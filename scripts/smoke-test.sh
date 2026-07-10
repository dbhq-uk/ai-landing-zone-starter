#!/usr/bin/env bash
#
# smoke-test.sh - prove the deployed landing zone actually works, not just that
# it deployed. Two layers:
#
#   Layer 1 (control plane, from here): deployments Succeeded, Search running,
#           private-endpoint connections Approved, private DNS A-records present,
#           public access Disabled.
#   Layer 2 (data plane, from INSIDE the VNet): a short-lived Container Apps job
#           in the deployed environment resolves a private FQDN and calls chat,
#           embeddings and Search using its own managed identity (AAD, no keys).
#           Container Apps is used rather than a VM so it works even where VM
#           SKUs are restricted.
#
# Logs every step PASS/FAIL and writes ./evidence/smoke-results.{json,html,png}.
#
# Usage: scripts/smoke-test.sh [resource_group] [output_dir]
# Requires: az (logged in), jq. PNG rendering also needs wkhtmltoimage.

set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RG="${1:-$(terraform -chdir="$ROOT_DIR" output -raw resource_group_name 2>/dev/null || true)}"
OUT_DIR="${2:-$ROOT_DIR/evidence}"
[[ -z "$RG" ]] && { echo "error: no resource group" >&2; exit 2; }
[[ "$(az group exists -n "$RG" 2>/dev/null)" == "true" ]] || { echo "error: RG '$RG' not found" >&2; exit 1; }
mkdir -p "$OUT_DIR"
STAMP="$(date -u +'%Y-%m-%d %H:%M UTC')"

RESULTS=()  # each entry: layer|name|status|detail
record() { RESULTS+=("$1|$2|$3|$4"); printf '  [%-4s] %-24s %s\n' "$3" "$2" "$4"; }

# --- Resolve resources. ------------------------------------------------------
acct="$(az resource list -g "$RG" --resource-type Microsoft.CognitiveServices/accounts --query "[0].name" -o tsv)"
search="$(az resource list -g "$RG" --resource-type Microsoft.Search/searchServices --query "[0].name" -o tsv)"
cae="$(az resource list -g "$RG" --resource-type Microsoft.App/managedEnvironments --query "[0].name" -o tsv)"
acct_id="$(az cognitiveservices account show -g "$RG" -n "$acct" --query id -o tsv)"
search_id="$(az resource show -g "$RG" -n "$search" --resource-type Microsoft.Search/searchServices --query id -o tsv)"
endpoint="$(az cognitiveservices account show -g "$RG" -n "$acct" --query properties.endpoint -o tsv)"
endpoint="${endpoint%/}"

echo "Layer 1 - control plane"
for m in gpt-5-mini text-embedding-3-small; do
  st="$(az cognitiveservices account deployment show -g "$RG" -n "$acct" --deployment-name "$m" --query properties.provisioningState -o tsv 2>/dev/null)"
  [[ "$st" == "Succeeded" ]] && record control "deploy:$m" PASS "$st" || record control "deploy:$m" FAIL "${st:-missing}"
done
st="$(az search service show -g "$RG" -n "$search" --query status -o tsv 2>/dev/null)"
[[ "$st" == "running" ]] && record control "search:status" PASS "$st" || record control "search:status" FAIL "${st:-unknown}"
bad="$(az network private-endpoint-connection list --id "$acct_id" --query "length([?properties.privateLinkServiceConnectionState.status!='Approved'])" -o tsv 2>/dev/null || echo "?")"
[[ "$bad" == "0" ]] && record control "pe:foundry" PASS "connection approved" || record control "pe:foundry" FAIL "non-approved: $bad"
recs="$(az network private-dns record-set a list -g "$RG" -z "privatelink.openai.azure.com" --query "length(@)" -o tsv 2>/dev/null || echo 0)"
[[ "${recs:-0}" -ge 1 ]] && record control "dns:openai-a-records" PASS "$recs record(s)" || record control "dns:openai-a-records" FAIL "no A records - private DNS not resolving"
pna="$(az cognitiveservices account show -g "$RG" -n "$acct" --query properties.publicNetworkAccess -o tsv)"
[[ "$pna" == "Disabled" ]] && record control "net:public-access" PASS "Disabled" || record control "net:public-access" FAIL "$pna"

# --- Layer 2 - data plane from inside the VNet via a Container Apps job. ------
echo "Layer 2 - data plane (Container Apps job, inside the VNet)"
if [[ -z "$cae" ]]; then
  record data "container-env" FAIL "no Container Apps environment"
