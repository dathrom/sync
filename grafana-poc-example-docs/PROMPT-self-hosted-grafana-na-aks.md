# PROMPT: Analiza wdrożenia self-hosted Grafany na AKS (dokładna kopia managed Grafany)

> Wklej poniższą treść jako zadanie dla agenta/inżyniera. Prompt jest samowystarczalny:
> najpierw każe przeczytać realny stan repo, dopiero potem analizować warianty.

---

## Rola i cel

Jesteś inżynierem platformy (Azure + Kubernetes + Terraform + Grafana). Twoim zadaniem
jest **przeanalizować i zarekomendować — zgodnie z dobrymi praktykami — jak dodać
self-hosted Grafanę na istniejący klaster AKS** w projekcie
`/Users/artur.prawdzik/repo/sync/grafana-poc-example/terraform`.

Ta self-hosted Grafana ma być **dokładną kopią istniejącej Azure Managed Grafany**:
- te same dashboardy,
- te same (odpowiedniki) źródła danych, w szczególności połączenie z **self-hosted
  Prometheusem** działającym już w tym klastrze,
- ten sam efekt wizualny/funkcjonalny dla użytkownika.

**Na tym etapie NIE implementujesz.** Produkujesz analizę wariantów + jednoznaczną
rekomendację + plan wdrożenia. Kod pokazujesz tylko jako szkice/fragmenty ilustrujące
rekomendację.

## Krok 0 — najpierw przeczytaj stan faktyczny (obowiązkowe, nie zgaduj)

Zanim cokolwiek zarekomendujesz, przeczytaj i streść realny stan tych plików:

- `terraform/grafana.tf` — obecna Azure Managed Grafana (SKU Standard, `grafana_major_version = 12`, tożsamość SystemAssigned, publiczna).
- `terraform/monitoring.tf` — dwa Azure Monitor Workspace: **AMW-A** (managed Prometheus add-on `ama-metrics` przez DCR-A) i **AMW-B** (self-hosted Prometheus `remote_write` przez DCR-B), wraz z parami DCE/DCR.
- `terraform/aks.tf` — klaster AKS (Azure CNI overlay, 1 węzeł, SKU Free), włączony `monitor_metrics {}` (add-on managed Prometheus), powiązania DCR-A.
- `terraform/rbac.tf` — nadania ról: Grafana MI → Monitoring Data Reader na AMW-A/AMW-B; kubelet MI → Monitoring Metrics Publisher na DCR-B; AKS MI → Network Contributor na vnet.
- `terraform/k8s/prometheus-values.yaml` — Helm values dla chartu `prometheus-community/prometheus`: `remoteWrite` z blokiem `azuread` (tożsamość kubeleta z IMDS), `service` typu wewnętrzny LoadBalancer z adnotacjami tworzącymi Private Link Service `pls-prometheus`, wyłączony alertmanager/pushgateway, włączony node-exporter i kube-state-metrics, `persistentVolume.enabled: false`.
- `terraform/k8s/deploy-k8s.sh` (i `.ps1`) — **imperatywny** post-apply: czyta `terraform output`, podmienia placeholdery `sed`-em, robi `helm upgrade --install prometheus ... -n monitoring`. To jest obecny wzorzec instalacji rzeczy na AKS.
- `terraform/configure-grafana.sh` (i `.ps1`) — **imperatywny** post-apply: przez `az grafana data-source create` tworzy 4 źródła danych (AMW-A, AMW-B jako Prometheus z auth `msi`; AzMon-CurrentUser; OSS-Prometheus-PLS przez MPE→PLS). Komentarz wprost mówi: Azure Managed Grafana wyłącza service accounts, więc provider Terraform Grafany się nie zaloguje — stąd `az grafana`.
- `terraform/outputs.tf` — outputy czytane przez skrypty (endpointy AMW, nazwy, client_id kubeleta itd.).
- `README.pl.md` — kolejność: `terraform apply` → `k8s/deploy-k8s.sh` → `configure-grafana.sh`.

