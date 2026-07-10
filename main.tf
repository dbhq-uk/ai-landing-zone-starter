# Reference deployment of the official Azure AI Landing Zone.
#
# First real task: wire in the AVM pattern module and an opinionated golden-path
# config for the "secure RAG / AI-app for a regulated UK SME" scenario. Check the
# current module version and inputs before uncommenting.
#
#   module "ai_landing_zone" {
#     source  = "Azure/avm-ptn-aiml-landing-zone/azurerm"
#     version = "~> 0.1" # confirm latest on the Terraform Registry
#
#     # ... opinionated golden-path inputs for the scenario ...
#     # money-pit resources (firewall, ddos, app gateway) default OFF via variables.
#   }