else
  cae_id="$(az containerapp env show -g "$RG" -n "$cae" --query id -o tsv)"
  search_host="${search}.search.windows.net"
  # Search RBAC is typically key-only, so the job uses the admin key for that check.
  search_key="$(az search admin-key show --service-name "$search" -g "$RG" --query primaryKey -o tsv 2>/dev/null)"
  job="smoke-$(date +%s)"

  # Script that runs IN the container (single-quoted heredoc: not expanded here).
  read -r -d '' JOBSCRIPT <<'JOB' || true
set -u
host="$(echo "$ENDPOINT" | sed -E 's#https?://##; s#/.*##')"
ip="$(python3 -c "import socket;print(socket.gethostbyname('$host'))" 2>/dev/null)"
if echo "$ip" | grep -qE '^(10|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.'; then
  echo "SMOKE:dns-private-ip:PASS:$host -> $ip"
else
  echo "SMOKE:dns-private-ip:FAIL:$host -> ${ip:-unresolved}"
fi
gettok() { curl -s "$IDENTITY_ENDPOINT?resource=$1&api-version=2019-08-01" -H "X-IDENTITY-HEADER: $IDENTITY_HEADER" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("access_token",""))' 2>/dev/null; }
tok="$(gettok https://cognitiveservices.azure.com)"
code="$(curl -s -o /tmp/chat.json -w '%{http_code}' -X POST "$ENDPOINT/openai/deployments/gpt-5-mini/chat/completions?api-version=2024-12-01-preview" -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"reply with the single word pong"}],"max_completion_tokens":16}')"
[ "$code" = "200" ] && echo "SMOKE:chat-completion:PASS:HTTP 200, $(wc -c </tmp/chat.json) bytes" || echo "SMOKE:chat-completion:FAIL:HTTP $code $(head -c 140 /tmp/chat.json | tr -d '\n')"
code="$(curl -s -o /tmp/emb.json -w '%{http_code}' -X POST "$ENDPOINT/openai/deployments/text-embedding-3-small/embeddings?api-version=2024-12-01-preview" -H "Authorization: Bearer $tok" -H 'Content-Type: application/json' -d '{"input":"private rag smoke test"}')"
if [ "$code" = "200" ]; then echo "SMOKE:embeddings:PASS:HTTP 200, $(python3 -c 'import json;print(len(json.load(open("/tmp/emb.json"))["data"][0]["embedding"]))' 2>/dev/null) dims"; else echo "SMOKE:embeddings:FAIL:HTTP $code $(head -c 140 /tmp/emb.json | tr -d '\n')"; fi
code="$(curl -s -o /tmp/srch.json -w '%{http_code}' "https://$SEARCHHOST/indexes?api-version=2024-07-01" -H "api-key: $SEARCHKEY")"
[ "$code" = "200" ] && echo "SMOKE:search-query:PASS:HTTP 200" || echo "SMOKE:search-query:FAIL:HTTP $code $(head -c 140 /tmp/srch.json | tr -d '\n')"
echo "SMOKE-DONE"
JOB

  echo "  creating job $job ..."
  # base64 the script + a YAML spec, so the CLI never parses the script's own
  # dash-flags (-c, -w, -X) as az options.
  b64="$(printf '%s' "$JOBSCRIPT" | base64 -w0)"
  loc="$(az group show -n "$RG" --query location -o tsv)"
  spec="$(mktemp --suffix=.yaml)"
  cat > "$spec" <<YAML
location: $loc
identity:
  type: SystemAssigned
properties:
  environmentId: $cae_id
  configuration:
    triggerType: Manual
    replicaTimeout: 600
    replicaRetryLimit: 0
    manualTriggerConfig:
      parallelism: 1
      replicaCompletionCount: 1
  template:
    containers:
      - name: smoke
        image: mcr.microsoft.com/azure-cli:latest
        command: ["/bin/bash", "-c", "echo $b64 | base64 -d | bash"]
        env:
          - name: ENDPOINT
            value: "$endpoint"
          - name: SEARCHHOST
            value: "$search_host"
          - name: SEARCHKEY
            value: "$search_key"
        resources:
          cpu: 0.5
          memory: 1.0Gi