**Ustal i zapisz fakty krytyczne dla analizy:**
1. Czy w repo istnieją JAKIEKOLWIEK definicje dashboardów? (Sprawdź — na dziś wygląda, że nie ma; dashboardy managed Grafany są konfigurowane poza kodem. To znaczy, że „dokładną kopię" trzeba najpierw **wyeksportować** z żywej managed Grafany.)
2. Jak dokładnie managed Grafana uwierzytelnia się do AMW-A/AMW-B (MSI) i co to oznacza dla self-hosted Grafany, która nie ma tożsamości Azure Managed Grafany.
3. Jaki dokładnie jest obecny wzorzec „wgrywania rzeczy na AKS" (imperatywny Helm w skrypcie post-apply, namespace `monitoring`).

## Krok 1 — przeanalizuj warianty METODY wdrożenia Grafany na AKS

Porównaj co najmniej poniższe podejścia. Dla każdego: jak wygląda, plusy, minusy,
zgodność z obecnym wzorcem (Prometheus przez Helm), koszt utrzymania, powtarzalność,
zarządzanie dashboardami-as-code i secretami.

- **A. Helm chart `grafana/grafana`** (społecznościowy oficjalny). Provisioning
  datasource'ów i dashboardów przez `values.yaml` (sekcje `datasources`,
  `dashboardProviders`, `dashboards`, sidecar `grafana.sidecar.dashboards`).
- **B. `kube-prometheus-stack`** (Prometheus + Grafana + operator w jednym).
  Rozważ, ale skonfrontuj z tym, że w repo jest świadomie `prometheus-community/prometheus`,
  a nie stack — czy migracja jest pożądana czy wręcz przeciwnie.
- **C. Kustomize** (bazowe manifesty + overlaye).
- **D. Grafana Operator** (CRDs: `Grafana`, `GrafanaDatasource`, `GrafanaDashboard`).
- **E. Terraform `helm_release`** (Helm sterowany z Terraforma zamiast ze skryptu).
- **F. GitOps (Argo CD / Flux)** — wspomnij jako kierunek docelowy, oceń czy nie jest
  przerostem formy dla tego PoC.

Użytkownik skłania się do **Helm deploymentu** — potraktuj to jako mocną preferencję,
ale uzasadnij rekomendację, nie przyjmuj bezkrytycznie.

## Krok 2 — przeanalizuj UWSPÓLNIENIE z obecnym wdrożeniem Prometheusa (kluczowe)

Wymaganie użytkownika: *„wszystkie rzeczy na tym AKS powinny być wgrywane tak samo,
więc trzeba to uwspólnić"*. Dziś Prometheus idzie imperatywnie (`deploy-k8s.sh` →
`helm upgrade --install`). Przeanalizuj i zarekomenduj **jeden spójny mechanizm** dla
obu (Prometheus + Grafana), rozważając m.in.:

- Pozostanie przy imperatywnym Helm w skryptach (dodać instalację Grafany do
  `deploy-k8s.sh`) — najmniejsza zmiana, spójne z „jak jest teraz", ale imperatywne.
- Migracja obu na **`helm_release` w Terraformie** — jeden `terraform apply` stawia
  wszystko, stan śledzony, ale trzeba rozwiązać zależność od outputów/kolejności
  (Grafana zależna od gotowego Prometheusa i endpointów AMW).
- **Helmfile** jako deklaratywna warstwa nad wieloma chartami.
- GitOps jako wariant docelowy.

Dla rekomendowanej opcji pokaż **docelowy układ katalogów** (np. `k8s/helm/prometheus`,
`k8s/helm/grafana`, wspólny values, wspólny skrypt/mechanizm) i jak wpasowuje się w
obecną kolejność `apply → deploy-k8s → configure-grafana`.

## Krok 3 — rozwiąż konkretne problemy techniczne (best practices)

Adresuj wprost każdy z punktów, z rekomendacją i uzasadnieniem:

1. **Źródła danych do parytetu z managed Grafaną.** Managed Grafana ma: AMW-A, AMW-B
   (auth MSI), AzMon-CurrentUser, OSS-Prometheus-PLS. Zdecyduj, do czego łączy się
   self-hosted Grafana:
   - Bezpośrednio do **in-cluster self-hosted Prometheusa** (`http://prometheus-server.monitoring.svc`)
     — najprościej, bez Azure, ale to inne dane niż AMW.
   - Do **AMW-A/AMW-B** przez plugin Azure Monitor / Prometheus z auth Azure — wtedy
     trzeba rozwiązać tożsamość (self-hosted Grafana nie ma MI Azure Managed Grafany).
     Rozważ **AKS Workload Identity / Managed Identity** (kubelet lub dedykowana UAMI +
     federacja), `azureCredentials` w datasource, oraz wymagane nadania ról (Monitoring
     Data Reader na AMW) — dołóż to do `rbac.tf`.
   - Wskaż, które źródła da się odtworzyć 1:1, a które (np. AzMon Current User) nie mają
     sensu w self-hosted i czym je zastąpić.
