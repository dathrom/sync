# Grafana PoC — lab monitoringu na Azure

Ten katalog to gotowy przykład (PoC), jak wdrożyć **Azure Managed Grafana** wpiętą
w **dwie przestrzenie Azure Monitor Workspace (AMW)** z metrykami Prometheus. Całość
stoi na **Terraformie** plus kilka skryptów, które dokańczają robotę już po `apply`.
Chodziło o pokazanie różnych ścieżek zbierania metryk oraz prywatnej (Private Link)
i publicznej łączności między poszczególnymi klockami.

## Co z tego wychodzi (architektura w skrócie)

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

- **AMW-A** — leci automatycznie z dodatku *managed Prometheus* w AKS (agent
  `ama-metrics`, kierowanie regułą DCR-A). Tę przestrzeń prywatyzujemy Private
  Endpointem i prywatną strefą DNS.
- **AMW-B** — karmiona przez *self-hosted Prometheusa* (doinstalowanego Helmem już
  po wdrożeniu) mechanizmem `remote_write` przez DCR-B. Zostaje publiczna.
- **Grafana** — sama zostaje publiczna. Prywatyzujemy tylko źródła danych (przez
  Managed Private Endpoints), a nie sam interfejs Grafany.

## Co gdzie leży

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
    ├── rbac.tf             # Wszystkie nadania ról (RBAC)
    ├── outputs.tf          # Wartości wyjściowe (czytane przez skrypty)
    │
    ├── configure-grafana.sh  # Po apply: tworzy źródła danych w Grafanie (az grafana) — wariant bash
    ├── configure-grafana.ps1 # To samo w PowerShell (Windows)
    ├── teardown.sh           # Przed destroy: usuwa zasoby robione ręcznie z CLI
    │
    └── k8s/
        ├── deploy-k8s.sh          # Po apply: instaluje self-hosted Prometheus (→ AMW-B) — wariant bash
        ├── deploy-k8s.ps1         # To samo w PowerShell (Windows)
        ├── prometheus-values.yaml # Wartości Helm dla Prometheusa (remote_write, PLS)
        └── debug-pod.yaml         # Pod diagnostyczny (netshoot) do prób DNS/sieci
```

Skrypty pomocnicze mają dwa równoważne warianty: `.sh` (bash — Linux/macOS/Git Bash)
oraz `.ps1` (PowerShell — Windows). Robią to samo, wybierz zgodnie z systemem.

> Pliki zaczynające się od `._` to śmieci macOS (AppleDouble). Nie mają nic wspólnego
> z projektem, można je spokojnie olać.

## Kolejność

1. `terraform init && terraform apply` — stawia całą infrastrukturę.
2. `k8s/deploy-k8s.sh` (lub `.ps1`) — instaluje self-hosted Prometheusa i pod diagnostyczny.
3. `configure-grafana.sh` (lub `.ps1`) — dokłada 4 źródła danych w Grafanie.
4. (demo) scenariusze S1.x / S2.x robione ręcznie z `az CLI`.
5. Sprzątanie: `teardown.sh <rg> <grafana>` **przed** `terraform destroy`.

Wspólne dla obu skryptów: potrzebny zalogowany `az CLI`, a dla `deploy-k8s` dodatkowo
`kubectl` i `helm` (>= 3). Skrypty czytają dane z `terraform output`, więc odpalaj je
z katalogu, w którym leży stan Terraform.

### Uruchamianie na Windows (PowerShell)

```powershell
# 1) self-hosted Prometheus + pod diagnostyczny
powershell.exe -ExecutionPolicy Bypass -File .\k8s\deploy-k8s.ps1

# 2) źródła danych w Grafanie
powershell.exe -ExecutionPolicy Bypass -File .\configure-grafana.ps1
```

- **`-ExecutionPolicy Bypass`** omija politykę uruchamiania skryptów (skrypty nie są
  podpisane).
- **Ścieżka do `kubectl`** — `deploy-k8s.ps1` zapyta o nią na starcie. Wciśnij Enter,
  żeby wziąć `kubectl` z `PATH`, albo podaj pełną ścieżkę (np. `C:\k8s\kubectl.exe`) —
  wtedy wszystkie wywołania idą tą ścieżką. Można też podać z góry:
  `-KubectlPath C:\k8s\kubectl.exe`.
- **Za korporacyjnym proxy z inspekcją TLS** certyfikat API serwera AKS jest podpisany
  przez nieznane CA (`x509: certificate signed by unknown authority`). Uruchom wtedy
  `deploy-k8s.ps1` z przełącznikiem **`-InsecureSkipTlsVerify`** — wyłącza on weryfikację
  TLS dla wpisu klastra w kubeconfig (działa i dla `kubectl`, i dla `helm`).
  Bezpieczniejsza alternatywa to dodanie firmowego root CA do zaufanych certyfikatów
  maszyny — wtedy przełącznik nie jest potrzebny.
- Pliki `.ps1` są zapisane w ASCII, więc kodowanie nie ma znaczenia (Windows PowerShell 5.1
  odczyta je poprawnie).

## Kto się jak loguje

- **Grafana → AMW-A / AMW-B**: tożsamość zarządzana Grafany (MSI) z rolą
  *Monitoring Data Reader*.
- **Dodatek AKS → AMW-A**: tożsamość AKS z rolą *Monitoring Metrics Publisher* na DCR-A.
- **Self-hosted Prometheus → AMW-B**: tożsamość kubeleta (węzła) brana z IMDS, blok
  `azuread` w remote_write, rola *Monitoring Metrics Publisher* na DCR-B.
- **Źródło Azure Monitor (Obszar 2)**: tożsamość zalogowanego użytkownika, a awaryjnie
  service principal z pliku `identity.tf`.

Więcej szczegółów siedzi w komentarzach po polsku, w poszczególnych plikach.
