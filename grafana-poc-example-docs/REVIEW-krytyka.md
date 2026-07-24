# REVIEW — krytyka, weryfikacja krzyżowa i CHANGELOG dokumentacji `grafana-poc-example-docs`

> Recenzja techniczno-redakcyjna serii `01`–`16` + `README.md`, wraz z weryfikacją krzyżową
> (spójność logiczna → fakty → zgodność ze spotkaniem → porządki formalne), CHANGELOG-iem
> wprowadzonych zmian i listą „Do potwierdzenia przez człowieka".
>
> **Data odniesienia:** 2026-07-21. **Zakres recenzji i nadpisań:** wyłącznie `01`–`16` +
> `README.md`. Pliki źródłowe (Terraform, `transkrybcja`, `managed_grafana_internal`,
> `jak_loki_zmienilby_drzewo_RBAC.md`, `pytania_do_zespołu.md`) i artefakty `PROMPT-*.md` /
> `ANALYSIS_PROMPT.md` — **nie były zmieniane** (artefakty tylko ocenione pod kątem błędów
> wprowadzających w błąd). ArgoCD/GitOps — poza zakresem (świadomie usunięty), nie przywracany.
>
> **Metoda weryfikacji:** twierdzenia produktowe potwierdzone u źródła (docs Grafana/Loki/
> Mimir/Azure, oficjalne repo) z URL+datą (patrz sekcja „Źródła weryfikacji"); twierdzenia
> repo-specyficzne potwierdzone **czytaniem kodu** w `../grafana-poc-example/terraform`; cytaty
> ze spotkania sprawdzone wprost w `../transkrybcja` (numery linii).

---

## Ocena ogólna

Dokumentacja jest **merytorycznie mocna i wewnętrznie spójna** — zwłaszcza część analityczna
(`08`–`16`) trzyma jednolity łańcuch decyzyjny:

> „foldery/dashboardy = granularne w każdym OSS; **izolacja query datasource / logów / metryk
> per tenant = tylko Enterprise (datasource permissions / LBAC) albo multi-org (OSS)**; team
> sync i custom/fixed roles = Enterprise/Cloud; reconciler odtwarza team sync, ale **nie**
> izolację datasource".

Ten łańcuch jest stosowany **identycznie** w `04`/`09`/`11`/`12`/`13`/`15`/`16`, a kluczowe
zastrzeżenia (LBAC fail-open, izolacja sieci backendów, `X-Scope-OrgID` nie znika w Enterprise,
Loki bez row/label-level security, Mimir nie scrapuje) są konsekwentne. **Wszystkie** twierdzenia
repo-specyficzne (01–08) zweryfikowano w kodzie jako **prawdziwe**. Wykryte problemy to
w większości **fakty/liczby** (kilka) i **porządki formalne** (nawigacja); **nie** znaleziono
sprzeczności logicznej między wnioskami dokumentów.

---

## FAZA 1 — krytyka per plik

### `README.md`
- **Co zawiera:** indeks całej serii + jednoakapitowe streszczenie architektury + konwencja
  diagramów + checklista „zweryfikuj po wdrożeniu".
- **Co dobre:** indeks kompletny (01–16), opisy trafne, brak wpisów-sierot i brak wzmianki
  o usuniętym ArgoCD. Streszczenie architektury zgodne z kodem.
- **Błędy/ryzyka:** brak istotnych. Odniesienie „Prompt, z którego powstała ta dokumentacja:
  `ANALYSIS_PROMPT.md`" dotyczy realnie tylko `01`–`07` (część analityczna 08–16 powstała
  z `PROMPT-*.md`) — drobna nieprecyzyjność, nie mylące.
- **Braki:** brak. **Rekomendacja:** bez zmian treści (nawigacja serii doprowadzona osobno).

### `01-architecture.md`
- **Co zawiera:** przegląd całości, diagram architektury, inwentarz zasobów, providery/wersje.
- **Co dobre:** każdy zasób ma odniesienie `plik.tf:linia`; diagram zgodny z kodem; jasny
  podział AMW-A (prywatna) vs AMW-B (publiczna).
