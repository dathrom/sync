# PROMPT: kompletne diagramy schematu RBAC (LGTM + tenanci/organizacje) w D2 (Terrastruct) i Excalidraw

> Prompt do odpalenia na subagencie z dostępem do plików repo (i sieci, jeśli trzeba
> zweryfikować składnię formatów). Cel: **jeden kanoniczny model → dwa rendery (D2 i
> Excalidraw), TREŚCIOWO IDENTYCZNE**, żeby dało się porównać jakość obu. Plus opis w `.md`.

---

## Rola i cel

Jesteś architektem observability i rysownikiem diagramów. Masz stworzyć **KOMPLETNY, szczegółowy
schemat RBAC** dla self-hosted stosu **LGTM** (Loki/Grafana/Tempo/Mimir + Prometheus) na AKS,
pokazujący **jak tenanci (`X-Scope-OrgID`) i organizacje Grafany odwzorowują granularny RBAC**
dla **2–3 przykładowych systemów** i **teamów zmapowanych z grup Entra ID** — w modelu
**analogicznym do [`managed_grafana_internal`](../../managed_grafana_internal)**, ale
**rozszerzonym o organizacje/tenanty LGTM**.

Wyprodukuj **ten sam** diagram w **dwóch formatach**:
1. **D2 (Terrastruct)** — plik `.d2` (renderowalny `d2 CLI`).
2. **Excalidraw** — plik `.excalidraw` (poprawny JSON, importowalny na excalidraw.com).

Oraz **`.md`** z opisem modelu, legendą i drzewem obiektów/katalogów (jak model mapuje się na
Terraform/Helm/config). Zasada nadrzędna: **oba diagramy renderują TEN SAM model** (te same
węzły, krawędzie, etykiety, grupowanie, legenda) — różnić ma się tylko narzędzie.

## Materiały wejściowe — przeczytaj przed rysowaniem (nie zgaduj)

- **Model RBAC źródłowy:** [`managed_grafana_internal/02-grafana-config/rbac_input.csv`](../../managed_grafana_internal/02-grafana-config/rbac_input.csv)
  (kolumny `ra, system, environment, entra_group, entra_object_id, access_level, instance_role`),
  oraz `groups.tf`, `teams.tf`, `folders.tf`, `README.md` — to jest wzorzec: team = grupa Entra,
  folder = `(ra, system)`, podfolder = `(ra, system, environment)`, uprawnienia View/Edit/Admin.
- **Ustalenia zespołu:** [`../transkrybcja`](../transkrybcja) — **zacytuj numery linii** dla
  decyzji, które diagram odzwierciedla (patrz lista niżej).
- **Docelowy stack i model tenantów:** [15](15-dyskusja-ze-mna-na-temat-wyboru-narzedzi.md),
  [16](16-rbac-grafana-oss-vs-enterprise-organizacje.md), [13](13-loki-wplyw-na-self-hosted-i-izolacje.md),
  [11](11-granulacja-uprawnien-warianty.md), [`../jak_loki_zmienilby_drzewo_RBAC.md`](../jak_loki_zmienilby_drzewo_RBAC.md).
- **Poziom zabezpieczeń (referencja):** [`../grafana-poc-example/terraform`](../grafana-poc-example/terraform)
  — Private Endpoint + Private DNS, Private Link Service, Managed/Workload Identity, brak sekretów
  w kodzie, izolacja sieci. Odwzoruj analogiczny poziom dla self-hosted LGTM.

## Model do zilustrowania (kanoniczny — użyj DOKŁADNIE tego)

Zbuduj **jeden spójny model** i wyrenderuj go w obu formatach. Uprość dane z CSV do
**czytelnego, ale reprezentatywnego** zestawu (nie rysuj wszystkich 17 grup — wybierz poniższe).

### Warstwy (od dołu/źródeł do góry/użytkownika)

1. **Źródła danych — KILKA per sygnał:**
   - **Logi:** (a) logi zasobów Azure → **Diagnostic Settings → Azure Event Hub**; (b) logi
     podów/kontenerów z AKS; (c) logi on-prem. → wszystkie do **Vector**.
   - **Metryki:** (a) scrape workloadów AKS (**Prometheus**); (b) metryki zasobów Azure
     (**Azure Monitor exporter** → Prometheus); (c) exporter on-prem. → **remote_write** do Mimira.
   - **Ślady:** (a) aplikacja A (OTel SDK); (b) aplikacja B (OTel SDK). → **OTel Collector**
     (tail sampling) → Tempo.
