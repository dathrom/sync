# RBAC dla self-hosted LGTM — tenanci (X-Scope-OrgID) i organizacje Grafany

> **Źródło prawdy dla obu renderów.** Ten plik zawiera **kanoniczną specyfikację modelu**
> (węzły z warstwą/kolorem, krawędzie z etykietami, podział na diagramy). Pliki `.d2` i
> `.excalidraw` są **generowane z tego samego modelu** (`rbac-lgtm.gen.py`) — muszą się
> zgadzać **1:1** (te same węzły, krawędzie, etykiety, legenda, podział).
>
> **Model:** rozszerzenie [`managed_grafana_internal`](../../../managed_grafana_internal)
> (team = grupa Entra, folder = `(ra, system)`, podfolder = `(ra, system, environment)`,
> uprawnienia View/Edit/Admin) o **organizacje Grafany + tenantów LGTM** — zgodnie z
> ustaleniami spotkania ([`../../transkrybcja`](../../transkrybcja)) i dokumentami
> [11](../11-granulacja-uprawnien-warianty.md) / [13](../13-loki-wplyw-na-self-hosted-i-izolacje.md) /
> [15](../15-dyskusja-ze-mna-na-temat-wyboru-narzedzi.md) /
> [16](../16-rbac-grafana-oss-vs-enterprise-organizacje.md) oraz
> [`../../jak_loki_zmienilby_drzewo_RBAC.md`](../../jak_loki_zmienilby_drzewo_RBAC.md).
> Poziom zabezpieczeń — analogicznie do Terraform PoC
> ([`../../grafana-poc-example/terraform`](../../grafana-poc-example/terraform)).

---

## 1. Pliki i podział na diagramy (parytet D2 ↔ Excalidraw)

Model jest **przeładowany na jeden obraz**, więc rozbity na **3 diagramy o identycznym
podziale w obu formatach**:

| Diagram | D2 | Excalidraw | SVG (dowód renderu D2) | Co przedstawia |
|---|---|---|---|---|
| **1 — Przepływ danych i tenanci** | `rbac-lgtm-1-dataflow.d2` | `rbac-lgtm-1-dataflow.excalidraw` | `rbac-lgtm-1-dataflow.svg` | Źródła → kolektory → backendy LGTM → tenanci → organizacje/DS Grafany. Zapis i odczyt z `X-Scope-OrgID`, ścieżki prywatne, izolacja sieci. |
| **2 — Mapowanie Entra → RBAC** | `rbac-lgtm-2-entra-rbac.d2` | `rbac-lgtm-2-entra-rbac.excalidraw` | `rbac-lgtm-2-entra-rbac.svg` | Grupy Entra → org_mapping/team sync → organizacje/teamy/foldery/podfoldery → View/Edit/Admin (+ DS permissions Enterprise). |
| **3 — Dashboard cross-tenant** | `rbac-lgtm-3-crosstenant.d2` | `rbac-lgtm-3-crosstenant.excalidraw` | `rbac-lgtm-3-crosstenant.svg` | Org Platform/Shared: dashboard z 2 tenantów (`A\|B`), `Mimir–shared`, team `platform_observability`, wariant Enterprise/LBAC. |

Wszystkie 3 D2 renderują się czysto (`d2 0.7.1`, `d2 fmt` bez błędów). Wszystkie 3
`.excalidraw` parsują się jako poprawny JSON sceny (`type: excalidraw`, `version: 2`);
bindingi (`startBinding`/`endBinding`/`containerId`/`boundElements`) i indeksy frakcyjne
zweryfikowane skryptem.

**Renderowanie:**

```bash
d2 rbac-lgtm-1-dataflow.d2 rbac-lgtm-1-dataflow.svg   # + analogicznie 2, 3
# Excalidraw: excalidraw.com → Open → plik (lub wtyczka VS Code pomdtr.excalidraw-editor)
```

---

## 2. Legenda (wspólna dla wszystkich diagramów)