- **Weryfikacja (kod):** RG `rg-xyz-grafmon-lab`/`westeurope`, dwa AMW, SKU Standard, providery
  `azurerm ~>4.0` / `azuread ~>2.50` / TF `>=1.5` — **wszystko TRUE** (main.tf, monitoring.tf,
  grafana.tf, providers.tf). Brak błędów.
- **Rekomendacja:** bez zmian.

### `02-metrics-flow.md`
- **Co zawiera:** ingest+query dla obu ścieżek, budowa URL `remote_write`, 4 źródła danych.
- **Co dobre:** rozbicie na ścieżki A/B/B'; diagramy zgodne z opisem; poprawnie wskazana rola
  IMDS/kubelet i podwójne nadanie na DCR-A.
- **Weryfikacja (kod):** `monitor_metrics {}` (aks.tf:46), `remote_write` `azuread`+kubelet
  client_id (prometheus-values.yaml), 4 DS w `configure-grafana.sh` (msi/currentuser/brak) —
  **TRUE**. **Rekomendacja:** bez zmian.

### `03-networking-dns.md`
- **Co zawiera:** topologia VNet, PE+Private DNS do AMW-A, PLS do OSS Prometheusa, demo NXDOMAIN.
- **Weryfikacja (kod):** adresacja (vnet-lab 10.10/16, snet-aks .0/24, snet-pe .1/24; vnet-b
  10.20/16), `private_link_service_network_policies_enabled=false`, jawna strefa DNS
  `privatelink.westeurope.prometheus.monitor.azure.com` z `registration_enabled=false`, brak
  PE→AMW-B w TF — **TRUE**. **Rekomendacja:** bez zmian.

### `04-rbac-identity.md`
- **Co zawiera:** model tożsamości (MI), macierz RBAC, trzy niuanse (podwójne nadanie, pusty
  kubelet client_id, Owner ≠ dostęp do Grafany).
- **Weryfikacja (kod):** wszystkie nadania z rbac.tf (Data Reader×2, Monitoring Reader/RG,
  Metrics Publisher na DCR-A×2 i DCR-B, Network Contributor, Grafana Admin) na wskazanych
  liniach — **TRUE**. Usunięty SP opisany zgodnie z identity.tf. **Rekomendacja:** bez zmian.

### `05-deployment-runbook.md`
- **Co zawiera:** obowiązkowa kolejność `apply → deploy-k8s.sh → configure-grafana.sh`,
  sekwencja, komendy, sprzątanie.
- **Co dobre:** poprawnie wyłapana zależność (PLS powstaje w kroku 2, konsumowany w 3).
  **Weryfikacja:** zgodne z `configure-grafana.sh`/`teardown.sh`. **Rekomendacja:** bez zmian.

### `06-scenarios.md`
- **Co zawiera:** scenariusze S1.x/S2.x zrekonstruowane z kodu; uczciwie oznaczone ⚠️ te
  wymagające zewnętrznego planu testów.
- **Co dobre:** transparentność co do rekonstrukcji; S2.3 poprawnie oznaczony jako
  niedemonstrowalny (brak app-registration). **Rekomendacja:** bez zmian.

### `07-design-decisions.md`
- **Co zawiera:** świadome decyzje i pułapki z komentarzy w kodzie.
- **Weryfikacja (kod):** SKU Free, 1×B2ms, os_disk Managed, brak OMS, PV=false, alert/pushgw
  off, `grafana_major_version=12` — **TRUE**. Komentarz „v11 EOL 2026-06-15" mirrorem kodu
  (grafana.tf:14); trackery third-party podają 11.6 EOL ~2026-06-25 — różnica dni, nieistotna;
  **na datę 2026-07-21 Grafana 11 jest już EOL**, co tylko wzmacnia decyzję o „12".
- **Rekomendacja:** bez zmian treści (poprawiona tylko nawigacja → `08`).

### `08-self-hosted-grafana-analysis.md`
- **Co zawiera:** analiza metody dodania self-hosted Grafany (Helm `grafana/grafana`),
  uwspólnienie z Prometheusem, rozstrzygnięcia techniczne (WI, dashboardy/UID, sekrety, UI),
  plan krok-po-kroku, szkice kodu.