2. **Dashboardy „dokładnie takie same".** Ponieważ w repo ich nie ma:
   - Jak je **wyeksportować** z żywej managed Grafany (`az grafana dashboard list` /
     `az grafana dashboard show` / API `/api/search` + `/api/dashboards/uid/...`), zapisać
     jako JSON do repo (np. `k8s/grafana/dashboards/`).
   - Jak je **provisionować as-code** w self-hosted Grafanie (Helm `dashboardProviders` +
     `dashboardsConfigMap`/sidecar, albo Grafana Operator `GrafanaDashboard`).
   - Jak **przemapować UID/nazwy datasource'ów** w JSON-ach, żeby wskazywały na nowe
     źródła (`__inputs`/`datasource` templating), inaczej dashboardy będą puste.
3. **Sekrety i konto admina.** Hasło admina Grafany — nie hardcode; rekomenduj
   Kubernetes Secret / Azure Key Vault + CSI Secrets Store, lub `existingSecret` w charcie.
4. **Ekspozycja / dostęp.** Jak wystawić UI (ClusterIP + port-forward na PoC, Ingress,
   Service LoadBalancer wewnętrzny?). Odnieś się do tego, że managed Grafana jest
   publiczna, ale self-hosted na AKS nie musi być.
5. **Trwałość i HA.** PVC dla Grafany (dashboardy provisionowane są bezstanowe, ale
   users/prefs nie) vs bezstanowo. Dla PoC prawdopodobnie 1 replika + provisioning as-code.
6. **Uwierzytelnianie użytkowników.** Czy odwzorować logowanie (Azure AD / Entra ID OAuth)
   tak jak w managed, czy zostawić lokalny admin na PoC.
7. **Wersja i zgodność.** Managed Grafana to major **12** — dobierz wersję obrazu
   self-hosted Grafany tak, żeby dashboardy i schema były kompatybilne.
8. **Idempotencja i kolejność.** Zależności: AMW/endpointy i Prometheus muszą istnieć,
   zanim Grafana dostanie datasource'y. Pokaż jak to zachować w rekomendowanym mechanizmie.

## Ograniczenia i zasady

- Trzymaj się konwencji repo: komentarze po polsku (jak w istniejących `.tf`), dwa warianty
  skryptów (`.sh` + `.ps1`), namespace `monitoring`, czytanie danych z `terraform output`.
- Preferuj **konfigurację jako kod** i **idempotencję** nad krokami ręcznymi.
- Nie wprowadzaj sekretów do repo ani do stanu Terraform w plaintext.
- Minimalizuj rozjazd między dwiema Grafanami — celem jest wierna kopia, nie „lepsza wersja".
- Jeśli któryś element managed Grafany jest niemożliwy do odtworzenia 1:1 w self-hosted,
  powiedz to wprost i zaproponuj najbliższy odpowiednik.

## Wymagane produkty pracy (format wyjścia)

Zwróć dokument zawierający:

1. **Streszczenie stanu faktycznego** (z Kroku 0) — 5–10 zdań.
2. **Tabela porównawcza wariantów metody** (Krok 1) z kolumnami: podejście / dashboardy-as-code /
   secrety / spójność z obecnym Prometheusem / koszt utrzymania / werdykt.
3. **Rekomendacja metody wdrożenia** + jak uwspólnić z Prometheusem (Krok 2), z docelowym
   drzewem katalogów.
4. **Rozstrzygnięcia techniczne** dla każdego z punktów Kroku 3 (zwłaszcza: auth do AMW vs
   in-cluster Prometheus, oraz eksport i re-provisioning dashboardów z re-mapowaniem datasource).
5. **Plan wdrożenia krok-po-kroku** (co, w jakiej kolejności, jakie pliki dodać/zmienić —
   w tym zmiany w `rbac.tf`/outputach jeśli potrzebne), z zaznaczeniem punktów ryzyka.
6. **Otwarte pytania / decyzje do potwierdzenia** przez właściciela repo.

Szkice kodu (Helm values, fragment `helm_release`, provisioning datasource/dashboard,
komenda eksportu dashboardów) dołącz jako ilustrację rekomendacji — zwięźle, nie całe pliki.

**Zapisz wynik analizy do** `/Users/artur.prawdzik/repo/sync/grafana-poc-example-docs/`
(zgodnie z konwencją tego repo dla dokumentów).