| Kolor | Klasa | Warstwa |
|---|---|---|
| czerwony `#F8CECC` | `sources` | Źródła telemetrii |
| pomarańczowy `#FFE6CC` | `collector` | Kolektory na AKS (ustawiają `X-Scope-OrgID`) |
| niebieski `#DAE8FC` | `azure` | Azure — usługi zarządzane (Event Hub) |
| brzoskwiniowy `#FDEBD0` | `backend` | Backendy LGTM (ClusterIP, tylko wewnętrznie) |
| żółty `#FFF2CC` | `tenant` | Tenant — `X-Scope-OrgID` (partycja backendu) |
| lawendowy `#D9D2E9` | `org` | Organizacja Grafany |
| morski `#D0E0E3` | `datasource` | Data source (z przypiętym `X-Scope-OrgID`) |
| zielony `#D5E8D4` | `folder` | Folder / podfolder |
| jasnopomarańczowy `#FCE5CD` | `dashboard` | Dashboard |
| fioletowy `#E1D5E7` | `team` / `identity` | Team = grupa Entra ID / tożsamość |
| kremowy `#FFFBEA` | `note` | Adnotacja / ustalenie ze spotkania |
| biały + obrys przerywany | `optional` | Wariant Enterprise (team sync + DS perms / LBAC) |

**Styl krawędzi:**
- **linia CIĄGŁA** = łączność w klastrze / publiczna;
- **linia PRZERYWANA** = ścieżka **PRYWATNA** (Private Endpoint / priv. DNS lub odczyt
  po ClusterIP niedostępnym z sieci userów) **oraz** krawędzie **wariantu Enterprise**
  (obrys szary przerywany).

**Model główny = OSS multi-org** (`org_mapping`, jedna organizacja = jeden tenant/system).
**Enterprise = wariant-adnotacja** (jedna org + team sync + datasource permissions / LBAC).

---

## 3. Kanoniczna specyfikacja modelu

Legenda znaczników: `▸` = strefa/kontener, `•` = węzeł liściowy; `[klasa]` = kolor warstwy.
Krawędzie: `PRYW` = przerywana (prywatna), `pub` = ciągła, `ENT` = wariant Enterprise
(szara przerywana). Numery `[L…]` = linie [`../../transkrybcja`](../../transkrybcja).

### 3.1. Diagram 1 — Przepływ danych i tenanci (44 węzły, 26 krawędzi)

**Węzły (strefy → węzły):**

- ▸ `zrodla` **ŹRÓDŁA TELEMETRII**
  - • `src_azres` [sources] Logi zasobów Azure (Diagnostic Settings)
  - • `src_akslogs` [sources] Logi podów / kontenerów (AKS)
  - • `src_onpremlogs` [sources] Logi on-prem
  - • `src_aksmetrics` [sources] Metryki workloadów AKS (endpoint /metrics)
  - • `src_azmon` [sources] Metryki zasobów Azure (Azure Monitor)
  - • `src_onprommetrics` [sources] Exporter metryk on-prem
  - • `src_appA` [sources] Aplikacja A (OTel SDK — ślady)
  - • `src_appB` [sources] Aplikacja B (OTel SDK — ślady)
- ▸ `azure` **AZURE**
  - • `eventhub` [azure] Azure Event Hub (bufor logów)
- ▸ `kolektory` **KOLEKTORY (AKS) — USTAWIAJĄ X-Scope-OrgID**
  - • `vector` [collector] Vector (Event Hub → Loki)
  - • `azmon_exp` [collector] Azure Monitor exporter (→ Prometheus)
  - • `prometheus` [collector] Prometheus (scrape + remote_write)
  - • `otel` [collector] OTel Collector (OTLP + tail sampling)
- ▸ `backendy` **BACKENDY LGTM (AKS, ClusterIP — TYLKO WEWNĘTRZNIE)**
  - • `loki` [backend] · • `mimir` [backend] · • `tempo` [backend]
