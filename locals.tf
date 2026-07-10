locals {
  resource_group_name = "rg-${var.name_prefix}-uks"

  # The Foundry BYOR storage auto-name (prefix + key + "fndrysa" + token) can
  # exceed the 24-char storage-account limit even from a valid name_prefix, so we
  # give it an explicit, bounded, globally-unique name instead.
  foundry_storage_name = "${var.name_prefix}sa${random_string.storage_suffix.result}"

  # App Gateway: the module reads app_gateway_definition.deploy without try(), so
  # a null value errors at plan time and the object has five required maps. We
  # therefore always forward a complete, valid stub and only toggle deploy.
  app_gateway_definition = {
    deploy = var.enable_app_gateway
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
    publisher_email = "noreply@dbhq.uk"
    publisher_name  = "DBHQ"
    sku_root        = "Developer"
    sku_capacity    = 1
  }
}
