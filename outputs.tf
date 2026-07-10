# The AVM module's own outputs are sparse (resource_id is a hardcoded "tbd"
# placeholder in v0.5.1), so we surface only what is usable plus our own naming.

output "resource_group_name" {
  description = "Resource group the landing zone deploys into."
  value       = local.names.resource_group
}

output "location" {
  description = "Azure region the landing zone deploys into."
  value       = var.location
}

output "virtual_network" {
  description = "The created virtual network object (null if a BYO VNet is ever used)."
  value       = try(module.ai_landing_zone.virtual_network, null)
}

output "subnets" {
  description = "Map of deployed subnets and their address prefixes."
  value       = try(module.ai_landing_zone.subnets, null)
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace id used for diagnostics."
  value       = try(module.ai_landing_zone.log_analytics_workspace_id, null)
}

output "apim" {
  description = "APIM module object when the AI gateway is enabled; null otherwise."
  value       = try(module.ai_landing_zone.apim, null)
}
