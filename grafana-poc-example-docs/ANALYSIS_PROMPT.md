# Prompt: analiza i dokumentacja labu Azure Managed Grafana + Prometheus

> Skopiuj poniższy blok jako polecenie dla Claude Code (lub subagenta). Prompt jest
> samodzielny — zakłada tylko dostęp do repo.

---

## PROMPT

Jesteś inżynierem platformy / SRE dokumentującym istniejący Proof-of-Concept.
Twoim zadaniem jest **przeanalizować** kod Terraform i skrypty w
`/Users/artur.prawdzik/repo/sync/grafana-poc-example/terraform` (wraz z podkatalogiem
`k8s/`) i wytworzyć **kompletną, estetyczną dokumentację techniczną** w formacie
Markdown, zapisaną w `/Users/artur.prawdzik/repo/sync/grafana-poc-example-docs`.

### Zakres analizy (przeczytaj WSZYSTKIE pliki, nie zgaduj)

Przejrzyj i zrozum każdy z plików; dla każdego ustal *co tworzy* i *dlaczego*:

- `main.tf`, `providers.tf`, `variables.tf`, `locals.tf`, `outputs.tf`, `terraform.tfvars*`
- `aks.tf` — klaster AKS, dodatek managed-Prometheus (`ama-metrics`), powiązania DCR
- `monitoring.tf` — Azure Monitor Workspaces (AMW-A/B), DCE, DCR, data flows
- `grafana.tf` — Azure Managed Grafana (SKU, tożsamość, sieć)
- `rbac.tf` — wszystkie `azurerm_role_assignment` (kto, jaka rola, na czym, po co)
- `network.tf`, `dns.tf` — VNety, subnety, Private Endpoint, Private DNS zone, PLS
- `identity.tf` — tożsamości i ograniczenia środowiska (brak app registration/SP)
- `configure-grafana.sh` / `configure-grafana.ps1` — tworzenie data source'ów, MPE→PLS
- `k8s/prometheus-values.yaml`, `k8s/deploy-k8s.sh/.ps1`, `k8s/debug-pod.yaml`
- `teardown.sh`, `.terraform.lock.hcl` (wersje providerów)

### Co musisz jednoznacznie wyjaśnić

1. **Przepływ metryk end-to-end** dla obu ścieżek:
   - AMW-A: AKS `ama-metrics` → DCR-A → AMW-A (ingest) → query endpoint → Grafana
   - AMW-B: self-hosted Prometheus (Helm) → `remote_write` (auth `azuread`/IMDS kubelet)
     → DCR-B → AMW-B → Grafana
2. **Jak Grafana łączy się ze źródłami** — data source typu `prometheus`, auth MSI,
   rola `Monitoring Data Reader`; dlaczego robi to skrypt `az grafana`, a nie Terraform
   (Managed Grafana wyłącza konta usługowe → provider Grafany nie zaloguje się).
3. **Model prywatyzacji** — Private Endpoint + Private DNS dla AMW-A; Managed Private
   Endpoint Grafany → Private Link Service dla self-hosted Prometheusa (S1.6);
   dlaczego AMW-B celowo NIE ma PE/DNS (demo NXDOMAIN, S1.3); dlaczego sam interfejs
   Grafany zostaje publiczny.
4. **Pełna macierz RBAC** — tabela: principal → rola → scope → uzasadnienie.
5. **Model tożsamości i uwierzytelniania** na każdym styku (kubelet vs control-plane MI,
   IMDS, MSI Grafany, currentuser dla Azure Monitor).
6. **Kolejność wdrożenia i zależności**: `terraform apply` → `k8s/deploy-k8s.sh`
   → `configure-grafana.sh`, oraz co się psuje przy złej kolejności.
7. **Scenariusze demonstracyjne** (S1.2b, S1.3, S1.6, S2.x) — co pokazują.
8. **Pułapki / decyzje projektowe** wychwycone z komentarzy w kodzie (np. nadmiarowe
   nadanie roli obu tożsamościom AKS, SKU Standard wymagane dla MPE, `kind` pusty w DCR).

### Wymagane produkty (pliki .md w katalogu docs)

Utwórz następujące pliki (odsyłające do siebie linkami względnymi):

- `README.md` — indeks + streszczenie architektury (1 akapit) + spis pozostałych dokumentów
- `01-architecture.md` — przegląd + diagram architektury całości
- `02-metrics-flow.md` — przepływy metryk (osobne diagramy dla AMW-A i AMW-B)
- `03-networking-dns.md` — sieci, PE, PLS, Private DNS + diagram + tabela NXDOMAIN
- `04-rbac-identity.md` — macierz RBAC + diagram tożsamości/auth
- `05-deployment-runbook.md` — kolejność kroków + diagram sekwencji + komendy
- `06-scenarios.md` — scenariusze S1/S2 z oczekiwanym wynikiem
- `07-design-decisions.md` — decyzje i pułapki (z odniesieniami do plików:linii)

### Wymagania jakościowe dla diagramów (ESTETYKA obowiązkowa)

- Używaj **diagramów Mermaid** w blokach `mermaid` (renderują się w GitHub/IDE).
- Stosuj różne typy trafnie: `flowchart` (architektura/przepływ), `sequenceDiagram`
  (runbook), `graph`/`subgraph` do grupowania (Resource Group, VNet, subnet, AKS).
- **Kolorystyka i czytelność**: definiuj `classDef` z sensowną, spójną i **dostępną**
  (kontrast w jasnym i ciemnym motywie) paletą; koloruj wg warstwy (compute / monitoring
  / grafana / network / identity). Grupuj zasoby w `subgraph` odwzorowujące granice
  Azure (RG → VNet → subnet). Dodawaj etykiety na krawędziach (protokół/port/auth).
  Odróżniaj wizualnie ścieżkę prywatną od publicznej (np. styl linii). Legenda mile widziana.
- Diagramy mają być **szczegółowe, ale czytelne** — nie jeden mega-graf; dziel na sekcje.
- Każdy zasób w diagramie nazywaj tak jak w kodzie (`amw-a`, `dcr-b`, `pe-amw-a`, `pls-prometheus`).

### Wymagania redakcyjne

- Język: **polski** (kod/nazwy zasobów po angielsku, jak w repo).
- Każde twierdzenie o infrastrukturze poprzyj odniesieniem `plik.tf:linia`.
- Tabele dla: RBAC, źródeł danych Grafany, workspace'ów/DCR/DCE, zmiennych.
- Nie wymyślaj — jeśli czegoś nie ma w kodzie, oznacz jako założenie/TODO.
- Na końcu `README.md` dodaj sekcję „Zweryfikuj po wdrożeniu” (checklista: metryka `up`
  w AMW-A/B, rozwiązanie DNS prywatnego rekordu, status połączenia MPE→PLS).

### Weryfikacja końcowa

Po zapisaniu plików sprawdź, że składnia Mermaid jest poprawna (brak niezbalansowanych
`subgraph`/`end`, poprawne `classDef`) i że wszystkie linki względne między dokumentami
działają. Podsumuj w odpowiedzi listę utworzonych plików.