- **Co dobre:** solidne „Krok 0" oparte o realny kod; rekomendacja Helm uzasadniona spójnością
  z `07`; wariant `kube-prometheus-stack` odrzucony zgodnie z decyzją repo. Wzmianka „GitOps
  (Argo CD / Flux)" jako jeden wiersz tabeli metod — trafna, zostaje (bez rozwijania).
- **Weryfikacja (kod):** brak dashboardów `*.json` w repo — **TRUE**; `oidc_issuer_enabled`/
  `workload_identity_enabled` **nie są** dziś ustawione w aks.tf → doc słusznie mówi „trzeba je
  DODAĆ" (Krok A) — **TRUE**.
- **Braki/ryzyka:** krok D §9 odsyła do `README.pl.md` (README repo Terraform, nie docs) —
  drobna nieprecyzyjność, nie mylące. **Rekomendacja:** bez zmian treści (nawigacja → `09`).

### `09-selfhosted-rbac-entra-model.md`
- **Co zawiera:** przeniesienie modelu z `managed_grafana_internal` na self-hosted; dwa
  blokery (app registration; team sync = Enterprise); realia wielu źródeł danych.
- **Co dobre:** trafnie rozdziela „co przenosi się 1:1" (warstwa 2) od „co się zmienia"
  (warstwa 1 → grafana.ini). Group overage (>~200) opisany poprawnie.
- **Weryfikacja (źródła+repo):** dwuwarstwowy podział i intencja „tool-agnostic bo migracja do
  self-hosted" **potwierdzone** w `managed_grafana_internal/README.md`; team sync =
  Enterprise/Cloud **potwierdzone** w docs Grafany. **Rekomendacja:** bez zmian treści.

### `10-grafana-licencje-koszty-oss-reconciler.md`
- **Co zawiera:** dylemat licencyjny (Enterprise/Cloud vs OSS+reconciler), cenniki (fakty +
  „contact sales"), progi opłacalności, przegląd narzędzi, rekomendacja warunkowa.
- **Co dobre:** wzorowe rozdzielenie fakt/szacunek/„contact sales"; Enterprise self-managed =
  „contact sales" bez zmyślonej kwoty (widełki third-party jawnie oznaczone). Rozróżnienie
  `org_mapping` (OSS) vs team sync (Enterprise) poprawne i istotne. Matematyka kosztów spójna
  (0,043 USD/h ≈ 377 USD/rok; 6 USD/user ≈ 72 USD/rok; 20/100/500 userów liczą się).
- **Błędy (NAPRAWIONE):**
  1. *fakt:* „~15 grup Entra" — realny `rbac_input.csv` ma **17 unikalnych grup w 19 wierszach**
     (3 systemy: RA0395/OCMS_KLIENT, RA0766/OLIMPS, RA0341/DINGO). Poprawiono na 17.
  2. *fakt:* §5.4 „Język: Go lub Python (Python spójny z `grafana-oss-team-sync` i
     `resolve_object_ids`)" — **`grafana-oss-team-sync` jest napisany w Go** (92,8% Go, repo
     GitHub), a `resolve_object_ids.*` to Bash/PowerShell, nie Python. Poprawiono.
- **Weryfikacja:** team sync/RBAC/reporting/SLA = Enterprise; `org_mapping` OSS GA 11.2.0;
  Azure Managed Grafana na Enterprise; Essential — pełna deprecjacja 2027-03-31, brak nowych;
  `grafana-oss-team-sync` GPL-3.0, ≥11.1, Graph `GroupMember.Read.All`+`User.ReadBasic.All`,
  22★, v0.3.2 (2026-05) — **wszystko potwierdzone u źródła**.
- **Rekomendacja:** patrz „Do potwierdzenia" (aktualność stawek Grafana Cloud Pro, X1/X2 Azure).

### `11-granulacja-uprawnien-warianty.md`
- **Co zawiera:** granulacja folderów/dashboardów/datasource w wariantach A–D; dwa diagramy
  (quadrant + poziomy egzekwowania); oś kluczowa: izolacja datasource.
