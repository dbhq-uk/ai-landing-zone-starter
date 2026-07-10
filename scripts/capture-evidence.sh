#!/usr/bin/env bash
#
# capture-evidence.sh - capture proof that the deployed landing zone is private
# and cost-safe, as a JSON bundle and a rendered PNG evidence sheet.
#
# Runs read-only Azure CLI queries against the deployed resource group and
# produces, under ./evidence:
#   - evidence.json        the raw control-plane facts
#   - evidence-sheet.html  a styled one-page summary
#   - evidence-sheet.png   the same, rendered (needs wkhtmltoimage)
#
# This supports the repo's deploy-capture-destroy discipline: capture the proof
# from the API (stronger than a portal screenshot), then tear down.
#
# Usage:
#   scripts/capture-evidence.sh [resource_group] [output_dir]
# Resource group defaults to `terraform output -raw resource_group_name`.
#
# Requires: az (logged in), jq. PNG rendering also needs wkhtmltoimage.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RG="${1:-$(terraform -chdir="$ROOT_DIR" output -raw resource_group_name 2>/dev/null || true)}"
OUT_DIR="${2:-$ROOT_DIR/evidence}"

if [[ -z "${RG}" ]]; then
  echo "error: no resource group given and 'terraform output' is empty." >&2
  echo "usage: $0 [resource_group] [output_dir]" >&2
  exit 2
fi
if [[ "$(az group exists -n "$RG" 2>/dev/null)" != "true" ]]; then
  echo "error: resource group '$RG' does not exist - deploy before capturing." >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
STAMP="$(date -u +'%Y-%m-%d %H:%M UTC')"
echo "Capturing evidence for '$RG' ..."

# --- Money-pit resource types that must be ABSENT for a cost-safe deployment. -
declare -A MONEY_PIT=(
  ["Azure Firewall"]="Microsoft.Network/azureFirewalls"
  ["API Management"]="Microsoft.ApiManagement/service"
  ["Application Gateway"]="Microsoft.Network/applicationGateways"
  ["Bastion"]="Microsoft.Network/bastionHosts"
  ["Container Registry"]="Microsoft.ContainerRegistry/registries"
  ["Cosmos DB"]="Microsoft.DocumentDB/databaseAccounts"
  ["Virtual Machine"]="Microsoft.Compute/virtualMachines"
)

# --- Gather control-plane facts. ---------------------------------------------
INVENTORY_JSON="$(az resource list -g "$RG" --query "[].type" -o json)"
TOTAL="$(echo "$INVENTORY_JSON" | jq 'length')"

search_name="$(az resource list -g "$RG" --resource-type Microsoft.Search/searchServices --query "[0].name" -o tsv)"
kv_name="$(az resource list -g "$RG" --resource-type Microsoft.KeyVault/vaults --query "[0].name" -o tsv)"
acct_name="$(az resource list -g "$RG" --resource-type Microsoft.CognitiveServices/accounts --query "[0].name" -o tsv)"

search_json="$(az search service show -g "$RG" -n "$search_name" \
  --query "{name:name, sku:sku.name, publicNetworkAccess:publicNetworkAccess, replicas:replicaCount, partitions:partitionCount}" -o json)"
kv_json="$(az keyvault show -n "$kv_name" \
  --query "{name:name, publicNetworkAccess:properties.publicNetworkAccess}" -o json)"
acct_json="$(az cognitiveservices account show -g "$RG" -n "$acct_name" \
  --query "{name:name, publicNetworkAccess:properties.publicNetworkAccess}" -o json)"
models_json="$(az cognitiveservices account deployment list -g "$RG" -n "$acct_name" \
  --query "[].{name:name, model:properties.model.name, version:properties.model.version, sku:sku.name, capacity:sku.capacity}" -o json)"

pep_count="$(echo "$INVENTORY_JSON" | jq '[.[]|select(.=="Microsoft.Network/privateEndpoints")]|length')"
dns_count="$(echo "$INVENTORY_JSON" | jq '[.[]|select(.=="Microsoft.Network/privateDnsZones")]|length')"

# Money-pit presence check.
moneypit_json="{}"
for label in "${!MONEY_PIT[@]}"; do
  n="$(echo "$INVENTORY_JSON" | jq --arg t "${MONEY_PIT[$label]}" '[.[]|select(.==$t)]|length')"
  moneypit_json="$(echo "$moneypit_json" | jq --arg l "$label" --argjson n "$n" '. + {($l): $n}')"
done

