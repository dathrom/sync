# Tożsamość bieżącego konta (Azure AD).
#
# Wcześniej ten plik tworzył też rejestrację aplikacji "xyz-grafmon-lab-area2" +
# service principal + sekret, jako drugie ("service credential") źródło danych w
# Grafanie dla scenariusza S2.3 (reguły alertów/nagrywania na poświadczeniach
# usługi, nie zalogowanego użytkownika). USUNIĘTE: środowisko nie ma uprawnień do
# tworzenia rejestracji aplikacji (brak roli typu Application Administrator /
# "Users can register applications" wyłączone dla zwykłych userów) —
# `terraform apply` na te zasoby się nie powiedzie. Reszta PoC (wszystkie S1.x,
# k8s/deploy-k8s.sh) w ogóle nie zależy od tej tożsamości. Jedyna strata: brak
# fallbacku w źródle AzMon-CurrentUser (patrz configure-grafana.sh/.ps1) — S2.3 w
# tej postaci nie jest dziś demonstrowalne.

# Dane bieżącego konta — używane jako właściciel roli Grafana Admin (rbac.tf).
data "azuread_client_config" "current" {}