- ▸ `tenanci` **TENANCI — X-Scope-OrgID (partycje backendów)**
  - • `t_ocms_dev` [tenant] `ra0395-ocms_klient-dev`
  - • `t_ocms_uat` [tenant] `ra0395-ocms_klient-uat`
  - • `t_olimps_dev` [tenant] `ra0766-olimps-dev`
  - • `t_dingo_dev` [tenant, opcjonalny] `ra0341-dingo-dev` (3. system)
  - • `t_shared` [tenant] `shared` (metryki dla wszystkich)
- ▸ `grafana` **GRAFANA — ORGANIZACJE I DATA SOURCE'Y**
  - ▸ `org_ocms` [org] **Org OCMS_KLIENT**: `ds_loki_ocms_dev`, `ds_mimir_ocms_dev`,
    `ds_tempo_ocms_dev` (wszystkie `X-Scope-OrgID: ra0395-ocms_klient-dev`),
    `ds_loki_ocms_uat` (`…-uat`) [datasource]
  - ▸ `org_olimps` [org] **Org OLIMPS**: `ds_loki_olimps_dev`, `ds_mimir_olimps_dev`,
    `ds_tempo_olimps_dev` (`X-Scope-OrgID: ra0766-olimps-dev`) [datasource]
  - ▸ `org_platform` [org] **Org Platform / Shared**: `ds_mimir_shared`
    (`X-Scope-OrgID: shared`), `ds_loki_cross` (`X-Scope-OrgID:
    ra0395-ocms_klient-dev|ra0766-olimps-dev`) [datasource]
- ▸ `security` **ADNOTACJE BEZPIECZEŃSTWA**: `note_trust`, `note_wi`, `note_flow`,
  `note_hdr` [note]

**Krawędzie (protokół / auth / X-Scope-OrgID / prywatna?):**

| Od → Do | Etykieta | Styl |
|---|---|---|
| `src_azres → eventhub` | Diagnostic Settings → logi; Private Endpoint + priv. DNS | PRYW |
| `eventhub → vector` | odczyt AMQP, WI (brak sekretów); Private Endpoint [L639] | PRYW |
| `src_akslogs → vector` | logi podów (w klastrze) | pub |
| `src_onpremlogs → vector` | logi on-prem | pub |
| `src_aksmetrics → prometheus` | scrape /metrics (pull) | pub |
| `src_azmon → azmon_exp` | Azure Monitor API, WI; prywatna | PRYW |
| `azmon_exp → prometheus` | scrape exportera [L664] | pub |
| `src_onprommetrics → prometheus` | scrape / remote | pub |
| `src_appA → otel` | OTLP (gRPC) | pub |
| `src_appB → otel` | OTLP (gRPC) [L699] | pub |
| `vector → loki` | push HTTP, X-Scope-OrgID: `<ra-system-env>`, nienadpisywalny [L625], w klastrze | pub |
| `prometheus → mimir` | remote_write, WI, X-Scope-OrgID: `<tenant>` lub `shared`, w klastrze | pub |
| `otel → tempo` | OTLP, X-Scope-OrgID: `<tenant>`, w klastrze | pub |
| `loki → tenanci` | partycje per X-Scope-OrgID; brak row/index-level security [L810-813] | pub |
| `mimir → tenanci` | partycje per X-Scope-OrgID (+ shared) [L808] | pub |
| `tempo → tenanci` | partycje per X-Scope-OrgID | pub |
| `ds_loki_ocms_dev → t_ocms_dev` | LogQL, X-Scope-OrgID: ra0395-ocms_klient-dev; ClusterIP (prywatna) | PRYW |
| `ds_mimir_ocms_dev → t_ocms_dev` | PromQL; ClusterIP (prywatna) | PRYW |
| `ds_tempo_ocms_dev → t_ocms_dev` | TraceQL; ClusterIP (prywatna) | PRYW |
| `ds_loki_ocms_uat → t_ocms_uat` | LogQL, X-Scope-OrgID: ra0395-ocms_klient-uat; ClusterIP | PRYW |
| `ds_loki_olimps_dev → t_olimps_dev` | LogQL, X-Scope-OrgID: ra0766-olimps-dev; ClusterIP | PRYW |
| `ds_mimir_olimps_dev → t_olimps_dev` | PromQL; ClusterIP (prywatna) | PRYW |
| `ds_tempo_olimps_dev → t_olimps_dev` | TraceQL; ClusterIP (prywatna) | PRYW |
| `ds_mimir_shared → t_shared` | PromQL, X-Scope-OrgID: shared (metryki dla wszystkich) [L808,1302] | PRYW |
| `ds_loki_cross → t_ocms_dev` | LogQL, X-Scope-OrgID: …ocms-dev\|… (pipe); cross-tenant, ClusterIP | PRYW |
| `ds_loki_cross → t_olimps_dev` | LogQL, X-Scope-OrgID: …\|ra0766-olimps-dev; cross-tenant, ClusterIP | PRYW |

