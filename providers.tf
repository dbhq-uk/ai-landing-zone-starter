provider "azurerm" {
  # subscription_id from the variable (or ARM_SUBSCRIPTION_ID).
  # Authenticate via Azure CLI / OIDC at apply time - never a committed secret.
  subscription_id = var.subscription_id
  features {}
}