# --- Write the JSON bundle. --------------------------------------------------
jq -n \
  --arg rg "$RG" --arg stamp "$STAMP" --argjson total "$TOTAL" \
  --argjson search "$search_json" --argjson kv "$kv_json" --argjson account "$acct_json" \
  --argjson models "$models_json" --argjson moneypit "$moneypit_json" \
  --argjson pep "$pep_count" --argjson dns "$dns_count" \
  '{resource_group:$rg, captured:$stamp, resource_count:$total,
    private_data_plane:{ai_search:$search, key_vault:$kv, ai_foundry:$account},
    models:$models, private_endpoints:$pep, private_dns_zones:$dns,
    money_pit_absent:$moneypit}' > "$OUT_DIR/evidence.json"

# --- Build the HTML evidence sheet. ------------------------------------------
priv_row() { # name | tier | public-access
  local pna="$3"; local ok="ok"; [[ "$pna" == "Disabled" ]] || ok="bad"
  printf '<tr><td>%s</td><td>%s</td><td class="%s">%s</td></tr>' "$1" "$2" "$ok" "$pna"
}
priv_rows="$(
  priv_row "AI Search ($(echo "$search_json" | jq -r .name))" "$(echo "$search_json" | jq -r '.sku+" x"+(.replicas|tostring)')" "$(echo "$search_json" | jq -r .publicNetworkAccess)"
  priv_row "Key Vault ($(echo "$kv_json" | jq -r .name))" "standard" "$(echo "$kv_json" | jq -r .publicNetworkAccess)"
  priv_row "AI Foundry ($(echo "$acct_json" | jq -r .name))" "AIServices" "$(echo "$acct_json" | jq -r .publicNetworkAccess)"
)"
model_rows="$(echo "$models_json" | jq -r '.[]|"<tr><td>"+.name+"</td><td>"+.model+" ("+.version+")</td><td>"+.sku+"</td></tr>"')"
inv_rows="$(echo "$INVENTORY_JSON" | jq -r 'group_by(.)|map({t:.[0],n:length})|sort_by(-.n)|.[]|"<tr><td>"+.t+"</td><td>"+(.n|tostring)+"</td></tr>"')"
mp_rows="$(echo "$moneypit_json" | jq -r 'to_entries|.[]|"<tr><td>"+.key+"</td><td class=\""+(if .value==0 then "ok" else "bad" end)+"\">"+(if .value==0 then "absent" else (.value|tostring)+" present" end)+"</td></tr>"')"

cat > "$OUT_DIR/evidence-sheet.html" <<HTML
<!doctype html><html><head><meta charset="utf-8"><style>
  body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1a2233;margin:32px;width:820px}
  h1{font-size:22px;margin:0 0 2px} .sub{color:#5a6472;font-size:13px;margin-bottom:20px}
  h2{font-size:14px;text-transform:uppercase;letter-spacing:.04em;color:#33507a;border-bottom:2px solid #e6ebf2;padding-bottom:4px;margin:22px 0 8px}
  table{border-collapse:collapse;width:100%;font-size:13px} td{padding:5px 8px;border-bottom:1px solid #eef1f5}
  td:first-child{color:#2a3448} .ok{color:#1a7f4b;font-weight:600} .bad{color:#b3261e;font-weight:600}
  .grid{display:flex;gap:24px} .grid>div{flex:1}
  .foot{margin-top:22px;color:#8a94a3;font-size:11px}
</style></head><body>
  <h1>Secure RAG landing zone - deployment evidence</h1>
  <div class="sub">Resource group <b>$RG</b> &nbsp;|&nbsp; $TOTAL resources &nbsp;|&nbsp; captured $STAMP</div>

  <h2>Private data plane (no public access)</h2>
  <table><tr><th></th><th></th><th></th></tr>$priv_rows</table>

  <div class="grid">
    <div>
      <h2>Models deployed</h2>
      <table>$model_rows</table>
      <h2>Private networking</h2>
      <table><tr><td>Private endpoints</td><td>$pep_count</td></tr><tr><td>Private DNS zones</td><td>$dns_count</td></tr></table>
    </div>
    <div>
      <h2>Money-pit check (all absent)</h2>
      <table>$mp_rows</table>
    </div>
  </div>

  <h2>Resource inventory</h2>
  <table>$inv_rows</table>

  <div class="foot">Generated from the Azure control plane by scripts/capture-evidence.sh - the authoritative API truth, not a rendered portal blade.</div>
</body></html>
HTML

# --- Render to PNG if wkhtmltoimage is available. -----------------------------
if command -v wkhtmltoimage >/dev/null 2>&1; then
  wkhtmltoimage --quiet --width 884 --quality 92 "$OUT_DIR/evidence-sheet.html" "$OUT_DIR/evidence-sheet.png"
  echo "Wrote $OUT_DIR/evidence-sheet.png"
else
  echo "note: wkhtmltoimage not found - HTML written, PNG skipped." >&2
fi

echo "Wrote $OUT_DIR/evidence.json and $OUT_DIR/evidence-sheet.html"
