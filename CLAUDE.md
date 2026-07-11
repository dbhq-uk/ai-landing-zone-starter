# ai-landing-zone-starter - working notes

Public proof-of-worth repo for DBHQ Consulting. An opinionated reference *deployment* of a secure Azure AI landing zone, built **on** the official `Azure/avm-ptn-aiml-landing-zone` Verified Module - not a reinvented module.

## What matters here

- **Build on the AVM module, do not reinvent it.** Check the current `avm-ptn-aiml-landing-zone` version and inputs first; the root module here only adds opinion (golden-path config, guardrails, scenario), never duplicates what the AVM module already does.
- **The README is half the product.** The decision log and Well-Architected mapping ("what good looks like and why") are the consulting value - keep them current with the code.
- **Cost safety is non-negotiable.** Money-pit resources feature-flagged off by default; deploy-capture-destroy every session; remote state in the `azure-housekeeping` backend.

## Conventions

- Terraform: `terraform fmt` before committing; keep `validate`, `tflint`, `checkov` green.
- No secrets or real subscription ids in the repo. `terraform.tfvars` is gitignored; authenticate via `az login` / OIDC.
- British English, plain hyphens (never em/en dashes), conventional-commit messages.

## Provenance

- Commits authored **Daniel Grimes <dan@dbhq.uk>** (repo-local git identity).
- No AI attribution anywhere: no `Co-Authored-By` trailer, no "Generated with" lines, no mention of AI assistants in commits, PRs, README or repo content. This is proof-of-worth - the history must read as Dan's work.
