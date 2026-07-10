variable "subscription_id" {
  description = "The Azure subscription to deploy the reference AI landing zone into. Supply via TF_VAR_subscription_id or a gitignored terraform.tfvars - never commit it."
  type        = string
}

variable "location" {
  description = "Azure region for all resources. UK South for UK-SME data residency."
  type        = string
  default     = "uksouth"
}

variable "name_prefix" {
  description = "Short (<=10 lowercase alphanumeric) prefix seeding generated resource names."
  type        = string
  default     = "dbhqairag"

  validation {
    condition     = can(regex("^[a-z0-9]{1,10}$", var.name_prefix))
    error_message = "name_prefix must be 1-10 lowercase alphanumeric characters."
  }
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    workload    = "ai-landing-zone-starter"
    scenario    = "secure-rag-uk-sme"
    managed-by  = "terraform"
    cost-centre = "dbhq-proof-of-worth"
  }
}

variable "enable_telemetry" {
  description = "AVM module usage telemetry. Harmless deployment counter; leave on to be a good AVM citizen."
  type        = bool
  default     = true
}

# --- Money-pit feature flags: all default off for cost safety. ---

variable "enable_firewall" {
  description = "Deploy Azure Firewall (money-pit). In a real ALZ you inherit the hub firewall instead."
  type        = bool
  default     = false
}

variable "enable_bastion" {
  description = "Deploy Azure Bastion for private admin access (standing cost)."
  type        = bool
  default     = false
}

variable "enable_jump_vm" {
  description = "Deploy a jumpbox VM (standing cost)."
  type        = bool
  default     = false
}

variable "enable_build_vm" {
  description = "Deploy a build/DevOps VM with Owner on the resource group (standing cost plus broad rights)."
  type        = bool
  default     = false
}

variable "enable_app_gateway" {
  description = "Deploy Application Gateway plus WAF v2 (money-pit). Off by default; a valid stub is always forwarded to satisfy the module."
  type        = bool
  default     = false
}

variable "enable_apim" {
  description = "Deploy API Management as the AI gateway (token governance over OpenAI). Off by default; when on, uses the cheap Developer SKU, not the module's Premium_3."
  type        = bool
  default     = false
}

variable "enable_container_registry" {
  description = "Deploy Premium Azure Container Registry (only tier with private link). Off by default - nothing to store in the reference."
  type        = bool
  default     = false
}