### 3.2. Diagram 2 — Mapowanie Entra → RBAC (28 węzłów, 22 krawędzie)

**Węzły:**

- ▸ `entra` **ENTRA ID — GRUPY (reprezentatywne z `rbac_input.csv`)**
  - • `g_ocms_reader` [identity] `namespace_app-ocmsk-dev_..._reader` (RA0395/OCMS DEV)
  - • `g_ocms_writer` [identity] `namespace_app-ocmsk-dev_..._writer`
  - • `g_ocms_admin` [identity] `self_prod_ra0395-dev_admin`
  - • `g_olimps_view` [identity] `nonprd_view_...ra0766...dev-1` (RA0766/OLIMPS DEV)
  - • `g_olimps_contrib` [identity] `nonprd_contrybutor_...ra0766...dev-1`
- ▸ `mapping` **MAPOWANIE TOŻSAMOŚCI**
  - • `oss_map` [collector] OSS: `org_mapping` `[auth.azuread]` grupa → ORG + rola
  - • `ent_sync` [optional] Enterprise: team sync — grupa → team (automat)
- ▸ `grafana` **GRAFANA — ORGANIZACJE / TEAMY / FOLDERY**
  - ▸ `org_ocms` [org] **Org OCMS_KLIENT**: `team_ocms_reader`, `team_ocms_writer`,
    `team_ocms_admin` [team]; ▸ `folder_ocms` (RA0395 - OCMS_KLIENT) → `subf_ocms_dev`,
    `subf_ocms_uat` [folder]; `ds_loki_ocms_dev` [datasource]
  - ▸ `org_olimps` [org] **Org OLIMPS**: `team_olimps_view`, `team_olimps_contrib` [team];
    ▸ `folder_olimps` (RA0766 - OLIMPS) → `subf_olimps_dev` [folder]; `ds_loki_olimps_dev`
    [datasource]
- ▸ `security` **ADNOTACJE — OSS vs ENTERPRISE**: `note_oss`, `note_ent`, `note_folders` [note]

**Krawędzie:**

