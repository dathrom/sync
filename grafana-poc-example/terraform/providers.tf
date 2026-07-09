# =============================================================================
# providers.tf — Konfiguracja Terraform i dostawców (providers)
# -----------------------------------------------------------------------------
# Definiuje, których providerów i w jakich wersjach używa projekt:
#   - azurerm : zasoby platformy Azure (grupy zasobów, AKS, Grafana, monitoring)
#   - azuread : obiekty Azure AD / Entra ID (rejestracja aplikacji, service principal)
# Uwierzytelnianie opiera się na "otoczeniu" (ambient), czyli na bieżącym
# logowaniu `az login` — celowo NIE ma tu żadnych sekretów/haseł w kodzie.
# =============================================================================

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

# Provider Azure — blok features {} jest wymagany (może być pusty).
# subscription_id wskazuje subskrypcję, w której powstaną wszystkie zasoby.
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# Provider Azure AD korzysta z poświadczeń bieżącej sesji az CLI; brak client_secret w kodzie.
# Uses ambient az CLI credentials; no client_secret here.
provider "azuread" {}