- **Co dobre:** quadrant zgodny z opisem (A prawy-górny „pełna kontrola", B lewy-górny „bez
  izolacji DS", C prawy-dolny „izolacja bez granulacji", D lewy-dolny). Macierz faktów spójna
  z `09`/`10`/`16`.
- **Weryfikacja:** subfoldery GA w OSS od Grafany 11, **do 4 poziomów, we wszystkich edycjach,
  kaskadowanie w dół** — potwierdzone; datasource permissions/custom roles = Enterprise —
  potwierdzone. **Rekomendacja:** bez zmian treści.

### `12-reconciler-architektura-mechanizmy.md`
- **Co zawiera:** jak działa reconciler (`grafana-oss-team-sync`): dwie powierzchnie (Graph
  ODCZYT, Grafana ZAPIS), pętla reconcile, mechanizmy, auth (SA token vs basic), obejście
  group overage, granice (bez izolacji DS/custom roles).
- **Co dobre:** poprawnie: bulk set-team-members wymaga Grafany ≥11.1; Admin API
  (`/api/admin/users`) wymaga basic auth; upstream używa `CLIENT_SECRET`, WI wymaga adaptacji.
  Diagram „Reconciler (CronJob, Go)" — zgodny z faktem (tool w Go).
- **Weryfikacja:** min. Grafana 11.1.0 (bulk endpoint), Graph perms, GPL-3.0 — potwierdzone.
  **Rekomendacja:** bez zmian treści.

### `13-loki-wplyw-na-self-hosted-i-izolacje.md`
- **Co zawiera:** jak Loki zmienia analizę OSS vs Enterprise; co Loki potrafi przyjąć/nie.
- **Co dobre:** trafny wniosek — izolacja logów ląduje na osi datasource, której OSS nie
  granuluje → Enterprise (LBAC/DS-permissions) lub multi-org; reconciler nie pomaga; przy
  Enterprise reconciler traci sens (spójny łańcuch warunkowy, brak sprzeczności z `10`–`12`).
  Loki = jeden typ (logi); LogQL metric queries ≠ metryki Prometheusa; derived fields = link
  do Tempo; nie full-text; tylko push.
- **Błąd (NAPRAWIONY, drobny):** LBAC opisany jako „GA dla logów" — LBAC jest GA także dla
  metryk (Mimir); dopisano „(i osobno dla metryk — Mimir)" dla zgodności z hotspotem.
- **Weryfikacja:** LBAC = Enterprise/Cloud, **fail-open** (brak reguły = pełny dostęp), limit
  ~500–600 reguł/DS; Promtail EOL 2026-03-02 (merge w Alloy, Loki 3.4); Grafana Agent EOL
  2025-11-01; OTLP natywnie w Loki 3.x — **wszystko potwierdzone**.
- **Rekomendacja:** OK (naprawione).

### `14-alternatywy-dla-grafany-rbac.md`
- **Co zawiera:** narzędzia z granularniejszym RBAC w OSS (Perses, OpenSearch Dashboards,
  Superset, Zabbix, SigNoz); teza „architektura bije zmianę narzędzia"; bilans migracji.
- **Co dobre:** uczciwy bilans (ekosystem, migracja dashboardów, kompetencje, dojrzałość);
  Perses (CNCF Sandbox od 2024-08, Apache 2.0) i OpenSearch fine-grained trafnie ujęte.
  Wzmianka „Mimir/Loki/Tempo mają natywne tenanty" spójna z `15`/`16`. **Rekomendacja:** bez zmian.

### `15-dyskusja-ze-mna-na-temat-wyboru-narzedzi.md`
- **Co zawiera:** uzasadnienie docelowego stacku (Prometheus→Mimir, Vector→Loki, OTel→Tempo,
  wspólny `X-Scope-OrgID`) + Q&A z cytatami ze spotkania.
- **Co dobre:** **wszystkie** cytowane numery linii transkrypcji (625, 879, 884-885, 901, 908,
  911, 918, 933, 948-950, 1281, 1302, 1370) **zweryfikowane jako zgodne** ze znaczeniem
  w `transkrybcja`. Mimir AGPLv3 vs Cortex/Thanos Apache 2.0, Mimir nie scrapuje, Tempo
  `X-Scope-OrgID` na zapisie i odczycie — poprawne.
