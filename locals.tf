locals {
  # --- CAF-aligned naming ----------------------------------------------------
  # Pattern: <resource-type-abbreviation>-<workload>-<environment>-<region>
  # (Microsoft Cloud Adoption Framework). Storage drops the delimiters because
  # storage account names must be 3-24 lowercase alphanumerics, globally unique.
  # Globally-unique resources (Foundry account, AI Search, Key Vault, Storage,
  # ACR) carry a short random suffix - the same approach as the official
  # Azure/naming module's `name_unique` - to avoid cross-tenant collisions.
  name_stem        = "${var.workload}-${var.environment}-${var.region_abbreviation}" # e.g. airag-prod-uks
  name_stem_nodash = "${var.workload}${var.environment}${var.region_abbreviation}"   # e.g. airagproduks
  unique           = random_string.name_unique.result

  names = {
    resource_group         = "rg-${local.name_stem}"
    virtual_network        = "vnet-${local.name_stem}"
    network_security_group = "nsg-${local.name_stem}"
    log_analytics          = "log-${local.name_stem}"
    container_app_env      = "cae-${local.name_stem}"
    ai_project             = "proj-${local.name_stem}"

    # Globally-unique names carry the random suffix; substr guards the 24-char
    # limits (Key Vault, Storage, ACR) against long token combinations. The
    # suffix sits last, so any trim only shortens entropy, never breaks the name.
    ai_foundry      = "aif-${local.name_stem}-${local.unique}"
    ai_search       = "srch-${local.name_stem}-${local.unique}"
    key_vault       = substr("kv-${local.name_stem}-${local.unique}", 0, 24)
    storage_account = substr("st${local.name_stem_nodash}${local.unique}", 0, 24)

    # Flag-gated edge resources, so enabling a flag also yields a CAF name.
    firewall            = "afw-${local.name_stem}"
    bastion             = "bas-${local.name_stem}"
    application_gateway = "agw-${local.name_stem}"
    api_management      = "apim-${local.name_stem}"
    container_registry  = substr("cr${local.name_stem_nodash}${local.unique}", 0, 24)
  }

  # Seeds the names the module generates itself (private endpoints, NICs, route
  # table, public IP, DNS links). It accepts only <=10 lowercase alphanumerics,
  # so it carries the workload token; those names stay module-controlled.
  module_name_prefix = var.workload

  # App Gateway: the module reads app_gateway_definition.deploy without try(), so
  # a null value errors at plan time and the object has five required maps. We
  # therefore always forward a complete, valid stub and only toggle deploy.
  app_gateway_definition = {
    deploy = var.enable_app_gateway
    name   = local.names.application_gateway
    backend_address_pools = {
      default = { name = "default-backend-pool" }
    }
    backend_http_settings = {
      default = { name = "default-http-settings", port = 80, protocol = "Http" }
    }
    frontend_ports = {
      default = { name = "default-frontend-port", port = 80 }
    }
    http_listeners = {
      default = { name = "default-listener", frontend_port_name = "default-frontend-port" }
    }
    request_routing_rules = {
      default = {
        name                       = "default-rule"
        rule_type                  = "Basic"
        http_listener_name         = "default-listener"
        backend_address_pool_name  = "default-backend-pool"
        backend_http_settings_name = "default-http-settings"
        priority                   = 100
      }
    }
  }

  # APIM: publisher_email/publisher_name are required even when deploy is false.
  # When enabled we pick the Developer SKU, not the module's Premium_3 default.
  apim_definition = {
    deploy          = var.enable_apim
    name            = local.names.api_management
    publisher_email = "noreply@dbhq.uk"
    publisher_name  = "DBHQ"
    sku_root        = "Developer"
    sku_capacity    = 1
  }
}
