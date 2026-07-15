# Co i w jakich wersjach ciągnie ten projekt:
#   azurerm - zasoby Azure (grupy zasobów, AKS, Grafana, monitoring)
#   azuread - obiekty Azure AD / Entra ID (rejestracja aplikacji, service principal)
# Logujemy się "z otoczenia", czyli po zwykłym `az login`. Żadnych sekretów w kodzie.

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 2.50"
    }
  }
}

# Provider Azure. Pusty blok features {} musi tu być, taki wymóg.
# subscription_id mówi, w której subskrypcji to wszystko wyląduje.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Azure AD provider bierze poświadczenia z bieżącej sesji az CLI, bez client_secret w kodzie.
# Uses ambient az CLI credentials; no client_secret here.
provider "azuread" {}