- **Błąd (NAPRAWIONY):** Q10 twierdziło „Ślady: **nieomówione**". W transkrypcji Tempo/ślady
  **padają** (element stosu + korelacja log↔trace: linie 625, 699, 705). Doprecyzowano: luka
  dotyczy **modelu dostępu/izolacji śladów per tenant** (ten aspekt faktycznie nieomówiony),
  nie samego istnienia Tempo w stacku.
- **Rekomendacja:** OK (naprawione).

### `16-rbac-grafana-oss-vs-enterprise-organizacje.md`
- **Co zawiera:** graficzny model dostępu, gdy user ma wjazd tylko do Grafany; OSS (multi-org)
  vs Enterprise (jedna org + teamy); model ze spotkania (cross-tenant query license-free vs
  „DS per strumień + permissions per team" = Enterprise).
- **Co dobre:** **wzorcowe** ujęcie modelu zaufania (backend ufa nagłówkowi → izolacja sieci
  obowiązkowa); jasne „`X-Scope-OrgID` nie znika w Enterprise"; **pułapka LBAC fail-open**
  jawnie zaznaczona; cross-tenant query (`A|B`) poprawnie sklasyfikowane jako feature backendu
  (license-free). Cytaty ~879–950 zweryfikowane. **Rekomendacja:** bez zmian treści.

### Artefakty procesowe (poza nadpisaniem — tylko ocena)
- `ANALYSIS_PROMPT.md`, `PROMPT-self-hosted-grafana-na-aks.md`,
  `PROMPT-grafana-licencje-vs-oss-reconciler.md`, `PROMPT-krytyka-i-aktualizacja-docs.md`:
  to **prompty procesowe**, nie dokumentacja produktowa. Ocenione pod kątem błędów
  wprowadzających w błąd — **nie znaleziono** twierdzeń faktograficznych fałszywych; nie
  przepisywane, nie usuwane.

---

## FAZA 1b — weryfikacja KRZYŻOWA (spójność całości)

Kolejność ważności: **A. logika → B. fakty/liczby → C. spotkanie → D. formalne.**

### A. Spójność LOGICZNA i rekomendacji (najważniejsze) — **DOBRA**
- **Brak sprzeczności tez między plikami.** Ten sam łańcuch decyzyjny (izolacja datasource per
  tenant = Enterprise/LBAC lub multi-org; foldery/dashboardy = OSS; team sync/custom roles =
  Enterprise) prowadzi do **tych samych wniosków** w `04`/`09`/`11`/`12`/`13`/`15`/`16`.
- **Łańcuchy warunkowe identyczne.** „Jeśli logi/metryki wymagają izolacji → Enterprise (LBAC/
  DS-perms) lub multi-org; jeśli nie → OSS+reconciler wystarcza" — brzmi tak samo w `11 §5`,
  `13 §3`, `16 §5`. Definicja docelowego stacku (`[źródło]→[kolektor]→[backend]→Grafana`,
  wspólny `X-Scope-OrgID`) identyczna w `13`/`15`/`16`. Model zaufania (backend ufa nagłówkowi →
  izolacja sieci) spójny w `15 Q18` i `16 §0/§3.3`.
- **Zastrzeżenia stosowane konsekwentnie:** LBAC fail-open (`16 §2`), izolacja sieci backendów
  (`15`,`16`), Mimir nie scrapuje (`15 Q13/Q16`), Loki nie jest DS metryk/traces (`13 §4`,
  `15 Q8`), tenant vs organizacja Grafany (`15 Q16`, `16`), `X-Scope-OrgID` nie znika w
  Enterprise (`16 §"Czy X-Scope znika"`).
- **Warunkowość reconcilera bez sprzeczności:** `10`–`12` rekomendują OSS+reconciler *gdy nie
  trzeba izolacji DS*; `13` mówi, że *gdy logi wymagają izolacji* reconciler nie wystarcza i
  wręcz traci sens (bo wtedy Enterprise). To różne przesłanki, nie sprzeczne wnioski.
- **Diagramy zgodne z tekstem** (sprawdzone: quadrant `11`, drzewo decyzyjne `13`, diagramy
  OSS/Enterprise `16`, sekwencja `12`, architektura `01`).

### B. Spójność faktów/liczb/wersji — **DOBRA po poprawkach**
Ujednolicone/potwierdzone wartości w całej serii:
- `org_mapping` = **OSS, GA 11.2.0** (jedna wartość w `10`,`16`). ✅
- Subfoldery = **OSS od Grafany 11, do 4 poziomów, we wszystkich edycjach, kaskadowanie**
  (`11`). ✅
- **Team sync / datasource permissions / LBAC / fixed+custom roles = Enterprise/Cloud** (spójne
  w `09`–`13`,`16`). ✅
- LBAC: **fail-open**, limit **~500–600 reguł/DS**, dla logów **i metryk** (`13`,`16`). ✅
- Promtail **EOL 2026-03-02** (merge w Alloy, Loki 3.4); Grafana Agent **EOL 2025-11-01**;
  OTLP natywnie w **Loki 3.x** (`13`,`15`). ✅
- Mimir: multi-tenant `X-Scope-OrgID`, **AGPLv3**, fork **Cortex** (Apache 2.0), **nie scrapuje**
  (`15`). ✅
- Tempo: `multitenancy_enabled`, `X-Scope-OrgID` na zapisie i odczycie (`15 Q18`,`16`). ✅
- Progi kosztowe (~70–140 userów) jako **szacunek** — spójne w `10`/`11`. ✅
- **Liczba grup Entra ujednolicona: 17** (w 19 wierszach, 3 systemy) — poprawione w `10`. ✅
- Język reconcilera/gotowca: **Go** — poprawione w `10 §5.4`, zgodne z `12`. ✅

### C. Zgodność z ustaleniami spotkania — **DOBRA po poprawce**
- „RBAC to wzorzec multi-org całego stosu (nie funkcja Lokiego)" — **zgodne** (transkrybcja:625).
- Koncesja „metryki dla wszystkich" — **zgodne** (1281 + 1302).
- Loki bez row/label-level security — **zgodne** (jak_loki §3, potwierdzone w `13`/`15`).
- „DS per strumień + permissions per team = Enterprise" i „user nie nadpisze nagłówka przez
  Grafanę" — **zgodne** (884-885, 901, 911, 918, 933, 948-950).
- **Ślady/Tempo:** doprecyzowano (`15 Q10`) — Tempo *było* wzmiankowane (stack + korelacja),
  ale jego **izolacja/RBAC per tenant nie była omawiana**; luka realna, ale węższa niż
  „nieomówione". (Uwaga: `../pytania_do_zespołu.md` — plik read-only — nadal formułuje to jako
  „na spotkaniu nieomówione"; patrz „Do potwierdzenia".)