2. **Kolektory (na AKS):** **Vector** (Event Hub → Loki), **Prometheus** (scrape + remote_write),
   **OTel Collector** (OTLP + tail sampling → Tempo). Każdy **ustawia `X-Scope-OrgID`** na zapisie.
3. **Backendy (na AKS, multi-tenant przez `X-Scope-OrgID`):** **Loki**, **Mimir**, **Tempo**.
   Pokaż **tenantów** (patrz niżej). Zaznacz: **osiągalne tylko wewnętrznie** (ClusterIP/internal
   LB) — nie z sieci użytkowników.
4. **Grafana (organizacje):** patrz „Organizacje i tenanci".
5. **Tożsamość / RBAC:** grupy **Entra ID** → (**org_mapping** OSS / **team sync** Enterprise) →
   organizacje/teamy/role Grafany; team = grupa Entra (jak w `managed_grafana_internal`).
6. **Sieć / bezpieczeństwo:** Private Endpoint do Event Hub, Private DNS, **Workload Identity**
   (UAMI + federated credential, brak sekretów), izolacja sieci backendów, Grafana UI za
   prywatnym ingressem. (Analogia do terraform PoC.)

### Systemy, tenanci, organizacje (użyj tych)

- **Systemy (z CSV):** `RA0395 / OCMS_KLIENT` (env: **DEV**, **UAT**), `RA0766 / OLIMPS`
  (env: **DEV**), opcjonalnie trzeci `RA0341 / DINGO` (env: **DEV**).
- **Tenanci LGTM (`X-Scope-OrgID`)** — jeden na `(ra, system, environment)`:
  `ra0395-ocms_klient-dev`, `ra0395-ocms_klient-uat`, `ra0766-olimps-dev`
  (+ `ra0341-dingo-dev` jeśli trzeci system) — **plus tenant `shared`** dla metryk „wspólnych"
  (koncesja ze spotkania: metryki widoczne dla wszystkich).
- **Organizacje Grafany:**
  - **Org „OCMS_KLIENT"** — data source'y przypięte do tenantów `ra0395-ocms_klient-*`;
  - **Org „OLIMPS"** — do `ra0766-olimps-dev`;
  - **Org „Platform/Shared"** — ma DS do **wielu** tenantów (cross-tenant) **oraz** tenant
    `shared` (metryki dla wszystkich); tu żyje **dashboard z DWÓCH tenantów** (patrz niżej).

### Data source'y (KILKA per sygnał, z przypiętym `X-Scope-OrgID`)

- W org OCMS_KLIENT: `Loki–OCMS-DEV` (`X-Scope-OrgID: ra0395-ocms_klient-dev`),
  `Mimir–OCMS-DEV`, `Tempo–OCMS-DEV`, oraz `Loki–OCMS-UAT` itd.
- W org OLIMPS: `Loki–OLIMPS-DEV`, `Mimir–OLIMPS-DEV`, `Tempo–OLIMPS-DEV`.
- W org Platform: `Mimir–shared` (`X-Scope-OrgID: shared`) **oraz** DS **cross-tenant**
  `Loki–OCMS|OLIMPS` z **`X-Scope-OrgID: ra0395-ocms_klient-dev|ra0766-olimps-dev`**
  (multi-tenant read przez `|`) — to obrazuje **dashboard łączący dwa tenanty**.

### Teamy z grup Entra (reprezentatywne, z CSV) i uprawnienia folderów

Dla każdego systemu pokaż 2–3 teamy = grupy Entra → uprawnienie do podfolderu:
- **OCMS_KLIENT-DEV:** `namespace_app-ocmsk-dev_..._reader` → **View**,
  `namespace_app-ocmsk-dev_..._writer` → **Edit**, `self_prod_ra0395-dev_admin` → **Admin**.
- **OLIMPS-DEV:** `nonprd_view_...ra0766...dev-1` → **View**,
  `nonprd_contrybutor_...ra0766...dev-1` → **Edit**.
