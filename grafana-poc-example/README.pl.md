# Grafana PoC — laboratorium monitoringu na Azure (opis po polsku)

Ten katalog zawiera kompletny przykład (PoC) wdrożenia **Azure Managed Grafana**
podłączonej do **dwóch przestrzeni Azure Monitor Workspace (AMW)** z metrykami
Prometheus, uruchamianego w oparciu o **Terraform** + kilka skryptów pomocniczych.
Celem laboratorium jest zademonstrowanie różnych ścieżek zbierania metryk oraz
prywatnej (Private Link) i publicznej łączności między komponentami.

## Co powstaje (architektura w skrócie)

```
                       ┌──────────────────────────┐
                       │   Azure Managed Grafana   │  (publiczna, SKU Standard)
                       │   tożsamość SystemAssigned │
                       └────────────┬──────────────┘
              odczyt metryk (MSI)   │   odczyt (MPE → prywatnie)
        ┌────────────────┬──────────┴───────────┬─────────────────────┐
        ▼                ▼                        ▼                     ▼
   ┌─────────┐     ┌─────────┐          ┌──────────────────┐   ┌──────────────┐
   │  AMW-A  │     │  AMW-B  │          │ self-hosted Prom │   │ Azure Monitor│
   │(prywatna)│    │(publ.)  │          │  (w AKS, PLS)    │   │  (Obszar 2)  │
   └────▲────┘     └────▲────┘          └────────▲─────────┘   └──────────────┘
        │ DCR-A         │ DCR-B (remote_write)    │
   ┌────┴───────────────┴─────────────────────────┴────┐
   │                    Klaster AKS                     │
   │  • dodatek managed-Prometheus (ama-metrics) → AMW-A │
   │  • samodzielny Prometheus (Helm)          → AMW-B   │
   └────────────────────────────────────────────────────┘
```

- **AMW-A** — zasilana automatycznie przez dodatek *managed Prometheus* w AKS
  (agent `ama-metrics`, kierowanie przez regułę DCR-A). Prywatyzowana za pomocą
  Private Endpointu i prywatnej strefy DNS.
- **AMW-B** — zasilana przez *samodzielny Prometheus* (instalowany Helmem po
  wdrożeniu) mechanizmem `remote_write` przez DCR-B. Pozostaje publiczna.
- **Grafana** — sama pozostaje publiczna; prywatyzujemy jedynie źródła danych
  (przez Managed Private Endpoints).

## Struktura katalogów i plików

```
grafana-poc-example/
└── terraform/
    ├── providers.tf        # Providery (azurerm, azuread) i wymagania Terraform
    ├── variables.tf        # Zmienne wejściowe (subskrypcja, region, tagi, user testowy)
    ├── terraform.tfvars    # Konkretne wartości zmiennych dla tego wdrożenia
    ├── locals.tf           # Wspólne tagi doklejane do wszystkich zasobów
    ├── main.tf             # Grupa zasobów (fundament)
    ├── network.tf          # Sieci wirtualne i podsieci (vnet-lab, vnet-b)
    ├── dns.tf              # Prywatna strefa DNS + Private Endpoint do AMW-A
    ├── aks.tf              # Klaster AKS + podpięcie do managed Prometheus (DCR-A)
    ├── monitoring.tf       # AMW-A, AMW-B oraz ich pary DCE/DCR
    ├── grafana.tf          # Azure Managed Grafana
    ├── identity.tf         # Rejestracja aplikacji + SP + sekret (Obszar 2)
    ├── rbac.tf             # Wszystkie nadania ról (RBAC) spinające uprawnienia
    ├── outputs.tf          # Wartości wyjściowe (czytane przez skrypty)
    │
    ├── configure-grafana.sh  # Po apply: tworzy źródła danych w Grafanie (az grafana)
    ├── teardown.sh           # Przed destroy: usuwa zasoby tworzone ręcznie (CLI)
    │
    └── k8s/
        ├── deploy-k8s.sh          # Po apply: instaluje self-hosted Prometheus (→ AMW-B)
        ├── prometheus-values.yaml # Wartości Helm dla Prometheusa (remote_write, PLS)
        └── debug-pod.yaml         # Pod diagnostyczny (netshoot) do prób DNS/sieci
```

> Pliki zaczynające się od `._` to metadane systemu macOS (AppleDouble) — nie są
> częścią projektu i można je zignorować.

## Kolejność użycia

1. `terraform init && terraform apply` — tworzy całą infrastrukturę.
2. `k8s/deploy-k8s.sh` — instaluje samodzielny Prometheus i pod diagnostyczny.
3. `configure-grafana.sh` — konfiguruje 4 źródła danych w Grafanie.
4. (demo) scenariusze S1.x / S2.x wykonywane ręcznie przez `az CLI`.
5. Sprzątanie: `teardown.sh <rg> <grafana>` **przed** `terraform destroy`.

## Model uwierzytelniania (kto jak się loguje)

- **Grafana → AMW-A / AMW-B**: tożsamość zarządzana Grafany (MSI) z rolą
  *Monitoring Data Reader*.
- **Dodatek AKS → AMW-A**: tożsamość AKS z rolą *Monitoring Metrics Publisher* na DCR-A.
- **Self-hosted Prometheus → AMW-B**: tożsamość kubeleta (węzła) pobierana z IMDS,
  blok `azuread` w remote_write, rola *Monitoring Metrics Publisher* na DCR-B.
- **Źródło Azure Monitor (Obszar 2)**: tożsamość zalogowanego użytkownika, a
  zapasowo service principal z pliku `identity.tf`.

Szczegółowe wyjaśnienia znajdują się w komentarzach (po polsku) w poszczególnych plikach.
