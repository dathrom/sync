# =============================================================================
# identity.tf — Tożsamość aplikacji (Azure AD) dla Obszaru 2
# -----------------------------------------------------------------------------
# Tworzy rejestrację aplikacji + service principal + sekret. Ta "tożsamość
# usługowa" (client_id + client_secret) służy jako drugie źródło danych w Grafanie
# (scenariusz S2.3: reguły alertów/nagrywania korzystające z poświadczeń usługi,
# a nie zalogowanego użytkownika).
# UWAGA: wygenerowany sekret trafia do stanu Terraform i do outputs.tf (sensitive).
# =============================================================================

# Informacje o bieżącym koncie (używane m.in. jako właściciel app-reg i do nadania ról).
data "azuread_client_config" "current" {}

# Area-2 app-reg auth identity (S2.3 second data source for alerting/recording rules).
resource "azuread_application" "app_reg" {
  display_name = "xyz-grafmon-lab-area2"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "sp" {
  client_id = azuread_application.app_reg.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azuread_application_password" "app_password" {
  application_id = azuread_application.app_reg.id
  display_name   = "lab-secret"
}
