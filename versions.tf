terraform {
  required_version = ">= 1.9, < 2.0"

  backend "azurerm" {
    resource_group_name  = "rg-dbhq-housekeeping"
    storage_account_name = "dbhqtfstateuks01"
    container_name       = "tfstate"
    key                  = "ai-landing-zone-starter.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
    modtm = {
      source  = "azure/modtm"
      version = "~> 0.3"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}