### D. Porządki formalne — **poprawione (nawigacja)**
- **Terminologia** jednolita (AMW, DCR/DCE, PE/PLS/MPE, `X-Scope-OrgID`, tenant vs organizacja,
  basic/fixed/custom roles, LBAC) — bez rozjazdów wymagających zmian.
- **Nawigacja 01→16:** wcześniej `08`–`16` linkowały „►" tylko do `README`, przez co ciągłe
  czytanie sekwencyjne urywało łańcuch. **Naprawiono** — `07`→`08`→…→`16`→`README`, z zachowaniem
  linku do `README` w każdym nagłówku (format `[◄ poprz.] · [README] · [nast. ►]`).
- **Linki/odnośniki `§`:** sprawdzone — działają; README kompletny (01–16), bez sierot,
  bez wpisów do usuniętego ArgoCD.

---

## CHANGELOG (per plik — co i dlaczego)

| Plik | Zmiana | Powód / źródło |
|---|---|---|
| `07-design-decisions.md` | Nagłówek nawigacji: „►" prowadzi teraz do `08` (przez `README`). | Domknięcie łańcucha 01→16 (Faza 1b/D). |
| `08` | Nawigacja „►" → `09`. | jw. |
| `09` | Nawigacja „►" → `10`. | jw. |
| `10-grafana-licencje-koszty-oss-reconciler.md` | (1) „~15 grup Entra" → **„17 grup"** (§1.5, §6, §7.5). (2) §5.4: usunięto błędne „Python spójny z `grafana-oss-team-sync`/`resolve_object_ids`"; **gotowiec jest w Go**, `resolve_object_ids.*` to Bash/PowerShell. (3) Nawigacja „►" → `11`. | (1) odczyt `managed_grafana_internal/02-grafana-config/rbac_input.csv` (19 wierszy, 17 unikalnych `entra_object_id`, 3 systemy). (2) repo GitHub `grafana-oss-team-sync` (92,8% Go). |
| `11` | Nawigacja „►" → `12`. | Faza 1b/D. |
| `12` | Nawigacja „►" → `13`. | jw. |
| `13-loki-wplyw-na-self-hosted-i-izolacje.md` | LBAC: „GA dla logów" → „GA dla logów (i osobno dla metryk — Mimir)". Nawigacja „►" → `14`. | Hotspot: LBAC obejmuje logi i metryki (docs Grafana, what's-new 2025-02-28). |
| `14` | Nawigacja „►" → `15`. | Faza 1b/D. |
| `15-dyskusja-ze-mna-na-temat-wyboru-narzedzi.md` | Q10: „Ślady: nieomówione" → doprecyzowanie (Tempo wzmiankowane w stacku/korelacji: transkrybcja 625/699/705; nieomówiona jest **izolacja/RBAC śladów per tenant**). Nawigacja „►" → `16`. | Weryfikacja `../transkrybcja` (linie 625, 699, 705). |
| `01`–`06`, `16`, `README.md` | **Bez zmian treści.** (`16` już kończy się linkiem do `README`.) | Zweryfikowane jako poprawne i spójne. |

