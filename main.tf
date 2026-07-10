# Secure RAG / AI-app landing zone for a regulated UK SME, built on the official
# Azure Verified Module. This root module adds only opinion and guardrails - it
# does not reinvent anything the pattern module already does.
#
# Golden path: a minimal, genuinely-private RAG platform (AI Foundry + one
# project + two GlobalStandard models + one Basic AI Search + Key Vault + Storage
# + Container App environment + Log Analytics), with every money-pit resource
# flagged off. See README.md for the decision log and Well-Architected mapping.

# Short random suffix for the globally-unique resource names (see locals.tf).
resource "random_string" "name_unique" {
  length  = 5
  special = false
  upper   = false
}

module "ai_landing_zone" {
  source  = "Azure/avm-ptn-aiml-landing-zone/azurerm"
  version = "0.5.1"

  location            = var.location
  resource_group_name = local.names.resource_group
  name_prefix         = local.module_name_prefix
  enable_telemetry    = var.enable_telemetry
  tags                = var.tags

  # Standalone: no shared platform hub exists, so the module must create its own
  # private DNS zones - otherwise the private endpoints have nowhere to resolve
  # and the "private RAG" story does not actually work. Edge appliances are then
  # explicitly disabled below for cost. In a real ALZ set this true and inherit
  # the hub firewall plus central private DNS.
  flag_platform_landing_zone = false
  use_internet_routing       = true # no firewall: send egress straight to the internet

  vnet_definition = {
    name          = local.names.virtual_network
    address_space = ["192.168.0.0/20"] # must sit in 192.168.0.0/16 for Foundry capability-host injection
  }
  nsgs_definition = { name = local.names.network_security_group }

  # --- AI core (the actual workload) ---
  ai_foundry_definition = {
    purge_on_destroy = true
    ai_foundry = {
      name                       = local.names.ai_foundry
      create_ai_agent_service    = false # no agent runtime -> no mandatory Cosmos
      enable_diagnostic_settings = true
    }
    # Model pair chosen for cost and for what a fresh Sponsorship subscription
    # actually has GlobalStandard quota for: a small, current chat model and the
    # cheaper embedding model - the sensible default for a cost-conscious SME.
    # Raise to gpt-4.1 / text-embedding-3-large once quota is granted.
    ai_model_deployments = {
      "gpt-5-mini" = {
        name  = "gpt-5-mini"
        model = { format = "OpenAI", name = "gpt-5-mini", version = "2025-08-07" }
        scale = { type = "GlobalStandard", capacity = 10 } # GlobalStandard = pay-per-token, never PTU
      }
      "text-embedding-3-small" = {
        name  = "text-embedding-3-small"
        model = { format = "OpenAI", name = "text-embedding-3-small", version = "1" }
        scale = { type = "GlobalStandard", capacity = 10 }
      }
    }
    # Foundation BYOR: Key Vault + Storage (required), plus one Basic AI Search as
    # the RAG index, connected to the project below.
    key_vault_definition       = { this = { name = local.names.key_vault } }
    storage_account_definition = { this = { name = local.names.storage_account, endpoints = { blob = { type = "blob" } } } }
    ai_search_definition = {
      this = {
        name          = local.names.ai_search
        sku           = "basic" # Basic is the private-link floor; no consumption tier exists
        replica_count = 1
      }
    }
    ai_projects = {
      rag = {
        name         = local.names.ai_project
        description  = "Secure RAG workload for a regulated UK SME"
        display_name = "Secure RAG"
        # The module couples project auto-connections to a mandatory Cosmos DB
        # role assignment. Cosmos' only consumer - the agent service - is off, so
        # we leave auto-connection off rather than pay for an unused Cosmos DB.
        # The project, both models, the search index, Key Vault and Storage all
        # still deploy privately; enabling connections is a one-line change that
        # also switches Cosmos on.
        create_project_connections = false
      }
    }
  }

  # --- App runtime (Consumption -> near-zero idle) plus observability ---
  container_app_environment_definition = { name = local.names.container_app_env, enable_diagnostic_settings = true }
  law_definition                       = { name = local.names.log_analytics }

  # --- Duplicate / idle top-level services OFF ---
  # The platform Key Vault stays off unless an ops VM is enabled - the build and
  # jump VMs store their generated admin credentials there.
  genai_key_vault_definition          = { deploy = var.enable_build_vm || var.enable_jump_vm }
  genai_cosmosdb_definition           = { deploy = false }
  genai_storage_account_definition    = { deploy = false }
  genai_app_configuration_definition  = { deploy = false }
  genai_container_registry_definition = { deploy = var.enable_container_registry, name = local.names.container_registry }
  ks_ai_search_definition             = { deploy = false } # RAG search is the Foundry BYOR one
  ks_bing_grounding_definition        = { deploy = false } # public grounding contradicts "private"

  # --- Money-pit edge, flag-gated OFF by default ---
  firewall_definition    = { deploy = var.enable_firewall, name = local.names.firewall }
  bastion_definition     = { deploy = var.enable_bastion, name = local.names.bastion }
  jumpvm_definition      = { deploy = var.enable_jump_vm }
  buildvm_definition     = { deploy = var.enable_build_vm }
  app_gateway_definition = local.app_gateway_definition
  apim_definition        = local.apim_definition
}