| Od → Do | Etykieta | Styl |
|---|---|---|
| `g_ocms_reader → team_ocms_reader` | org_mapping → Org OCMS + rola (Enterprise: team sync) | pub |
| `g_ocms_writer → team_ocms_writer` | org_mapping / team sync | pub |
| `g_ocms_admin → team_ocms_admin` | org_mapping / team sync | pub |
| `g_olimps_view → team_olimps_view` | org_mapping → Org OLIMPS | pub |
| `g_olimps_contrib → team_olimps_contrib` | org_mapping / team sync | pub |
| `oss_map → org_ocms` | grupa → ORG + rola (Viewer/Editor/Admin) | pub |
| `ent_sync → org_ocms` | grupa → team (jedna org) | ENT |
| `team_ocms_reader → folder_ocms` | View (folder nadrzędny — cały system) | pub |
| `team_ocms_writer → folder_ocms` | View (nadrzędny) | pub |
| `team_ocms_admin → folder_ocms` | View (nadrzędny) | pub |
| `team_olimps_view → folder_olimps` | View (nadrzędny) | pub |
| `team_olimps_contrib → folder_olimps` | View (nadrzędny) | pub |
| `team_ocms_reader → subf_ocms_dev` | **View** | pub |
| `team_ocms_writer → subf_ocms_dev` | **Edit** | pub |
| `team_ocms_admin → subf_ocms_dev` | **Admin** | pub |
| `team_olimps_view → subf_olimps_dev` | **View** | pub |
| `team_olimps_contrib → subf_olimps_dev` | **Edit** | pub |
| `team_ocms_reader → ds_loki_ocms_dev` | Query (Enterprise: DS permission) | ENT |
| `team_ocms_writer → ds_loki_ocms_dev` | Edit (Enterprise) | ENT |
| `team_ocms_admin → ds_loki_ocms_dev` | Admin (Enterprise) | ENT |
| `team_olimps_view → ds_loki_olimps_dev` | Query (Enterprise) | ENT |
| `team_olimps_contrib → ds_loki_olimps_dev` | Edit (Enterprise) | ENT |

### 3.3. Diagram 3 — Dashboard cross-tenant + OSS vs Enterprise (22 węzły, 10 krawędzi)

**Węzły:**

- ▸ `entra` **ENTRA ID**: • `g_platform` [identity] `platform_observability` (centralny zespół)
- ▸ `grafana` **GRAFANA — Org Platform / Shared**
  - ▸ `org_platform` [org]: `team_platform` [team]; ▸ `folder_platform` (Platform /
    Cross-system) → `dash_cross` [dashboard] „Dashboard: OCMS + OLIMPS (logi z 2 tenantów
    + metryki shared)"; `ds_loki_cross`, `ds_mimir_shared` [datasource]
- ▸ `backendy` **BACKENDY LGTM (AKS, ClusterIP)**
  - ▸ `loki` [backend]: `t_ocms_dev`, `t_olimps_dev` [tenant]
  - ▸ `mimir` [backend]: `t_shared` [tenant]
- ▸ `enterprise` **WARIANT ENTERPRISE (adnotacja)**: `ent_box`, `ent_lbac` [optional]
- ▸ `security` **ADNOTACJE — CROSS-TENANT I KONCESJE**: `note_cross`, `note_shared`,
  `note_trust` [note]

**Krawędzie:**

| Od → Do | Etykieta | Styl |
|---|---|---|
| `g_platform → team_platform` | org_mapping / team sync → Org Platform | pub |
| `team_platform → folder_platform` | Admin / Edit (folder Platform) | pub |
| `team_platform → dash_cross` | **View** (dashboard cross-tenant) | pub |
| `team_platform → ds_loki_cross` | Query (Enterprise: DS permission) | ENT |
| `dash_cross → ds_loki_cross` | panel logów (2 tenanty) | pub |
| `dash_cross → ds_mimir_shared` | panel metryk shared | pub |
| `ds_loki_cross → t_ocms_dev` | LogQL, X-Scope-OrgID: …ocms-dev\|… (pipe); `multi_tenant_queries_enabled`, ClusterIP | PRYW |
| `ds_loki_cross → t_olimps_dev` | LogQL, X-Scope-OrgID: …\|ra0766-olimps-dev (pipe); ClusterIP | PRYW |
| `ds_mimir_shared → t_shared` | PromQL, X-Scope-OrgID: shared; metryki dla wszystkich [L808,1302] | PRYW |
| `ent_box → ent_lbac` | reguły LBAC | ENT |

---

## 4. Ustalenia ze spotkania odzwierciedlone na diagramach (z numerami linii)