> **Charakter zmian:** konserwatywny i atomowy — wyłącznie edycje punktowe (fakty + nawigacja).
> Żaden plik nie był przepisywany od zera. Żaden plik źródłowy (read-only) nie został zmieniony.

---

## Do potwierdzenia przez człowieka

Rzeczy, których **nie dało się** rozstrzygnąć autorytatywnie na datę 2026-07-21 — do weryfikacji,
zamiast zgadywania:

1. **Cennik Grafana Cloud Pro (per aktywny user, opłata platformowa).** `10 §3.3` podaje 19 USD/
   mies. platforma + 8 USD/user (3 gratis) z cytatem `grafana.com/pricing` (2026-07-20). Cennik
   Cloud bywa zmieniany — potwierdzić aktualne stawki i model zużycia przed użyciem w decyzji.
2. **Grafana Enterprise self-managed — realna cena.** Nadal **„contact sales"**; widełki
   third-party (~25–150k USD/rok, floor ~25k) są **szacunkiem**, nie ofertą. Potwierdzić z
   Grafana sales (minimum roczne, model per-user vs per-active-user, floor userów).
3. **Azure Managed Grafana — sizing Standard (X1/X2).** MS Learn (migrate-essential, 2026-06)
   wspomina dwa rozmiary instancji Standard (X1 domyślny, X2). `10 §3.4` operuje jednostkową
   ceną ~0,043 USD/h — potwierdzić, czy X2 nie zmienia stawki bazowej w kalkulacji.
4. **Grafana 11 EOL — dokładna data.** Kod (`grafana.tf:14`) i `07` podają 2026-06-15; trackery
   third-party ~2026-06-25 (11.6). Nieistotne dla wniosku (na datę odniesienia 11 jest już EOL),
   ale jeśli data ma trafić do decyzji formalnej — potwierdzić w oficjalnym harmonogramie Grafany.
5. **`../pytania_do_zespołu.md` (read-only)** formułuje ślady jako „na spotkaniu nieomówione".
   Zgodnie z weryfikacją transkrypcji Tempo *było* wzmiankowane (stack/korelacja), a nieomówiona
   jest jego izolacja per tenant. Jeśli ten plik ma być publikowany dalej — rozważyć analogiczne
   doprecyzowanie (poza zakresem tej recenzji — plik źródłowy).
