# Zadanie: Jak wdrożenie Loki zmieniłoby POC grafana-poc-example

Jesteś analitykiem observability/Azure. Masz trzy źródła prawdy — przeanalizuj je
w tej kolejności ważności:

1. **Podsumowanie spotkania** (główne źródło potrzeb):
   `/Users/artur.prawdzik/repo/sync/podsumowanie_spotkania.md`
2. **Surowa transkrybcja** (posiłkowo, gdy podsumowanie jest zbyt skrótowe lub
   trzeba potwierdzić intencję): `/Users/artur.prawdzik/repo/sync/transkrybcja`
   — UWAGA: to automatyczne ASR, mocno zniekształcone fonetycznie. Korzystaj ze
   „Słowniczka zniekształceń transkrypcji" na końcu podsumowania (np. „lok fary"→Log4j,
   „mecz"→message, „riler/rooler"→ruler, „i went hub"→Event Hub, „wektor"→Vector).
3. **Aktualny stan POC** (to, co dziś istnieje):
   `/Users/artur.prawdzik/repo/sync/grafana-poc-example/` — przeczytaj README.pl.md
   oraz WSZYSTKIE pliki w `terraform/` (providers, network, dns, aks, monitoring,
   grafana, identity, rbac, outputs, locals, main) i skrypty
   (configure-grafana.sh, k8s/deploy-k8s.sh, k8s/prometheus-values.yaml, teardown.sh).

## Co masz ustalić

### Krok 1 — Potrzeby wokół Loki (z podsumowania + transkrybcji)
Wypisz KONKRETNE, wyartykułowane na spotkaniu wymagania dotyczące logów/Loki, m.in.:
- ścieżka zbierania logów z PaaS: `Diagnostic settings → Event Hub → Vector → Loki`
  i motywacja kosztowa (taniej niż Log Analytics przy długiej retencji),
- multi-tenancy Loki przez nagłówek `X-Scope-OrgID`, model „organizacja = system /
  data stream", ten sam data source dodawany wielokrotnie z uprawnieniami per team,
- brak row/index-level security w Loki (jest w Elasticsearch) — świadomy kompromis,
- brak full-text search — trzeba wskazywać pole, `message` domyślnie nieindeksowane
  → wymóg strukturyzowania logów (JSON) po stronie aplikacji,
- alerty na logach: data-source-managed **Loki ruler** (ingestion time), nie
  Grafana-managed cron — dla dużej skali reguł,
- Vector vs Alloy vs OpenTelemetry Collector (rekomendacja: Vector, wada: brak
  inputu Windows Event Log),
- kwestie towarzyszące: Event Hub throughput units (auto-inflate w górę, nie w dół),
  centralne Event Huby, PostgreSQL zamiast SQLite pod Grafaną.
Przy każdym punkcie zaznacz, czy to **twarde wymaganie**, **rekomendacja**, czy
**Twoja inferencja**. Cytuj źródło jako `plik:linia`.

### Krok 2 — Czego POC dziś NIE ma
Potwierdź (czytając kod), że obecny POC jest wyłącznie metrykowy: Grafana + 2×
Azure Monitor Workspace (AMW-A prywatna, AMW-B publiczna) + Prometheus przez DCE/DCR,
brak jakiegokolwiek komponentu logowego (Loki, Event Hub, Vector, diagnostic settings).

### Krok 3 — Zmiany wprowadzone przez Loki
Opisz, co dołożenie Loki „zgodnie z potrzebami" faktycznie zmienia w tym POC:
nowe zasoby Terraform (Event Hub namespace + hub, diagnostic settings na źródłach
PaaS, deployment Vector, deployment Loki na AKS + storage, ewentualnie Mimir dla
metryk long-term), nowe data source'y w `configure-grafana.sh`, zmiany w RBAC/tożsamościach,
zmiany sieciowe (private link / DNS), zmiany w modelu multi-tenancy i alertowania.
Wyraźnie oddziel „to wynika wprost z ustaleń" od „to konieczna konsekwencja techniczna".

## Format wyjścia (po polsku)

Narysuj wynik **dokładnie w konwencji drzewa jak w analizie managed_grafana_internal**:
drzewo ASCII pokazujące architekturę PO wdrożeniu Loki, z zaznaczeniem, które węzły
są NOWE (dodane przez Loki), a które ISTNIEJĄ dziś. Np.:

```
Azure (POC po dodaniu Loki)
├─ ISTNIEJE  Azure Managed Grafana
│   ├─ ISTNIEJE  data source: AMW-A (Prometheus, prywatny)
│   ├─ ISTNIEJE  data source: AMW-B (Prometheus, publiczny)
│   └─ NOWE      data source: Loki  (X-Scope-OrgID per organizacja/system)
├─ ISTNIEJE  AKS
│   ├─ ISTNIEJE  managed-Prometheus (ama-metrics → AMW-A)
│   ├─ NOWE      Loki (deployment + storage)
│   └─ NOWE      Vector (Event Hub → Loki)
└─ NOWE      Ścieżka logów PaaS: Diagnostic settings → Event Hub → Vector → Loki
```
(To tylko szkielet — uzupełnij realnymi zasobami i zależnościami, które ustalisz z kodu.)

Po drzewie dodaj:
1. **Tabelę zmian**: Zasób/Plik | Akcja (NOWY / MODYFIKACJA / bez zmian) | Powód (z `plik:linia`).
2. **Listę nowych/zmienianych plików Terraform** (np. proponowany `loki.tf`,
   `logging.tf`/`eventhub.tf`, zmiany w `configure-grafana.sh`, `rbac.tf`, `dns.tf`).
3. **Sekcję „Kompromisy i ryzyka"** wprost z wniosków spotkania (tanio vs
   granularnie vs alerty; brak row-level security; jakość logów po stronie aplikacji).
4. **Otwarte pytania** (np. Loki single- vs multi-tenant, gdzie storage: Blob/S3-compat,
   czy Mimir wchodzi w zakres tego POC).

Zasady: wszystko osadzaj w realnych plikach i cytuj `plik:linia`. Nie wymyślaj
zasobów, których nie da się uzasadnić potrzebą lub konsekwencją techniczną.
Nie modyfikuj żadnych plików — to analiza. Jeśli podsumowanie i transkrybcja są
sprzeczne, zaufaj podsumowaniu i odnotuj rozbieżność.
