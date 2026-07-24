# 07 — Decyzje projektowe i pułapki

[◄ Scenariusze demo](06-scenarios.md) · [README](README.md) · [Self-hosted Grafana ►](08-self-hosted-grafana-analysis.md)

Świadome decyzje wychwycone z komentarzy w kodzie, z odniesieniami do plików i linii.

## Grafana i źródła danych

### Dlaczego data source tworzy skrypt, a nie Terraform
Azure Managed Grafana **wyłącza konta usługowe**, więc provider Grafany nie ma jak się
zalogować do data‑plane. Konfigurację źródeł kodyfikuje `configure-grafana.sh` przez
`az grafana` na sesji `az login` operatora
([configure-grafana.sh:1‑14](../grafana-poc-example/terraform/configure-grafana.sh#L1-L14)).

### Interfejs Grafany zostaje publiczny
`public_network_access_enabled = true` — celowo. Prywatyzowane są **dane i źródła**
(PE do AMW‑A, MPE→PLS do OSS Prometheusa), nie sam UI
([grafana.tf:6‑7,16](../grafana-poc-example/terraform/grafana.tf#L6-L7)).

### SKU Standard jest wymuszony
Bez SKU `Standard` nie da się tworzyć Managed Private Endpoints — a to na nich stoi
prywatna ścieżka S1.6 ([grafana.tf:13](../grafana-poc-example/terraform/grafana.tf#L13)).

## Monitoring

### Dwa AMW to celowa demonstracja, nie redundancja
AMW‑A (managed add‑on, prywatna) i AMW‑B (self‑hosted `remote_write`, publiczna) pokazują dwie
różne ścieżki zbierania i dwa modele dostępu
([monitoring.tf:1‑13](../grafana-poc-example/terraform/monitoring.tf#L1-L13)).

### `kind` w DCR celowo pusty
Reguły DCR dla Prometheusa nie korzystają z wariantów Linux/Windows/AgentDirectToStore
([monitoring.tf:33‑37](../grafana-poc-example/terraform/monitoring.tf#L33-L37)).

## RBAC / tożsamości

### Podwójne nadanie Metrics Publisher na DCR‑A
Nie było pewne, której tożsamości używa `ama-metrics` (control‑plane MI vs kubelet MI), a
samo powiązanie DCR może autoryzować z automatu. Nadano **obu** — nadmiarowo, ale bezpiecznie,
by ingest nie padł na 403 ([rbac.tf:44‑62](../grafana-poc-example/terraform/rbac.tf#L44-L62)).

### Usunięty app registration / SP (S2.3)
Środowisko nie ma uprawnień do rejestracji aplikacji, więc `apply` na te zasoby by się
wywalił. Usunięto z `identity.tf`; jedyna strata to fallback SP w źródle Azure Monitor
([identity.tf:3‑12](../grafana-poc-example/terraform/identity.tf#L3-L12),
[rbac.tf:36‑40](../grafana-poc-example/terraform/rbac.tf#L36-L40)).

### Owner ≠ dostęp do danych Grafany
Trzeba jawnej roli Grafana (Admin/Viewer). Stąd `configurator_object_id` dla przypadku, gdy
skrypt odpala inne konto niż `terraform apply`
([variables.tf:44‑54](../grafana-poc-example/terraform/variables.tf#L44-L54),
[terraform.tfvars:13‑18](../grafana-poc-example/terraform/terraform.tfvars#L13-L18)).

## Sieć / DNS

### Jawna Private DNS zone (nie auto z PE)
Zadeklarowana wprost, żeby `terraform destroy` sprzątał bez osieroconych rekordów
([dns.tf:13‑15](../grafana-poc-example/terraform/dns.tf#L13-L15)).

### AMW‑B celowo bez PE/DNS
Brak DNS na PE→AMW‑B to właśnie to, co pozwala pokazać NXDOMAIN (S1.3). Ten PE stawia się
ręcznie z CLI i taguje `lab=cli` ([dns.tf:34‑35](../grafana-poc-example/terraform/dns.tf#L34-L35)).

### Warunki działania PLS
`private_link_service_network_policies_enabled = false` na `snet-aks`
([network.tf:26‑28](../grafana-poc-example/terraform/network.tf#L26-L28)) **oraz** rola
`Network Contributor` MI klastra na `vnet-lab`
([rbac.tf:73‑81](../grafana-poc-example/terraform/rbac.tf#L73-L81)) — inaczej internal LB
zostaje `<pending>` (403 na odczyt subnetu).

## Skrypty / operacyjne

### Twarda walidacja pustych wartości w `deploy-k8s.sh`
`set -e` nie łapie samej pustej zmiennej (`az` zwraca 0 przy polach null). Pusta wartość
skleiłaby wadliwy URL `remote_write` i AMW‑B nigdy nie przyjęłaby metryk — stąd jawne guardy
([deploy-k8s.sh:59‑65](../grafana-poc-example/terraform/k8s/deploy-k8s.sh#L59-L65)).

### `client_id` kubeleta nie może być pusty
Pusty wybrałby system‑assigned MI, którego węzły nie mają; `deploy-k8s.sh` podstawia
`aks_kubelet_client_id`
([prometheus-values.yaml:16‑18](../grafana-poc-example/terraform/k8s/prometheus-values.yaml#L16-L18)).

### `teardown.sh` przed `terraform destroy`
Ręcznie tworzone zasoby (Grafana MPE, PE `lab=cli`, grupy reguł, sprywatyzowane AMW) blokują
`destroy` (np. PE w subnecie = 409). `teardown.sh` je kasuje i przywraca publiczny dostęp do
AMW ([teardown.sh:1‑17](../grafana-poc-example/terraform/teardown.sh#L1-L17)).

## Ograniczenia labu (świadomie oszczędne)

| Decyzja | Wartość | Powód |
|---|---|---|
| AKS SKU | `Free` | Brak SLA na API server — akceptowalne dla labu ([aks.tf:16](../grafana-poc-example/terraform/aks.tf#L16)) |
| Node pool | 1× `Standard_B2ms`, `os_disk_type=Managed` | Temp disk B2ms za mały na ephemeral OS ([aks.tf:18‑24](../grafana-poc-example/terraform/aks.tf#L18-L24)) |
| Brak OMS/Container Insights | wyłączone | Nie chcemy płatnego Log Analytics ([aks.tf:48](../grafana-poc-example/terraform/aks.tf#L48)) |
| Prometheus PV | `enabled: false` | Krótkotrwały lab ([prometheus-values.yaml:48‑49](../grafana-poc-example/terraform/k8s/prometheus-values.yaml#L48-L49)) |
| alertmanager / pushgateway | wyłączone | Niepotrzebne w tym labie ([prometheus-values.yaml:63‑67](../grafana-poc-example/terraform/k8s/prometheus-values.yaml#L63-L67)) |
| `grafana_major_version` | `12` | v11 EOL 2026‑06‑15 ([grafana.tf:14](../grafana-poc-example/terraform/grafana.tf#L14)) |