| Ustalenie | Gdzie na diagramie | Transkrypcja |
|---|---|---|
| `X-Scope-OrgID` ustawiany i **nienadpisywalny**, per organizacja; backendy L/M/T czytają z niego tenanta | D1 `note_hdr`, etykieta `vector → loki`; D3 `note_trust` | [L625](../../transkrybcja#L625) |
| **Org = system / data-stream**; ten sam DS dodawany do wielu org z uprawnieniami per team | D2 (org_ocms/org_olimps + teamy), D3 (ds_loki_cross) | [L884](../../transkrybcja#L884), [L893](../../transkrybcja#L893), [L898](../../transkrybcja#L898) |
| **Loki bez row/index-level security** → izolacja przez tenant/org + DS | D1 `loki → tenanci`, `note_hdr`; D3 `note_shared` | [L810-L813](../../transkrybcja#L810-L813) |
| **Metryki „shared" dla wszystkich** (koncesja) | D1 `t_shared`, `ds_mimir_shared`; D3 `note_shared` | [L808](../../transkrybcja#L808), [L1302](../../transkrybcja#L1302) |
| Ścieżka logów **Event Hub → Vector → Loki** | D1 `src_azres → eventhub → vector → loki`, `note_flow` | [L639](../../transkrybcja#L639) |
| Metryki przez exporter → (Prometheus) → Mimir | D1 `src_azmon → azmon_exp → prometheus → mimir` | [L664](../../transkrybcja#L664) |
| Ślady z aplikacji → OTel → Tempo | D1 `src_appA/B → otel → tempo` | [L699](../../transkrybcja#L699) |
| Cross-tenant query `A\|B` (license-free feature backendu) | D3 `ds_loki_cross`, `note_cross` | [L884-L950](../../transkrybcja#L884), [dok. 16 §3.1](../16-rbac-grafana-oss-vs-enterprise-organizacje.md) |
| Backendy **ufają nagłówkowi → izolacja sieciowa** | D1 `note_trust`; D3 `note_trust`; wszystkie backendy = ClusterIP | [dok. 16 §0](../16-rbac-grafana-oss-vs-enterprise-organizacje.md) |

---

## 5. Poziom zabezpieczeń (analogia do Terraform PoC)

Odwzorowane z [`../../grafana-poc-example/terraform`](../../grafana-poc-example/terraform):

- **Private Endpoint + prywatna strefa DNS** do Event Hub / Azure Monitor
  (`dns.tf`: `azurerm_private_dns_zone` + `azurerm_private_endpoint`) — na D1 krawędzie
  `src_azres → eventhub`, `eventhub → vector`, `src_azmon → azmon_exp` są **przerywane**.
- **Workload Identity** (UAMI + federated credential, **brak sekretów w kodzie**) —
  `identity.tf` (app-registration świadomie **usunięty**), auth przez tożsamość, nie sekret;
  na D1 adnotacja `note_wi` i etykiety `WI` przy krawędziach do Azure.
- **Least-privilege role** (`rbac.tf`: Monitoring Data Reader / Metrics Publisher /
  Network Contributor) — analogicznie kolektory dostają tylko rolę zapisu, Grafana tylko odczytu.
- **Backendy L/M/T tylko wewnętrznie** (ClusterIP / internal LB) — strefa `backendy` na
  D1/D3 opisana „TYLKO WEWNĘTRZNIE", odczyt DS → tenant zawsze **przerywany** (ClusterIP).
- **Grafana UI za prywatnym ingressem** (analogia do internal LB / PLS z PoC
  `k8s/prometheus-values.yaml`, `network.tf`).
- **Granica zaufania `X-Scope-OrgID`** = **przypięcie nagłówka w Grafanie** (DS) **+**
  **izolacja sieci** backendów — obie warstwy razem (`note_trust`).

---

## 6. Drzewo mapowania modelu na obiekty / konfigurację

Jak model przekłada się na obiekty Grafany / Terraform / konfigurację kolektorów.
Bazuje na [`managed_grafana_internal/02-grafana-config`](../../../managed_grafana_internal/02-grafana-config)
(`groups.tf`, `teams.tf`, `folders.tf`, `rbac_input.csv`) — **rozszerzonym** o organizacje
i tenantów (por. [`../../jak_loki_zmienilby_drzewo_RBAC.md`](../../jak_loki_zmienilby_drzewo_RBAC.md)).

```
Entra ID (grupy z rbac_input.csv)
│   kolumny: ra, system, environment, entra_group, entra_object_id, access_level
│
├─ org_mapping (OSS) / team sync (Enterprise)      →  Organizacja + rola / Team
│
GRAFANA (OSS multi-org — model główny)
│
├─ Org OCMS_KLIENT                                  (org = system RA0395/OCMS_KLIENT)
│   ├─ TEAMY (= grupy Entra; grafana_team, teams.tf:2-6)
│   │   ├─ team ..._reader   → View  (podfolder DEV)
│   │   ├─ team ..._writer   → Edit  (podfolder DEV)
│   │   └─ team self_prod_ra0395-dev_admin → Admin (podfolder DEV)
│   ├─ FOLDERY (grafana_folder, folders.tf)
│   │   └─ 📁 RA0395 - OCMS_KLIENT        (folder = (ra,system); View dla WSZYSTKICH teamów systemu)
│   │       ├─ 📂 OCMS_KLIENT-DEV         (podfolder = (ra,system,env); perms wg CSV: View/Edit/Admin)
│   │       └─ 📂 OCMS_KLIENT-UAT
│   └─ DATA SOURCE'Y (grafana_data_source, przypięty X-Scope-OrgID)
│       ├─ Loki–OCMS-DEV    X-Scope-OrgID: ra0395-ocms_klient-dev   → tenant Loki
│       ├─ Mimir–OCMS-DEV   X-Scope-OrgID: ra0395-ocms_klient-dev   → tenant Mimir
│       ├─ Tempo–OCMS-DEV   X-Scope-OrgID: ra0395-ocms_klient-dev   → tenant Tempo
│       └─ Loki–OCMS-UAT    X-Scope-OrgID: ra0395-ocms_klient-uat
│       (Enterprise: grafana_data_source_permission per team — Query/Edit/Admin)
│
├─ Org OLIMPS                                       (org = system RA0766/OLIMPS)
│   ├─ team nonprd_view_...dev-1 → View, team nonprd_contrybutor_...dev-1 → Edit
│   ├─ 📁 RA0766 - OLIMPS → 📂 OLIMPS-DEV
│   └─ Loki/Mimir/Tempo–OLIMPS-DEV   X-Scope-OrgID: ra0766-olimps-dev
│
└─ Org Platform / Shared                            (org cross-system — centralny zespół)
    ├─ team platform_observability → Admin/Edit (folder Platform), View (dashboard)
    ├─ 📁 Platform / Cross-system → 📈 Dashboard „OCMS + OLIMPS"
    └─ DATA SOURCE'Y
        ├─ Mimir–shared              X-Scope-OrgID: shared                      → tenant shared
        └─ Loki–OCMS|OLIMPS          X-Scope-OrgID: ra0395-ocms_klient-dev|ra0766-olimps-dev
                                     (cross-tenant read, multi_tenant_queries_enabled)

TENANCI LGTM (X-Scope-OrgID = klucz (ra,system,environment), małe litery)
│   ustawiane przez kolektory na ZAPISIE, przypięte w DS na ODCZYCIE
├─ ra0395-ocms_klient-dev   (Vector→Loki, Prometheus→Mimir, OTel→Tempo)
├─ ra0395-ocms_klient-uat
├─ ra0766-olimps-dev
├─ ra0341-dingo-dev         (opcjonalny 3. system)
└─ shared                   (metryki dla wszystkich — koncesja)

KOLEKTORY (AKS) — który ustawia jaki tenant
├─ Vector           X-Scope-OrgID = <ra-system-env>  (Event Hub → Loki)
├─ Prometheus       X-Scope-OrgID = <tenant> lub shared (remote_write → Mimir)
└─ OTel Collector   X-Scope-OrgID = <tenant>  (OTLP + tail sampling → Tempo)
```

### Co dochodzi względem `managed_grafana_internal` (wariant „rozszerzony o organizacje")

| Warstwa | `managed_grafana_internal` (dziś, Managed Grafana) | Model rozszerzony (self-hosted LGTM) |
|---|---|---|
| Organizacje | **brak** (Azure Managed Grafana nie ma organizacji) | **N organizacji** = N systemów + „Platform/Shared" |
| Team | `grafana_team` = grupa Entra (`teams.tf`) | bez zmian (team = grupa Entra) |
| Folder / podfolder | `(ra,system)` / `(ra,system,env)` (`folders.tf`) | bez zmian |
| Data source | 1 globalny (TestData) + Prometheus read-only | **N data source'ów per tenant** z przypiętym `X-Scope-OrgID` (Loki/Mimir/Tempo) |
| Izolacja | tylko poziom folderów | **brzeg organizacji** (OSS) lub **DS permissions/LBAC** (Enterprise) + tenant backendu |
| Mapowanie z Entra | team sync (Managed=Enterprise) | **`org_mapping`** (OSS) lub team sync (Enterprise) |

### OSS multi-org vs Enterprise (skrót)

- **OSS (model główny):** izolacja **brzegiem organizacji** (`org_mapping` → org + rola
  Viewer/Editor/Admin). Data source'y i dashboardy **powielane w każdej org**; rola w org
  zgrubna; brak uprawnień do DS per team; brak widoku cross-org (poza cross-tenant query).
  Darmowe. Dobre przy niewielu tenantach. (dok. 16 §1)
- **Enterprise (wariant-adnotacja):** **jedna organizacja** + **team sync** (grupa → team
  automatycznie) + **datasource permissions / LBAC** (filtr etykiet per team) + **foldery
  per team** + **custom roles**. Granulacja bez mnożenia organizacji; wspólne dashboardy.
  Płatne. Opłaca się przy wielu tenantach/systemach. (dok. 16 §2)
- **Wspólny warunek:** backendy **ufają nagłówkowi `X-Scope-OrgID`** → muszą być
  **nieosiągalne sieciowo** dla użytkowników (ClusterIP + izolacja sieci). (dok. 16 §0)

---

## 7. Nota porównawcza — D2 vs Excalidraw (dla tego modelu)

**D2** wygrywa na **utrzymywalności i parytecie**: auto-layout ogarnia zagnieżdżone
kontenery (org → folder → podfolder, backend → tenant) i gęstą sieć krawędzi z długimi
etykietami (`X-Scope-OrgID`, protokół, auth) bez ręcznego pozycjonowania; `classes`
= paleta raz zdefiniowana; `style.stroke-dash` czytelnie koduje ścieżki prywatne;
render CLI → SVG działa w CI („docs as code"). Diff w gicie jest czytelny.

**Excalidraw** wygrywa na **prezentacji i ręcznej korekcie** (styl whiteboard, wspólna
edycja), ale przy tej skali (do 172 elementów) **nie ma auto-layoutu** — współrzędne
trzeba wyliczać skryptem, etykiety wieloliniowe łatwo nachodzą, a duży JSON słabo się
diffuje.

**Werdykt:** dla tego modelu — silnie zagnieżdżonego (organizacje/foldery/tenanci) i
bogatego w etykiety krawędzi — **D2 oddaje go lepiej**: auto-layout + klasy + docs-as-code
utrzymują parytet i czytelność minimalnym nakładem; Excalidraw ma sens dopiero jako
**ręcznie dopieszczona wersja pod prezentację**.