- **Cross-tenant:** team **`platform_observability`** (grupa Entra) → **View** na dashboardzie
  łączącym OCMS+OLIMPS w org Platform (ilustruje dostęp „centralnego zespołu" do wielu systemów).
- Folder/podfolder: folder `RA0395 - OCMS_KLIENT` → podfolder `OCMS_KLIENT-DEV` (i `-UAT`),
  analogicznie OLIMPS — dokładnie jak w `managed_grafana_internal/folders.tf`.

### Ustalenia ze spotkania do ODZWIERCIEDLENIA (opisz na diagramie/legendzie, z nr linii)

- `X-Scope-OrgID` ustawiany i **nienadpisywalny**, per organizacja; backendy L/M/T czytają z
  niego tenant ([transkrybcja:625](../transkrybcja#L625)).
- **Org = system / data-stream**; ten sam DS dodawany do wielu org z uprawnieniami per team
  ([884](../transkrybcja#L884), [893](../transkrybcja#L893), [898](../transkrybcja#L898)).
- **Loki bez row/index-level security** → izolacja przez tenant/org + DS
  ([810–813](../transkrybcja#L810-L813)).
- **Metryki „shared" widoczne dla wszystkich** — koncesja ([808](../transkrybcja#L808),
  [1302](../transkrybcja#L1302)).
- Ścieżka logów **Event Hub → Vector → Loki** ([639](../transkrybcja#L639)); metryki przez
  exporter → Mimir; ślady z aplikacji → Tempo ([664](../transkrybcja#L664), [699](../transkrybcja#L699)).
- **Backendy ufają nagłówkowi → muszą być izolowane sieciowo** (spójnie z dok. 16 §0).

### Warstwa bezpieczeństwa (poziom jak w terraform PoC)

Zaznacz (jako adnotacje/strefy): **Private Endpoint** do Event Hub + **Private DNS**;
**Workload Identity** (UAMI + federated credential) dla dostępu do Azure — **brak sekretów**;
**backendy L/M/T tylko wewnętrznie** (ClusterIP/internal LB); **Grafana UI za prywatnym
ingressem**; granica zaufania `X-Scope-OrgID` = przypięcie w Grafanie **+** izolacja sieci.

## Wymagania wizualne (wspólne dla obu formatów)

- **Warstwy jako kontenery/strefy** (Źródła → Kolektory → Backendy(tenanci) → Grafana(organizacje/
  teamy/foldery) → Entra/RBAC → Sieć/Security).
- **Legenda**: kolory warstw; styl krawędzi **prywatna (przerywana)** vs **w klastrze/publiczna
  (ciągła)**; oznaczenie edycji **OSS (org_mapping, multi-org)** vs **Enterprise (team sync,
  datasource permissions/LBAC)** — pokaż model **OSS multi-org jako główny**, a Enterprise jako
  wariant-adnotację (mniejsza ramka „gdyby Enterprise: jedna org + LBAC").
- **Etykiety krawędzi** muszą nieść: protokół + auth + **`X-Scope-OrgID: <tenant>`** +
  prywatna/publiczna (np. „remote_write, WI, X-Scope-OrgID: ra0395-ocms_klient-dev").
- Kolorystyka spójna z serią docs (compute/monitoring/grafana/network/identity/external).
- Czytelność: jeśli jeden diagram jest przeładowany, **rozbij na 2–3** (np. (1) przepływ danych
  + tenanci, (2) mapowanie Entra→org/team/folder/uprawnienia, (3) dashboard cross-tenant) —
  **ale wtedy ten sam podział w OBU formatach**.

## Wymagania techniczne — D2

- Plik `.d2` renderowalny (`d2 fmt` bez błędów). Użyj **kontenerów zagnieżdżonych** (np.
  `aks: AKS { grafana; loki; mimir; tempo; vector; prometheus; otel }`), **klas** (`classes:`)
  do kolorów warstw, `direction`, oraz krawędzi z etykietami (`a -> b: "label"`).
- Organizacje/tenanty jako zagnieżdżone kontenery w `grafana`/backendach. Legenda jako kontener.
- Styl prywatnych krawędzi: `style.stroke-dash`. Zadbaj o spójne `class` per warstwa.

## Wymagania techniczne — Excalidraw

- Plik `.excalidraw` = poprawny JSON:
  `{"type":"excalidraw","version":2,"source":"https://excalidraw.com","elements":[...],`
  `"appState":{"viewBackgroundColor":"#ffffff","gridSize":null},"files":{}}`.
- Elementy: **prostokąty** (kontenery/węzły), **text** (etykiety; dla tekstu w prostokącie ustaw
  `containerId`), **arrow** (krawędzie z `startBinding`/`endBinding` do `elementId`, oraz wpis w
  `boundElements` po obu stronach). Każdy element: unikalne `id`, `x,y,width,height,angle:0`,
  `strokeColor,backgroundColor,fillStyle,strokeWidth,strokeStyle,roughness,opacity`,
  `groupIds:[]`, `frameId:null`, `roundness`, losowe `seed`/`versionNonce`, `version`,
  `isDeleted:false`, `boundElements`, `updated`, `link:null`, `locked:false`, oraz `index`
  (indeks frakcyjny, np. `a0`,`a1`,…).
- Prywatne krawędzie: `strokeStyle:"dashed"`. Kolory warstw jak w legendzie.
- **Rozplanuj współrzędne na siatce** (np. warstwy co ~200 px w pionie, węzły co ~220 px w
  poziomie), żeby nie było nachodzenia. Grupuj węzły warstwy wspólnym `groupIds`/`frameId`.
- Po wygenerowaniu **zweryfikuj**, że JSON się parsuje i struktura jest kompletna (bindings
  spójne). Jeśli używasz skryptu pomocniczego do generacji — dozwolone, ale **artefaktem jest
  gotowy `.excalidraw`**.

## Parytet treści (twarde)

Najpierw zapisz **kanoniczną specyfikację modelu** (lista węzłów z warstwą/kolorem + lista
krawędzi z etykietami + grupy) w pliku `.md`. **Oba** rendery (D2, Excalidraw) muszą 1:1
odpowiadać tej liście — te same węzły, krawędzie, etykiety, legenda, podział na diagramy.

## Plik `.md` (opis + drzewo)

- Kanoniczna specyfikacja modelu (jw.).
- Legenda i objaśnienie warstw.
- **Mapowanie na obiekty/konfigurację** — „drzewo" pokazujące, jak model przekłada się na:
  organizacje Grafany → teamy (=grupy Entra) → foldery/podfoldery → uprawnienia; data source'y z
  `X-Scope-OrgID`; tenanci L/M/T; konfiguracja kolektorów (który ustawia jaki tenant). Nawiąż do
  struktury `managed_grafana_internal` (co dochodzi w wariancie „rozszerzonym o organizacje").
- Krótko: co robi OSS multi-org, a co zmienia Enterprise (team sync + datasource permissions/LBAC).

## Zasady

- **Rzetelność:** model musi być zgodny z ustaleniami docs 11/13/15/16 i transkrypcji; nie
  wprowadzaj sprzeczności (izolacja datasource/logów = multi-org OSS lub Enterprise LBAC/DS-perms;
  metryki „shared" = koncesja; backendy izolowane sieciowo).
- **Po polsku**; nazwy techniczne (X-Scope-OrgID, org_mapping, LBAC) zostają.
- Nie zmyślaj grup/systemów — bierz z CSV (dozwolone uproszczenie liczby, nie treści).

## Gdzie zapisać

Utwórz katalog `grafana-poc-example-docs/diagrams/` i zapisz:
- `rbac-lgtm.d2`
- `rbac-lgtm.excalidraw`
- `rbac-lgtm.md` (opis + kanoniczna specyfikacja + drzewo).
Jeśli rozbijasz na 2–3 diagramy — nazwij konsekwentnie (`rbac-lgtm-1-dataflow.d2/.excalidraw`, itd.)
i utrzymaj parytet między formatami. Dopisz pozycję do `README.md` serii.

## Na koniec zwróć

Listę utworzonych plików, krótki opis co przedstawia każdy diagram, oraz — dla porównania —
**2–3 zdania: który format (D2 vs Excalidraw) lepiej oddał ten model i dlaczego**.