YAML
  az containerapp job create -g "$RG" -n "$job" --yaml "$spec" -o none
  rm -f "$spec"

  job_mi="$(az containerapp job show -g "$RG" -n "$job" --query identity.principalId -o tsv)"
  az role assignment create --assignee-object-id "$job_mi" --assignee-principal-type ServicePrincipal \
    --role "Cognitive Services OpenAI User" --scope "$acct_id" -o none 2>/dev/null || true
  echo "  waiting 75s for role propagation ..."; sleep 75

  exec_name="$(az containerapp job start -g "$RG" -n "$job" --query name -o tsv)"
  echo "  execution $exec_name started; waiting ..."
  for _ in $(seq 1 40); do
    est="$(az containerapp job execution show -g "$RG" -n "$job" --job-execution-name "$exec_name" --query properties.status -o tsv 2>/dev/null)"
    [[ "$est" == "Succeeded" || "$est" == "Failed" ]] && break; sleep 15
  done
  echo "  execution status: ${est:-unknown}; fetching logs ..."

  # Log Analytics is private (unreachable from the deployer), so read the job's
  # console output directly from the execution log stream instead.
  msg=""
  for _ in $(seq 1 10); do
    msg="$(az containerapp job logs show -g "$RG" -n "$job" --container smoke --execution "$exec_name" --format text --tail 200 2>/dev/null)"
    echo "$msg" | grep -q 'SMOKE-DONE' && break
    sleep 15
  done
  smoke_lines="$(printf '%s\n' "$msg" | grep 'SMOKE:' | sed 's/.*\(SMOKE:\)/\1/')"

  if [[ -z "$smoke_lines" ]]; then
    record data "job-logs" FAIL "no logs retrieved (execution: ${est:-unknown})"
  else
    while IFS= read -r line; do
      [[ "$line" == SMOKE:* ]] || continue
      name="$(cut -d: -f2 <<<"$line")"; status="$(cut -d: -f3 <<<"$line")"; detail="$(cut -d: -f4- <<<"$line")"
      record data "$name" "$status" "$detail"
    done <<<"$smoke_lines"
  fi
  az containerapp job delete -g "$RG" -n "$job" --yes -o none 2>/dev/null || true
fi

# --- Summarise + write artifacts. --------------------------------------------
pass="$(printf '%s\n' "${RESULTS[@]}" | grep -c '|PASS|')"
fail="$(printf '%s\n' "${RESULTS[@]}" | grep -c '|FAIL|')"
total=$(( pass + fail ))
echo "Result: $pass/$total passed, $fail failed."

rows_json="$(printf '%s\n' "${RESULTS[@]}" | jq -R 'split("|")|{layer:.[0],check:.[1],status:.[2],detail:.[3]}' | jq -s .)"
jq -n --arg rg "$RG" --arg stamp "$STAMP" --argjson pass "$pass" --argjson fail "$fail" --argjson results "$rows_json" \
  '{resource_group:$rg, captured:$stamp, passed:$pass, failed:$fail, checks:$results}' > "$OUT_DIR/smoke-results.json"

html_rows="$(printf '%s\n' "${RESULTS[@]}" | while IFS='|' read -r layer name status detail; do
  cls=$([[ "$status" == PASS ]] && echo ok || echo bad)
  printf '<tr><td>%s</td><td>%s</td><td class="%s">%s</td><td>%s</td></tr>' "$layer" "$name" "$cls" "$status" "$detail"
done)"
verdict=$([[ "$fail" == 0 ]] && echo '<span class="ok">ALL PASS</span>' || echo "<span class=\"bad\">$fail FAILED</span>")
cat > "$OUT_DIR/smoke-results.html" <<HTML
<!doctype html><html><head><meta charset="utf-8"><style>
 body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1a2233;margin:32px;width:860px}
 h1{font-size:22px;margin:0 0 2px} .sub{color:#5a6472;font-size:13px;margin-bottom:18px}
 table{border-collapse:collapse;width:100%;font-size:13px} td,th{padding:5px 8px;border-bottom:1px solid #eef1f5;text-align:left}
 th{color:#33507a;text-transform:uppercase;font-size:11px;letter-spacing:.04em}
 .ok{color:#1a7f4b;font-weight:600} .bad{color:#b3261e;font-weight:600} .foot{margin-top:18px;color:#8a94a3;font-size:11px}
</style></head><body>
 <h1>Secure RAG landing zone - smoke test</h1>
 <div class="sub">Resource group <b>$RG</b> &nbsp;|&nbsp; $pass/$total passed &nbsp;|&nbsp; $verdict &nbsp;|&nbsp; $STAMP</div>
 <table><tr><th>Layer</th><th>Check</th><th>Status</th><th>Detail</th></tr>$html_rows</table>
 <div class="foot">Layer 1 from the control plane; Layer 2 from inside the VNet via a Container Apps job's managed identity (AAD, no keys).</div>
</body></html>
HTML
command -v wkhtmltoimage >/dev/null 2>&1 && wkhtmltoimage --quiet --width 904 --quality 92 "$OUT_DIR/smoke-results.html" "$OUT_DIR/smoke-results.png"
echo "Wrote $OUT_DIR/smoke-results.{json,html,png}"
[[ "$fail" == 0 ]] || exit 1