6. **`../jak_loki_zmienilby_drzewo_RBAC.md` (read-only)** analizuje **starszą/większą** wersję
   `rbac_input.csv` (deklaruje „25 wierszy", ~23 teamy), podczas gdy plik na dysku ma dziś
   **19 wierszy / 17 grup**. Docs `08`–`16` nie propagują liczby „25", ale przy aktualizacji
   materiałów źródłowych warto ujednolicić. (Poza zakresem — plik read-only.)
7. **`grafana-oss-team-sync` — liczba commitów.** `10 §5.3` podaje „~580 commitów"; zweryfikowano
   licencję (GPL-3.0), wersję (v0.3.2, 2026-05), gwiazdki (~22), min. Grafanę (≥11.1) i uprawnienia
   Graph — ale dokładnej liczby commitów nie potwierdzano. Nieistotne merytorycznie.

---

## Źródła weryfikacji (URL + data dostępu 2026-07-21)

**Grafana / Loki / Mimir:**
- Team sync = Enterprise/Cloud: <https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-team-sync/>
- `org_mapping`/`org_attribute_path` OSS, GA v11.2: <https://grafana.com/docs/grafana/latest/whatsnew/whats-new-in-v11-2/>, <https://grafana.com/whats-new/map-org-specific-user-roles-from-your-oauth-provider/>
- LBAC (Enterprise/Cloud, fail-open, ~500–600 reguł, logi i metryki): <https://grafana.com/docs/grafana/latest/administration/data-source-management/teamlbac/>, <https://grafana.com/whats-new/2025-02-28-lbac-for-data-sources---logs/>, <https://grafana.com/whats-new/2025-02-28-lbac-for-data-sources---metrics/>
- Subfoldery (OSS v11, do 4 poziomów, wszystkie edycje, kaskadowanie): <https://grafana.com/whats-new/2024-02-27-subfolders/>, <https://grafana.com/blog/grafana-11-release-all-the-new-features/>
- Promtail EOL 2026-03-02 / merge w Alloy (Loki 3.4) / Grafana Agent EOL 2025-11-01: <https://grafana.com/blog/2025/02/13/grafana-loki-3.4-standardized-storage-config-sizing-guidance-and-promtail-merging-into-alloy/>, <https://grafana.com/docs/loki/latest/send-data/promtail/>
- OTLP natywnie w Loki 3.x: <https://grafana.com/docs/loki/latest/send-data/otel/>
- Mimir AGPLv3, fork Cortex (Apache 2.0): <https://grafana.com/oss/mimir/>, <https://thenewstack.io/the-great-grafana-mimir-and-cortex-split/>
- Grafana 11 EOL / harmonogram: <https://endoflife.date/grafana>
- `grafana-oss-team-sync` (GPL-3.0, Go, ≥11.1, Graph perms, v0.3.2): <https://github.com/skuethe/grafana-oss-team-sync>

**Azure:**
- Managed Grafana cennik (Standard, per aktywny user): <https://azure.microsoft.com/en-us/pricing/details/managed-grafana/>
- Managed Grafana na Grafana Enterprise / FAQ: <https://learn.microsoft.com/en-us/azure/managed-grafana/faq>
- Essential — pełna deprecjacja 2027-03-31, brak nowych, X1/X2 Standard: <https://learn.microsoft.com/en-us/azure/managed-grafana/how-to-migrate-essential-service-tier>

**Repo (potwierdzone czytaniem kodu):** `../grafana-poc-example/terraform` (grafana.tf, monitoring.tf,
rbac.tf, identity.tf, aks.tf, network.tf, dns.tf, providers.tf, outputs.tf, configure-grafana.sh,
k8s/prometheus-values.yaml, k8s/deploy-k8s.sh) oraz
`../../managed_grafana_internal/{README.md, 02-grafana-config/rbac_input.csv}`.

**Spotkanie (potwierdzone w `../transkrybcja`):** linie 625, 699, 705, 879, 884–885, 901, 908, 911,
918, 933, 948–950, 1281, 1302, 1370.
