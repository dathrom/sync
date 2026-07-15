# Tożsamość aplikacji (Azure AD) na potrzeby Obszaru 2. Robimy rejestrację aplikacji,
# service principal i sekret. Ta para (client_id + client_secret) idzie jako drugie
# źródło danych w Grafanie — scenariusz S2.3, gdzie reguły alertów/nagrywania jadą
# na poświadczeniach usługi zamiast zalogowanego użytkownika.
# Uwaga: wygenerowany sekret ląduje w stanie Terraform i w outputs.tf (sensitive).

# Dane bieżącego konta — użyjemy ich jako właściciela app-reg i przy nadaniach ról.
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
