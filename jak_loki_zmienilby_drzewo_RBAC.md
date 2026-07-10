# Jak wprowadzenie Loki zmieniłoby drzewo RBAC (managed_grafana_internal)

> **Zakres:** wpływ dołożenia **Grafana Loki** (logi) na drzewo **folderów /
> uprawnień / data source'ów / dashboardów** generowane przez to repo z
> [`rbac_input.csv`](rbac_input.csv).
> **Wsad analizy:** obecny [`rbac_input.csv`](rbac_input.csv) (25 wierszy przypisań).
> **Źródło potrzeb Loki:** [`../sync/podsumowanie_spotkania.md`](../sync/podsumowanie_spotkania.md)
> (posiłkowo surowa [`../sync/transkrybcja`](../sync/transkrybcja)).
> **Ważne:** to repo zarządza **wyłącznie obiektami wewnątrz Grafany** (+ role Azure na
> instancji). Infrastruktura Loki (deployment, storage, Event Hub, Vector, ruler) leży
> **poza** tym repo — patrz „Granica własności" w [`README.md`](README.md#L26).

---

## 1. Skąd się bierze drzewo — dane i konwencje

Jedynym źródłem prawdy jest [`rbac_input.csv`](rbac_input.csv) (`csvdecode`,
[groups.tf:7](groups.tf#L7)). Kolumny: `ra, system, environment, entra_group,
entra_object_id, access_level, instance_role`. Nazwy teamów/folderów **nie są** w CSV —
Terraform wylicza je z pól ([README.md:88](README.md#L88)).

**Konwencje (obecne):**

| Element | Reguła | Źródło |
|---|---|---|
| Team Grafany | 1 na **unikalną** grupę Entra; `name = entra_group` | [teams.tf:2-6](teams.tf#L2-L6) |
| Team ↔ Entra | `grafana_team_external_group`, `groups=[object_id]` (SSO team sync) | [teams.tf:10-15](teams.tf#L10-L15) |
| Folder nadrzędny | 1 na `(ra, system)`; klucz `"${ra}-${system}"`; tytuł `"${ra} - ${system}"` | [groups.tf:24-33](groups.tf#L24-L33) |
| Podfolder | 1 na `(ra, system, environment)`; klucz `"${ra}-${system}-${environment}"`; tytuł `"${system}-${environment}"`; zagnieżdżony w folderze systemu | [groups.tf:36-46](groups.tf#L36-L46), [folders.tf:10-15](folders.tf#L10-L15) |
| Uprawnienie folderu nadrzędnego | **każdy** team systemu → `View` | [folders.tf:18-30](folders.tf#L18-L30) |
| Uprawnienie podfolderu | per wiersz CSV: `view→View`, `edit→Edit`, `admin→Admin` | [folders.tf:33-45](folders.tf#L33-L45), [groups.tf:10-14](groups.tf#L10-L14) |
| Rola Azure na instancji | tylko wiersze z niepustym `instance_role`; `azurerm_role_assignment` na `grafana_id`, principal = object_id grupy | [rbac_azure.tf:4-11](rbac_azure.tf#L4-L11), [groups.tf:49-52](groups.tf#L49-L52) |
| Prefiks własnych UID | `mgfi-` (ochrona przed nadpisaniem, provider `overwrite=true`) | [content.tf:65,72](content.tf#L65) |
| Nazewnictwo Azure | `company-cost_index-app_name-…-env-N` (`gxyz-ck1-ra0661-…`) | [terraform.tfvars:11-14](terraform.tfvars#L11-L14) |
| Providery | `grafana ~> 4.39`, `azurerm ~> 4.78`, TF `>= 1.9` | [versions.tf](versions.tf) |

**Bezpieczniki (`check`):** każde przypisanie musi mieć niepuste `entra_object_id`
([groups.tf:56-61](groups.tf#L56-L61)) i znany `access_level` ([groups.tf:64-69](groups.tf#L64-L69)).

---

## 2. Stan OBECNY (PRZED) — drzewo dla `rbac_input.csv`

```
Grafana instance
│
├─ 📊 DATA SOURCES (globalne, poza folderami)
│   ├─ poc-testdata                     [grafana-testdata-datasource]  (resource)
│   └─ gxyz-ck1-ra0661-monit-dev-1       [prometheus]  READ-ONLY, data{} (gated enable_amw_example)
│
├─ 📁 RA0395 - OCMS_KLIENT                     (View: wszystkie 13 teamów systemu)
│   ├─ 📂 OCMS_KLIENT-DEV
│   │   │   perms: writer→Edit, reader→View, contrib-dev-1→Edit, view-dev-1→View,
│   │   │          self_user→View, self_admin→Admin, self_owner→Admin
│   │   ├─ 📈 "OCMS_KLIENT-DEV dashboard"          (poc-dash-ocms-dev, TestData)
│   │   └─ 📈 "Managed Prometheus (AMW) — przyklad" (mgfi-example-amw-prom, Prometheus; gated)
│   ├─ 📂 OCMS_KLIENT-DEV2
│   │       perms: writer→Edit, reader→View, contrib-dev-2→Edit, view-dev-2→View
│   └─ 📂 OCMS_KLIENT-UAT
│           perms: writer→Edit, reader→View, contrib-uat-1→Edit, view-uat-1→View
│
├─ 📁 RA0766 - OLIMPS                          (View: wszystkie 6 teamów systemu)
│   └─ 📂 OLIMPS-DEV
│       │   perms: reader→View, writer→Edit, view-dev-1→View, contrib-dev-1→Edit,
│       │          view-dev-2→View, contrib-dev-2→Edit
│       └─ 📈 "OLIMPS-DEV dashboard"             (poc-dash-olimps-dev, TestData)
│
└─ 📁 RA0341 - DINGO                           (View: wszystkie 4 teamy systemu)
    └─ 📂 DINGO-DEV
            perms: reader→View, writer→Edit, contrib-dev-1→Edit, view-dev-1→View
```

**Bilans OBECNY:**

| Zasób | Liczba | Uwaga |
|---|---|---|
| `grafana_team` | **23** | unikalne grupy Entra (writer/reader `ocmsk-dev` liczą się raz mimo DEV+DEV2) |
| `grafana_folder.system` | **3** | OCMS_KLIENT, OLIMPS, DINGO |
| `grafana_folder.env` | **5** | DEV, DEV2, UAT, OLIMPS-DEV, DINGO-DEV |
| `grafana_folder_permission` | **3 + 5** | nadrzędne (View dla wszystkich) + podfoldery (25 wpisów perm łącznie) |
| `grafana_data_source` (resource) | **1** | `poc-testdata` (globalny) |
| `data.grafana_data_source` | **1** | Prometheus read-only (gated) |
| `grafana_dashboard` | **3** | 2× TestData + 1× Prometheus (przy `enable_amw_example=true`) |
| `azurerm_role_assignment` | **3** | self_user→Viewer, self_admin/owner→Admin |

Charakterystyka: **1 globalny data source** dla wszystkich, izolacja **wyłącznie na
poziomie folderów**. Nie ma pojęcia „per-tenant data source" ani uprawnień do samych DS.

---

## 3. Stan DOCELOWY (PO) — z Loki

### Dlaczego Loki przewraca warstwę data source'ów, a NIE foldery

Foldery liczone są z `ra/system/environment` — Loki tego nie zmienia. Zmiana wynika z
trzech ustaleń spotkania:

1. **Loki nie ma row/index-level security** ([podsumowanie:54](../sync/podsumowanie_spotkania.md#L54))
   → jedyną granicą izolacji logów jest **osobny data source per tenant + uprawnienia DS per team**.
2. **Multi-tenancy przez `X-Scope-OrgID`**, model **„organizacja = system / data stream"**,
   **„ten sam data source dodawany wielokrotnie z uprawnieniami per team"**
   ([podsumowanie:53-55](../sync/podsumowanie_spotkania.md#L53-L55)).
3. **Azure Managed Grafana nie ma organizacji** ([podsumowanie:82-83](../sync/podsumowanie_spotkania.md#L82-L83))
   → multi-tenancy realizuje się właśnie przez N data source'ów Loki + `grafana_data_source_permission`.

**Mapowanie tenanta (rekomendacja): 1 data source Loki na podfolder `(ra, system, environment)`**,
`X-Scope-OrgID` = klucz tenanta (np. `ra0395-ocms_klient-dev`). Daje izolację DEV/DEV2/UAT na
poziomie DS (bez tego środowiska mieszają się w jednym strumieniu). Alternatywa coarser:
1 DS na `(ra, system)` (3 DS) — taniej, ale bez izolacji środowisk. Uprawnienia DS wynikają z
tych samych wierszy CSV co uprawnienia podfolderu, zmapowane na czasowniki DS
(`view→Query`, `edit→Edit`, `admin→Admin`).

```
Grafana instance
│
├─ 📊 DATA SOURCES (globalne)
│   ├─ (usunięte)  poc-testdata                    ← TestData wychodzi po wejściu realnych źródeł
│   ├─ ISTNIEJE    gxyz-ck1-ra0661-monit-dev-1       [prometheus] read-only
│   ├─ NOWE        mgfi-loki-RA0395-OCMS_KLIENT-DEV  [loki]  X-Scope-OrgID: ra0395-ocms_klient-dev
│   │               └─ DS perms: writer→Edit, reader→Query, contrib-dev-1→Edit, view-dev-1→Query,
│   │                  self_user→Query, self_admin→Admin, self_owner→Admin
│   ├─ NOWE        mgfi-loki-RA0395-OCMS_KLIENT-DEV2 [loki]  X-Scope-OrgID: ra0395-ocms_klient-dev2
│   │               └─ DS perms: writer→Edit, reader→Query, contrib-dev-2→Edit, view-dev-2→Query
│   ├─ NOWE        mgfi-loki-RA0395-OCMS_KLIENT-UAT  [loki]  X-Scope-OrgID: ra0395-ocms_klient-uat
│   │               └─ DS perms: writer→Edit, reader→Query, contrib-uat-1→Edit, view-uat-1→Query
│   ├─ NOWE        mgfi-loki-RA0766-OLIMPS-DEV       [loki]  X-Scope-OrgID: ra0766-olimps-dev
│   │               └─ DS perms: reader→Query, writer→Edit, view-dev-1→Query, contrib-dev-1→Edit,
│   │                  view-dev-2→Query, contrib-dev-2→Edit
│   └─ NOWE        mgfi-loki-RA0341-DINGO-DEV        [loki]  X-Scope-OrgID: ra0341-dingo-dev
│                   └─ DS perms: reader→Query, writer→Edit, contrib-dev-1→Edit, view-dev-1→Query
│
├─ 📁 RA0395 - OCMS_KLIENT                     (BEZ ZMIAN: View dla 13 teamów)
│   ├─ 📂 OCMS_KLIENT-DEV                        (folder + perms BEZ ZMIAN)
│   │   ├─ 📈 ISTNIEJE  "OCMS_KLIENT-DEV dashboard"        (metryki)
│   │   ├─ 📈 ISTNIEJE  "Managed Prometheus (AMW) — przyklad"
│   │   └─ 📈 NOWE      "OCMS_KLIENT-DEV — Logi (Loki)"    → mgfi-loki-RA0395-OCMS_KLIENT-DEV
│   ├─ 📂 OCMS_KLIENT-DEV2                       (folder + perms BEZ ZMIAN)
│   │   └─ 📈 NOWE      "OCMS_KLIENT-DEV2 — Logi (Loki)"   → mgfi-loki-RA0395-OCMS_KLIENT-DEV2
│   └─ 📂 OCMS_KLIENT-UAT                        (folder + perms BEZ ZMIAN)
│       └─ 📈 NOWE      "OCMS_KLIENT-UAT — Logi (Loki)"    → mgfi-loki-RA0395-OCMS_KLIENT-UAT
│
├─ 📁 RA0766 - OLIMPS                           (BEZ ZMIAN: View dla 6 teamów)
│   └─ 📂 OLIMPS-DEV                             (folder + perms BEZ ZMIAN)
│       ├─ 📈 ISTNIEJE  "OLIMPS-DEV dashboard"            (metryki)
│       └─ 📈 NOWE      "OLIMPS-DEV — Logi (Loki)"        → mgfi-loki-RA0766-OLIMPS-DEV
│
└─ 📁 RA0341 - DINGO                            (BEZ ZMIAN: View dla 4 teamów)
    └─ 📂 DINGO-DEV                              (folder + perms BEZ ZMIAN)
        └─ 📈 NOWE      "DINGO-DEV — Logi (Loki)"          → mgfi-loki-RA0341-DINGO-DEV
```

---

## 4. Diff PRZED → PO

| Warstwa | PRZED | PO | Zmiana |
|---|---|---|---|
| Teamy | 23 | 23 | **bez zmian** (Loki nie tworzy teamów) |
| Foldery nadrzędne | 3 | 3 | **bez zmian** |
| Podfoldery | 5 | 5 | **bez zmian** |
| Uprawnienia folderów | 3 + 5 | 3 + 5 | **bez zmian** |
| Data source Loki | 0 | **5** | **+5** (1 na podfolder; tenant = `X-Scope-OrgID`) |
| Uprawnienia data source | 0 | **25** | **+25** (nowa warstwa `grafana_data_source_permission`, 1:1 z wierszami CSV) |
| Data source TestData | 1 | 0 | **−1** (wycofany) |
| Dashboardy | 3 | **8** | **+5** log-dashboardów (1 na podfolder) |
| Role Azure | 3 | 3 | **bez zmian** |

**Sedno:** szkielet folderów i teamów zostaje nietknięty. Pojawia się **nowa oś izolacji** —
data source per tenant + macierz uprawnień DS — bo w Loki to ona (a nie folder) trzyma
granicę widoczności logów.

---

## 5. Zmiany w kodzie

### Nowy plik `loki.tf`
```hcl
# Data source Loki per podfolder (tenant). X-Scope-OrgID izoluje strumienie —
# w Loki nie ma row-level security, więc granicę trzyma osobny DS + uprawnienia DS.
resource "grafana_data_source" "loki" {
  for_each = local.env_folders

  type = "loki"
  name = "mgfi-loki-${each.key}"
  url  = var.loki_url

  http_headers = {
    "X-Scope-OrgID" = local.loki_tenant[each.key]
  }
}

# Uprawnienia DS per team — spłaszczone (ds_key, group, perm) z wierszy CSV.
resource "grafana_data_source_permission" "loki" {
  for_each = {
    for p in flatten([
      for k, f in local.env_folders : [
        for pr in f.perms : { key = "${k}::${pr.group}", ds = k, group = pr.group, perm = pr.perm }
      ]
    ]) : p.key => p
  }

  datasource_uid = grafana_data_source.loki[each.value.ds].uid
  team           = grafana_team.this[each.value.group].id
  permission     = local.grafana_ds_perm[each.value.perm_level]  # patrz niżej
}
```

### `groups.tf` — nowe locale
```hcl
# Mapowanie access_level -> uprawnienie DATA SOURCE (inne czasowniki niż folder!).
grafana_ds_perm = { view = "Query", edit = "Edit", admin = "Admin" }

# X-Scope-OrgID per podfolder (data stream). Tu: ra-system-environment, małe litery.
loki_tenant = { for k, f in local.env_folders : k => lower(k) }
```
> Uwaga: `env_folders[].perms` trzyma już `perm` przemapowane na *folderowe* `View/Edit/Admin`
> ([groups.tf:44](groups.tf#L44)). Dla DS trzeba nieść **surowy** `access_level` (view/edit/admin)
> obok, żeby zmapować go na `Query/Edit/Admin` — drobna korekta w `env_folders`.

### `content.tf` — dashboardy logowe
`grafana_dashboard "loki_logs"` `for_each = local.env_folders`, panel typu `logs`,
`datasource = grafana_data_source.loki[each.key].uid`, UID `mgfi-logs-${each.key}`,
`folder = grafana_folder.env[each.key].uid`. TestData do wycofania.

### `variables.tf` / `terraform.tfvars`
- `loki_url` — adres gateway Loki (przez Managed Private Endpoint, analogicznie do Prometheusa).
- `loki_tenant_scope` — `"env"` (rekomendacja) lub `"system"`.

### `outputs.tf`
- `loki_data_sources` = mapa `klucz podfolderu → { uid, tenant }`.

### `rbac_input.csv` (opcjonalnie)
Tenant można **wyliczyć** z `ra-system-environment` (spójne z filozofią „Terraform liczy z pól",
[README.md:88](README.md#L88)) — wtedy **CSV bez zmian**. Alternatywa: jawna kolumna
`loki_tenant` / `data_stream`, gdy strumienie nie mapują się 1:1 na środowiska.

---

## 6. Kompromisy i ryzyka (z wniosków spotkania)

- **Tanio vs granularnie vs alerty** ([podsumowanie:114](../sync/podsumowanie_spotkania.md#L114)):
  model „jeden zespół dostarcza monitoring wszystkim" jest pod prąd narzędzi
  ([podsumowanie:116](../sync/podsumowanie_spotkania.md#L116)); granularny dostęp do logów =
  obejścia (N data source'ów) i najpewniej Enterprise.
- **Brak row-level security** ([podsumowanie:54](../sync/podsumowanie_spotkania.md#L54)):
  izolacja stoi w 100% na macierzy `grafana_data_source_permission`. Błąd w macierzy = wyciek
  logów między RA/systemami. Warstwa uprawnień DS staje się tak samo krytyczna jak dziś foldery.
- **Full-text search / jakość logów** ([podsumowanie:76-78,118](../sync/podsumowanie_spotkania.md#L76-L78)):
  bez ustrukturyzowanych logów (JSON) alerty na `message` nie zadziałają — to warunek po stronie aplikacji.
- **Alerty logowe = Loki ruler** (ingestion time), nie Grafana-managed
  ([podsumowanie:70-73](../sync/podsumowanie_spotkania.md#L70-L73)) — **poza** obiektami tego repo.

---

## 7. Otwarte pytania

1. **Granularność tenanta**: per `(ra,system,environment)` — 5 DS, izolacja środowisk
   (rekomendacja) — czy per `(ra,system)` — 3 DS, taniej, bez izolacji DEV/UAT?
2. `X-Scope-OrgID` **wyliczany** z pól CSV (CSV bez zmian) czy jawna kolumna `loki_tenant`?
3. Log-dashboardy dla **każdego** podfolderu, czy tylko tam, gdzie dziś jest przykład?
4. Czy `poc-testdata` znika całkowicie, czy zostaje jako demo obok Loki?
5. Gdzie infrastruktura Loki (AKS, storage, Event Hub, Vector) i kto ją posiada —
   to inny state niż to repo (patrz „Granica własności", [README.md:26](README.md#L26)).
```
