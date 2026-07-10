provider "azurerm" {
  # subscription_id from the variable (or ARM_SUBSCRIPTION_ID).
  # Authenticate via Azure CLI / OIDC at apply time - never a committed secret.
  subscription_id     = var.subscription_id
  storage_use_azuread = true

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    # Purge soft-delete-capable resources on destroy so deploy-capture-destroy
    # cycles do not collide with soft-deleted name reservations.
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

provider "azapi" {}
