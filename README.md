# ai-landing-zone-starter

An opinionated, deploy-ready **reference deployment** of a secure Azure AI landing zone for a regulated UK SME, built **on** Microsoft's official Azure AI Landing Zone Verified Module ([`Azure/avm-ptn-aiml-landing-zone`](https://registry.terraform.io/modules/Azure/avm-ptn-aiml-landing-zone/azurerm/latest)).

It is deliberately **not** a new landing-zone module - Microsoft's is official, AVM-based and maintained. The value here is the judgment layer their generic module does not carry: an opinionated golden-path configuration for one real scenario, deployed for real, with the cost and the decisions written down.

## What this delivers

- A thin, opinionated Terraform root module wrapping the AVM AI-landing-zone pattern module, with golden-path `tfvars` for a secure RAG / AI-app workload.
- Money-pit resources (Azure Firewall, DDoS, Application Gateway, provisioned throughput) expressed in code but feature-flagged **off** by default, so a demo never pays for always-on infrastructure.
- A README decision log + Well-Architected mapping, an architecture diagram, and a costed deploy / teardown.

## Status

Scaffold. The build is specified in the handoff brief that seeds it - the Terraform here is a starting skeleton (provider + variables) to keep CI meaningful; the AVM module wiring is the first real task.

## Cost discipline

One shared Azure credit backs this and the sibling repos. **Deploy -> capture (architecture, cost view) -> `terraform destroy`.** Consumption/serverless tiers only; never leave the money-pit resources running. Remote state lives in the shared backend from `azure-housekeeping`, so teardown stays reliable across sessions.

## CI

Static checks only (no cloud credentials in CI): `terraform fmt`/`validate`, `tflint` (+ Azure ruleset), `trivy` IaC scan, `gitleaks` secret scan.

## Licence

MIT - see [LICENSE](LICENSE).
