# 10 — Grafana: licencje i koszty (Enterprise/Cloud vs OSS) + wariant „OSS + reconciler" dla team sync

[◄ Model dostępu (grupy Entra)](09-selfhosted-rbac-entra-model.md) · [README](README.md) · [Granulacja uprawnień ►](11-granulacja-uprawnien-warianty.md)

> Dokument analityczny/decyzyjny. Rozwija blocker z [09 §4](09-selfhosted-rbac-entra-model.md)
> (team sync = Enterprise). **Rozstrzyga dylemat licencyjny**: kiedy opłaca się Grafana
> Enterprise / Grafana Cloud, a kiedy **OSS + własny mechanizm synchronizacji** grup Entra na
> uprawnienia. Nie implementuje — liczy koszty, przegląda gotowe narzędzia, rekomenduje
> warunkowo. Kod tylko jako zwięzły szkic.
>
> **Metodyka źródeł.** Każda cena i każde twierdzenie „to tylko Enterprise/Cloud" ma URL i datę
> dostępu (**wszystkie sprawdzone 2026-07-20**). Rozdzielam **fakty ze źródłem** od **szacunków**.
> Ceny „contact sales" nazywam wprost i **nie zmyślam kwot** — liczby z blogów third-party są
> oznaczone jako nieoficjalne widełki do potwierdzenia z Grafana sales.

---

## 1. Streszczenie decyzji (5 zdań)

1. **Sedno problemu jest licencyjne, nie techniczne:** granularny model z
   [`rbac_input.csv`](../../managed_grafana_internal/02-grafana-config/rbac_input.csv) (grupa Entra
   → team → `View/Edit/Admin` na podfolderze) opiera się na **team sync**
   (`grafana_team_external_group`), a to jest funkcja **Grafana Enterprise / Cloud, nie OSS**
   (potwierdzone w dokumentacji Grafany, §5).
2. **Grafana Enterprise self-managed nie ma publicznego cennika** — jest „contact sales", a
   nieoficjalne widełki third-party (≈25 000–150 000 USD/rok, minimum ~25 000 USD/rok) trzeba
   potwierdzić u sprzedawcy; to **rząd wielkości drożej** niż dzisiejszy Azure Managed Grafana.
3. **Grafana Cloud ma team sync we wszystkich planach (nawet Free)**, ale jest **hostowana przez
   Grafana Labs** — łamie wymaganie „self-hosted na AKS", więc traktuję ją tylko jako alternatywę
   z konsekwencjami, nie jako rekomendację.
4. **OSS zamyka lukę na dwa sposoby bez Enterprise:** albo **`org_mapping` w OSS** (multi-org, GA
   od Grafany 11.2.0 — grupa → organizacja+rola, ale bez per-folder granularności), albo **własny
   reconciler** Graph→Grafana API (odtwarza team sync; istnieje nawet gotowy FOSS
   `grafana-oss-team-sync`, GPL-3.0), za cenę własnego kodu do utrzymania.
5. **Rekomendacja warunkowa (szczegóły §8):** przy dzisiejszej skali PoC (3 systemy/RA,
   17 grup Entra) i wymaganiu self-hosted — **OSS + reconciler** (najlepiej adaptacja
   `grafana-oss-team-sync`) bije kosztowo Enterprise; próg, od którego warto rozważyć
   Enterprise/Cloud, to nie tyle liczba userów, co **wielosystemowość + brak zdolności do
   utrzymania własnego kodu + wymogi audytu/wsparcia SLA** (Enterprise ma podłogę ~25 000 USD/rok,
   której sam koszt inżynierski reconcilera przy tej skali nie przekracza).

---

## 2. Co dokładnie odblokowuje licencja (fakty ze źródłem)

| Funkcja | OSS | Enterprise | Cloud | Źródło (dostęp 2026-07-20) |
|---|---|---|---|---|
| **Team sync** (`grafana_team_external_group`, grupa IdP → team) | ⛔ | ✅ | ✅ (każdy plan, też Free) | „Available in Grafana Enterprise and Grafana Cloud" — [docs/configure-team-sync](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-team-sync/) |
| **Fine-grained RBAC** (role custom, `grafana_role`) | ⛔ | ✅ | ✅ | [docs/configure-team-sync](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-team-sync/) (ta sama nota edycji) |
| **`role_attribute_path`** (grupa/claim → globalna rola Viewer/Editor/Admin) | ✅ | ✅ | ✅ | [docs/entraid](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/entraid/) |
| **`org_mapping` / `org_attribute_path`** (grupa → **organizacja** + rola) | ✅ **OSS, GA od 11.2.0** | ✅ | ⚠️ „Supported on Cloud: No" = nie dotyczy Cloud (Cloud = jedna org), **nie** oznacza Enterprise-only | [docs/generic-oauth](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/); wersja: [whats-new „map org-specific roles"](https://grafana.com/whats-new/) + [issue #73448](https://github.com/grafana/grafana/issues/73448) |
| **Foldery / podfoldery / `grafana_folder_permission` per team** | ✅ | ✅ | ✅ | to zwykłe API OSS (potwierdzone w [09 §2](09-selfhosted-rbac-entra-model.md)) |
| **Reporting, audit log, premium data sources, SLA support** | ⛔ | ✅ | ✅ (plan Advanced/Enterprise) | [grafana.com/pricing](https://grafana.com/pricing/) |

**Kluczowe rozróżnienie (naprawia częste nieporozumienie):**

- **`org_mapping` = OSS.** To realna alternatywa dla team sync bez Enterprise — mapuje grupę Entra
  na **osobną organizację** Grafany + rolę. Dostępna w open source, **GA od Grafany 11.2.0**
  (dynamiczne `org_attribute_path`); zapis `<ExternalOrgName>:<OrgIdOrName>:<Role>`. Adnotacja
  „Supported on Cloud: No" w docs znaczy tylko, że **Grafana Cloud pracuje na jednej organizacji**
  i nie stosuje multi-org — a **nie** że to funkcja Enterprise. Dla Entra ID mapowanie działa na
  tym samym atrybucie grup co role mapping.
- **Team sync = Enterprise/Cloud.** Mapuje grupę na **team wewnątrz jednej organizacji**, a team
  dostaje `View/Edit/Admin` na konkretnym **podfolderze** — to dokładnie model z `rbac_input.csv`.
  Tego OSS nie ma.

To rozróżnienie determinuje warianty architektury w §6 (org_mapping = wariant b; team sync
odtworzony kodem = wariant a).

---

## 3. Cenniki (fakty ze źródłem + wyraźnie oznaczone „contact sales")

### 3.1. Grafana OSS
- **Licencja:** Apache 2.0, **0 zł**. Źródło: [grafana.com/pricing](https://grafana.com/pricing/).
- **Realny koszt = nakład inżynierski** na zamknięcie luki team sync (reconciler lub adaptacja
  gotowego FOSS) + dług operacyjny. Wycena w §7.

### 3.2. Grafana Enterprise (self-managed)
- **Cennik: „contact sales" — brak publicznej ceny per użytkownik.** Źródło:
  [grafana.com/pricing](https://grafana.com/pricing/) (self-managed Enterprise → kontakt ze
  sprzedażą).
- **Nieoficjalne widełki third-party (NIE źródło Grafany, do potwierdzenia):** ≈ 25 000–150 000
  USD/rok, z **minimalnym zobowiązaniem rocznym ~25 000 USD**. Źródło:
  [costbench.com/.../grafana-enterprise](https://costbench.com/software/business-intelligence/grafana-enterprise/).
  **Traktować jako szacunek marketingowy, nie ofertę.**
- **Model liczenia „aktywnych użytkowników":** niepublikowany dla self-managed — do potwierdzenia
  z sales (Cloud liczy per active user, patrz niżej; self-managed historycznie per-user w
  kontrakcie).
- **Co odblokowuje istotnego tutaj:** team sync, fine-grained RBAC, reporting, wsparcie SLA (§2).

### 3.3. Grafana Cloud (hostowana — konfrontacja z „self-hosted na AKS")
Źródło całości: [grafana.com/pricing](https://grafana.com/pricing/) (dostęp 2026-07-20).

| Plan | Opłata platformowa | Per aktywny użytkownik (wizualizacja) | Included | Team sync | Uwaga |
|---|---|---|---|---|---|
| **Free** | 0 | — | 3 aktywni użytkownicy, 10k serii metryk, 50 GB logów, retencja 14 dni | ✅ (jest w każdym planie Cloud) | limity zużycia |
| **Pro** | 19 USD/mies. | **8 USD/użytkownik/mies.** (pierwsi 3 gratis), + zużycie (metryki 6,50 USD/1k serii, logi 0,40 USD/GB itd.) | 3 aktywni użytkownicy | ✅ | 8×5 support |
| **Advanced/Enterprise** | wg kontraktu | negocjowane | — | ✅ + audit/SLA | **minimum ~25 000 USD/rok** |

- **Team sync jest w Cloud od planu Free** — z punktu widzenia funkcji Cloud „załatwia" model z CSV.
- **ALE Cloud to Grafana hostowana przez Grafana Labs**, nie na AKS. **Łamie wymaganie
  „self-hosted na AKS"** ([08](08-self-hosted-grafana-analysis.md), [09](09-selfhosted-rbac-entra-model.md)).
  Dane (dashboardy, konfiguracja DS) i tożsamość idą do infrastruktury Grafany — to inny model
  wdrożenia i inny profil zgodności/sieci (prywatne AMW/PLS/on-prem trzeba by wystawiać na
  zewnątrz). Wymieniam jako alternatywę z konsekwencjami, **nie** rekomenduję przy obecnym wymaganiu.

### 3.4. Azure Managed Grafana (punkt odniesienia = „ile kosztuje dziś")
Źródła: [azure.microsoft.com/pricing/details/managed-grafana](https://azure.microsoft.com/en-us/pricing/details/managed-grafana/)
oraz [learn.microsoft.com/.../managed-grafana/faq](https://learn.microsoft.com/en-us/azure/managed-grafana/faq)
(dostęp 2026-07-20).

- **Instancja (SKU Standard):** ~**0,043 USD/godz.** za jednostkę standardową (≈ **31 USD/mies.**,
  ≈ 377 USD/rok), **0,051 USD/godz.** zone-redundant (≈ 37 USD/mies.).
- **Per aktywny użytkownik: ~6 USD/mies.** (= 72 USD/rok/użytkownik). Aktywny użytkownik = unikalny
  user/service account/API key w miesiącu kalendarzowym; rozliczany raz per subskrypcja niezależnie
  od liczby instancji; naliczanie proporcjonalne w pierwszym/ostatnim miesiącu.
- **SKU Essential:** nie da się już tworzyć nowych, **pełna deprecjacja 2027-03-31**.
- **Kluczowy fakt:** Azure Managed Grafana **pracuje na Grafana Enterprise** licencjonowanej od
  Grafana Labs — dlatego ma **team sync „za darmo" w cenie usługi** (dlatego model z
  `managed_grafana_internal` działa). Źródło: [FAQ „Do you use open source Grafana?" → No,
  Grafana Enterprise](https://learn.microsoft.com/en-us/azure/managed-grafana/faq) oraz
  [how-to-sync-teams-with-entra-groups](https://learn.microsoft.com/en-us/azure/managed-grafana/how-to-sync-teams-with-entra-groups).
- **Enterprise plugins nie są wliczone** — osobny płatny add-on.

> Wszystkie powyższe kwoty **nie obejmują** kosztów wspólnych dla każdej opcji: ingest/retencja w
> AMW, compute AKS, ruch sieciowy. Porównanie w §4 dotyczy wyłącznie warstwy „Grafana + dostęp".

---

## 4. Tabela kosztów opcji + progi opłacalności

### 4.1. Roczny koszt warstwy „Grafana + team sync" wg skali
Założenia: 1 instancja, single-unit (nie zone-redundant), rok = 8760 h. **Fakty** = ceny ze
źródeł §3; **szacunki** = nakład inżynierski OSS (§7) i widełki Enterprise. Kwoty zaokrąglone.

| Opcja | Stały koszt/rok | Per user/rok | 20 userów | 100 userów | 500 userów | Self-hosted na AKS? | Team sync? |
|---|---|---|---|---|---|---|---|
| **Azure Managed Grafana (Standard)** *(fakt)* | ~377 USD (instancja) | 72 USD | **~1 800 USD** | **~7 600 USD** | **~36 400 USD** | ⚠️ managed przez Azure (nie AKS) | ✅ wliczony |
| **Grafana Cloud Pro** *(fakt)* | 228 USD (platforma) | 96 USD (3 gratis) + zużycie | ~1 860 USD + zużycie | ~9 540 USD + zużycie | ~47 900 USD + zużycie | ❌ hostowana | ✅ |
| **Grafana Enterprise self-managed** *(contact sales; widełki third-party)* | **~25 000 USD/rok minimum** *(szac.)* | niepubl. | **~25 000+ USD** | ~25 000+ USD | ~25 000–150 000 USD *(szac.)* | ✅ | ✅ |
| **Grafana OSS + reconciler** *(licencja 0 + nakład — szac.)* | **~5 000–12 000 USD/rok** *(szac. nakład, §7)* | ~0 (koszt nie rośnie z liczbą userów) | **~5–12k USD** | **~5–12k USD** | ✅ | ✅ (odtworzony kodem) |
| **Grafana OSS + `org_mapping` (multi-org)** *(licencja 0)* | ~1–3 dni konfiguracji jednorazowo *(szac.)* | ~0 | **~0 (poza konfiguracją)** | ~0 | ~0 | ✅ | ⚠️ tylko org+rola, **bez** per-folder |

Uwagi do tabeli:
- **Koszt OSS+reconciler prawie nie rośnie z liczbą userów** — to koszt kodu/utrzymania, nie
  licencji per-seat. Dlatego przy dużej skali OSS wygrywa kosztowo tym wyraźniej.
- **Enterprise self-managed ma podłogę** (~25k USD/rok szac.) — poniżej niej nie zejdzie niezależnie
  od liczby userów, więc przy małej skali jest **najdroższą** opcją self-hosted.
- **Azure Managed Grafana** to najtańszy start przy małej liczbie userów (bo team sync w cenie i
  brak własnego kodu), ale koszt **rośnie liniowo 72 USD/user/rok**.

### 4.2. Progi opłacalności (break-even)

Przyjmując szacunkowy **all-in koszt reconcilera ≈ 5 000–10 000 USD/rok** (budowa amortyzowana +
utrzymanie, §7):

| Porównanie | Próg | Interpretacja |
|---|---|---|
| **OSS+reconciler vs Azure Managed Grafana (per-user 72 USD/rok)** | ~**70–140 aktywnych userów** | Poniżej ~70 userów **tańszy jest Azure Managed Grafana** (nie warto budować/utrzymywać kodu, żeby oszczędzić <5–10k USD/rok). Powyżej ~140 userów opłata per-user Azure przewyższa koszt reconcilera — **self-hosted OSS zaczyna oszczędzać**, kosztem ryzyka dryfu/bezpieczeństwa. |
| **OSS+reconciler vs Grafana Enterprise self-managed** | praktycznie **zawsze OSS taniej** przy tej skali | Enterprise podłoga ~25k USD/rok (szac.) > koszt reconcilera. Enterprise wygrywa **nie ceną**, lecz brakiem własnego kodu, wsparciem SLA, audytem, reportingiem. |
| **OSS+reconciler vs Grafana Cloud Pro (96 USD/user/rok + zużycie)** | ~**55–110 userów** | Podobnie jak Azure, ale Cloud **łamie self-hosted** — próg czysto teoretyczny. |
| **Kiedy Enterprise/Cloud „bije" OSS mimo ceny** | **>~5–10 niezależnych systemów/RA** *(szac.)* **LUB** brak zespołu do utrzymania kodu **LUB** twardy wymóg audytu/SLA/reportingu | Próg jest **organizacyjny, nie userowy**: im więcej systemów i im mniejsza zdolność utrzymania reconcilera, tym szybciej wygrywa gotowa licencja. |

> **Wniosek progowy:** czysto kosztowo Enterprise self-managed niemal nigdy nie „wygrywa" z
> OSS+reconciler przy skali tego projektu — jego uzasadnieniem jest **redukcja ryzyka i wsparcie**,
> nie oszczędność. Realny dylemat brzmi: **Azure Managed Grafana (zostań, płać per-user)** vs
> **OSS+reconciler na AKS (zapłać kodem, zyskaj self-hosted i brak per-seat)**. Break-even ≈
> 70–140 userów.

---

## 5. Część B — luka OSS i jak ją zamknąć

### 5.1. Na czym polega luka (precyzyjnie)
- **Czego OSS nie ma:** team sync (`grafana_team_external_group`) — automatycznego mapowania
  członkostwa w grupie Entra na **team**, a przez to na `View/Edit/Admin` konkretnego **podfolderu**.
  To serce modelu z [`teams.tf`](../../managed_grafana_internal/02-grafana-config/teams.tf) i
  [`folders.tf`](../../managed_grafana_internal/02-grafana-config/folders.tf).
- **Co OSS ma i można wykorzystać:**
  - `[auth.azuread]` / `[auth.generic_oauth]` z **`role_attribute_path`** → globalna rola
    (Viewer/Editor/Admin całej org);
  - **`org_mapping` / `org_attribute_path`** (OSS, GA 11.2.0) → grupa Entra na **organizację** +
    rolę;
  - **JIT user provisioning** przy pierwszym logowaniu OAuth (user powstaje dopiero po zalogowaniu —
    to problem dla reconcilera, patrz niżej);
  - **`grafana_team`, `grafana_folder`, `grafana_folder_permission`** przez API/Terraform — działają
    w OSS; brakuje tylko **automatycznego** wiązania członka grupy z teamem.

### 5.2. Warianty architektury zamknięcia luki

#### (a) Reconciler grup → teamów (odtworzenie team sync kodem)
Usługa/CronJob w AKS (ns `monitoring`) czyta członkostwo grup z **Microsoft Graph** i przez
**Grafana HTTP API** synchronizuje: `teams` → membership → `folder permissions` wg
[`rbac_input.csv`](../../managed_grafana_internal/02-grafana-config/rbac_input.csv).

- **Zalety:** wierne odtworzenie modelu per-folder z CSV; jedna organizacja; zero Enterprise;
  koszt niezależny od liczby userów.
- **Problem „user musi istnieć w Grafanie":** członka teamu dodaje się po **user id**, a user w OSS
  powstaje dopiero przy **pierwszym logowaniu OAuth** (JIT). Rozwiązania:
  1. **Pre-provisioning userów** przez Admin API (`POST /api/admin/users`) na podstawie listy
     członków z Graph — reconciler zakłada konta zanim ktokolwiek się zaloguje;
  2. albo **sync tylko dla już zalogowanych** (reconciler dopisuje do teamów userów, którzy
     istnieją) + fallback `org_mapping` na baseline rolę dla reszty;
  3. dopasowanie po `login`/`email` z Graph (`userPrincipalName`).
- **Uwaga:** to jest dokładnie to, co robi gotowy FOSS `grafana-oss-team-sync` (§5.3) — **nie ma
  potrzeby pisać od zera**, jeśli jego model pasuje.

#### (b) Multi-org + `org_mapping` (czysty OSS, bez reconcilera i bez Enterprise)
Każdy system/RA = osobna **organizacja** Grafany; grupy Entra mapowane na org+rola przez
`org_mapping` w `grafana.ini`. **Bez** własnego kodu, **bez** Enterprise.

```ini
# grafana.ini — [auth.azuread] (OSS, org_mapping GA 11.2.0)
# <ExternalOrgName(=nazwa/obj grupy)>:<OrgIdOrName>:<Role>
org_mapping = "self_prod_ra0395-dev_admin:RA0395-OCMS_KLIENT:Admin nonprd_view_gxyz-...-ra0766-...:RA0766-OLIMPS:Viewer"
# rola globalna w obrębie danej org: Viewer/Editor/Admin
```

- **Zalety:** zero kodu, zero licencji, natywne, deklaratywne.
- **Wady (istotne):** granularność tylko **org + globalna rola**, **nie** per-folder — user jest
  Viewer/Editor/Admin **całej organizacji systemu**, nie pojedynczego podfolderu środowiska. Do
  tego: **izolacja per-org** (brak współdzielenia dashboardów/DS między orgami — każdą trzeba
  duplikować), **UX przełączania organizacji** (user w wielu systemach musi przełączać org),
  brak wspólnego widoku. Odpowiada „degradacji" z [09 §4](09-selfhosted-rbac-entra-model.md), tyle
  że na poziomie org zamiast globalnej roli — nieco lepiej izoluje systemy, ale wciąż **nie
  spełnia** wymagania „View/Edit/Admin na podfolderze środowiska".

#### (c) Terraform provider `grafana` jako reconciler stanu
`grafana_team` + membership utrzymywane deklaratywnie w OSS.

- **Działa:** `grafana_team`, `grafana_folder`, `grafana_folder_permission` — tak jak w
  `02-grafana-config` (przenośne 1:1, [09 §2](09-selfhosted-rbac-entra-model.md)).
- **Ograniczenie kluczowe:** `grafana_team_external_group` **nie zadziała w OSS** (to team sync).
  Membership trzeba by utrzymywać zasobem **po user id** (`grafana_team_membership`/`_member`), a
  **nie po grupie** — czyli Terraform musiałby znać listę userów każdej grupy (odczyt z Graph przez
  `azuread`/data source) i user musiałby już istnieć w Grafanie (ten sam problem JIT). Terraform
  nie reaguje na zmiany członkostwa w czasie rzeczywistym — to „reconciler co apply", nie ciągły.
  **Wniosek:** nadaje się na strukturę (teamy/foldery/uprawnienia), **nie** na bieżącą synchronizację
  członkostwa. Najlepiej łączyć: Terraform robi szkielet, reconciler (a) lub gotowy FOSS pilnuje
  członkostwa.

### 5.3. Gotowe narzędzia — research (URL, aktywność, licencja, dojrzałość)

| Narzędzie | URL | Licencja | Aktywność / dojrzałość | Czy zamyka lukę team sync? |
|---|---|---|---|---|
| **skuethe/grafana-oss-team-sync** | [github.com/skuethe/grafana-oss-team-sync](https://github.com/skuethe/grafana-oss-team-sync) | **GPL-3.0** | ~22★, v0.3.2 (maj 2026), ~580 commitów, **aktywny, ale 1 główny maintainer**; wymaga Grafany ≥11.1 | **TAK, bezpośrednio.** Synchronizuje teamy, userów i **foldery z uprawnieniami** (viewer/editor/admin) z **Entra ID** do OSS. Działa jako „single source of truth" — **nadpisuje** uprawnienia folderów przy każdym syncu. Wymaga uprawnień Graph (`GroupMember.Read.All`, `User.ReadBasic.All`). **Najlepiej dopasowany** do modelu z `rbac_input.csv`. Ryzyko: bus factor = 1, GPL-3.0 (do akceptacji przez dział prawny). |
| **NovatecConsulting/grafana-ldap-sync-script** | [github.com/NovatecConsulting/grafana-ldap-sync-script](https://github.com/NovatecConsulting/grafana-ldap-sync-script) | **Apache-2.0** | ~31★, ostatnie wydanie v1.1.1 (**luty 2022 — przestarzały**) | Częściowo — synchronizuje userów/teamy/uprawnienia folderów, ale **tylko z LDAP**, **brak Entra ID**. Dla Entra nieprzydatny bez przepisania. Ryzyko porzucenia: wysokie. |
| **grafana-operator/grafana-operator** | [github.com/grafana/grafana-operator](https://github.com/grafana/grafana-operator) | Apache-2.0 | duży, aktywny, oficjalny | **NIE zamyka luki.** Zarządza instancjami, dashboardami, datasource'ami i **folderami** (CRD), ale **nie ma `GrafanaTeam`/team sync** — prośba o CRD Teams/Orgs ([issue #549](https://github.com/grafana-operator/grafana-operator/issues/549)) zamknięta jako duplikat, brak implementacji. Uzupełnia [08 §2 wariant D](08-self-hosted-grafana-analysis.md), ale **nie** rozwiązuje membershipu grup. |
| **Grafana Terraform generator (Entra→teams)** | [grafana.com/docs/learning-paths/configure-grafana-terraform](https://grafana.com/docs/learning-paths/configure-grafana-terraform/create-teams/) | — | oficjalny learning path | Generuje Terraform mapujący grupy Entra na teamy z folderami — **ale zakłada team sync = Enterprise/Cloud**. Nie działa w OSS bez licencji. |

**Werdykt narzędziowy:** realnie tylko **`grafana-oss-team-sync`** zamyka lukę w OSS end-to-end dla
Entra ID i pokrywa się z modelem z CSV. To zmienia „napisz reconciler od zera" na **„zaadaptuj i
utrzymuj istniejący FOSS"** — mniejszy nakład, ale świadomy dług (GPL-3.0, jeden maintainer).

### 5.4. Jeśli budować własne (lub adaptować FOSS) — szkic i nakład

**Stack i osadzenie:**
- Język: **Go** przy adaptacji gotowca (`grafana-oss-team-sync` jest napisany w Go — [repo](https://github.com/skuethe/grafana-oss-team-sync), dostęp 2026-07-21), albo **Go/Python** przy budowie od zera (oba mają dojrzałe SDK do Microsoft Graph i Grafana API). Uwaga: skrypty `resolve_object_ids.*` w `managed_grafana_internal` to Bash/PowerShell, nie Python — nie są tu wyznacznikiem języka.
- Gdzie: **CronJob w ns `monitoring`** (np. co 15–30 min), spójnie z [08](08-self-hosted-grafana-analysis.md).
- Tożsamość do Graph: **AKS Workload Identity** (UAMI + federated credential), spójnie z
  [08 §4.1](08-self-hosted-grafana-analysis.md) — **zero sekretów**. Uprawnienia app:
  `GroupMember.Read.All`, `User.ReadBasic.All`.
- Token do Grafany: service-account token z API OSS (jak [09 §2](09-selfhosted-rbac-entra-model.md)),
  z Key Vault (CSI).

**Wymagane cechy:**
- **Źródło prawdy = `rbac_input.csv`** (ten sam plik co Terraform — jeden model dla obu Grafan).
- **Idempotencja** (deklaratywny reconcile: policz stan docelowy z CSV+Graph, zdejmij różnicę).
- **Obsługa „group overage" >200 grup** — czytać członkostwo z Graph (transitiveMembers), nie z
  claimu tokenu ([09 §3](09-selfhosted-rbac-entra-model.md)).
- **Deprovisioning** — usuwanie z teamu/uprawnień, gdy user wypadł z grupy (najczęściej pomijane).
- **Pre-provisioning userów** (Admin API) — obejście JIT (§5.2a).
- **Obserwowalność** (metryki reconcile do Prometheusa), **tryb dry-run**, logi audytowe.
- **Guardy rate-limit** Graph i Grafana API.

**Szkic pętli (ilustracja):**
```
for row in rbac_input.csv:                      # źródło prawdy
    team   = ensure_team(row.entra_group)        # POST /api/teams (idempotentnie)
    members = graph.group_transitive_members(row.entra_object_id)  # obejście overage
    for m in members:
        uid = ensure_user(m.upn)                 # pre-provision (obejście JIT)
        ensure_team_member(team, uid)
    ensure_folder_permission(row.ra, row.system, row.environment,
                             team, map(row.access_level))  # View/Edit/Admin
prune(teams/members/permissions not in desired) # deprovisioning
```

**Nakład (szacunek):**
- **Adaptacja `grafana-oss-team-sync`** (rekomendowane): ~**5–10 roboczodni** (dopasowanie do CSV,
  Workload Identity, deploy CronJob, dry-run, testy) + **~1 dzień/mies. utrzymania** (~12–15 dni/rok).
- **Budowa od zera:** ~**15–25 roboczodni** budowy + ~**12–18 dni/rok** utrzymania (overage, JIT,
  deprovisioning, rate-limity to najkosztowniejsze fragmenty).
- **All-in rocznie** (utrzymanie + amortyzacja + ryzyko/on-call): **~5 000–12 000 USD/rok** (szac.,
  przy stawce blended ~500 USD/dzień).

**Ryzyka:** dryf (rozjazd stanu Grafany z CSV/Graph), rate-limit Graph/Grafana, bezpieczeństwo
tokenu SA, bus factor (własny kod lub FOSS jednego maintainera), zmiany API Grafany między wersjami.

---

## 6. Rekomendacja warunkowa

> **Domyślnie przy tym projekcie (self-hosted na AKS, skala PoC: 3 systemy/RA, 17 grup Entra):**
> **Grafana OSS + reconciler** — konkretnie **adaptacja `grafana-oss-team-sync`** (a nie pisanie od
> zera), źródło prawdy = `rbac_input.csv`, tożsamość Graph przez Workload Identity. Uzasadnienie:
> spełnia self-hosted, odtwarza per-folder model z CSV, koszt (~5–12k USD/rok szac.) jest
> **rząd wielkości niższy** niż podłoga Enterprise self-managed (~25k USD/rok szac.), a licencja = 0.

Warunki przełączające decyzję:

1. **Jeśli app registration jest niedostępna** (blocker #1 z [09 §3](09-selfhosted-rbac-entra-model.md)) →
   **żaden** wariant mapowania grup nie zadziała; zostaje lokalny admin (PoC bez modelu dostępu).
   To trzeba rozstrzygnąć **przed** wyborem licencji.
2. **Jeśli >~5–10 niezależnych systemów/RA LUB brak zespołu do utrzymania kodu LUB twardy wymóg
   audytu/reportingu/SLA** → **Grafana Enterprise self-managed** (mimo ceny — kupujesz brak własnego
   kodu i wsparcie), po potwierdzeniu oferty z sales.
3. **Jeśli akceptowalne odejście od „self-hosted"** i liczy się czas do wartości → **Grafana Cloud**
   (team sync w każdym planie, w tym Free) — ale świadomie łamie wymaganie AKS i wynosi dane do
   Grafana Labs.
4. **Jeśli wystarczy izolacja per-system bez per-folder** (kompromis) → **OSS + `org_mapping`
   multi-org** — zero kodu i zero licencji, kosztem duplikacji dashboardów/DS i UX przełączania org.
5. **Zostanie na Azure Managed Grafana** jest racjonalne, dopóki liczba aktywnych userów jest
   **poniżej ~70** — wtedy 72 USD/user/rok jest tańsze niż budowa+utrzymanie reconcilera, a team
   sync masz w cenie. Migracja na self-hosted OSS zaczyna się kosztowo opłacać **powyżej ~140
   userów** (albo gdy self-hosted jest wymogiem twardym, nie kosztowym).

---

## 7. Otwarte pytania / do potwierdzenia

**Do potwierdzenia z Grafana sales:**
1. **Realna cena Grafana Enterprise self-managed** — minimum roczne, model per-user vs per-active-user,
   czy widełki ~25–150k USD/rok się potwierdzają (dziś to szacunek third-party, nie oferta).
2. **Jak self-managed liczy „aktywnych użytkowników"** i czy jest floor userów.
3. **Czy Enterprise plugin add-on** (potrzebny jakikolwiek?) jest w cenie czy osobno.

**Do potwierdzenia wewnętrznie (determinują próg):**
4. **Ilu realnie jest/będzie aktywnych użytkowników?** To główny parametr break-even (~70 / ~140).
5. **Ile jest niezależnych systemów/RA docelowo?** (dziś w CSV: 3 — RA0395/OCMS_KLIENT,
   RA0766/OLIMPS, RA0341/DINGO; 17 unikalnych grup Entra w 19 wierszach przypisań). Powyżej ~5–10 systemów rośnie argument za Enterprise.
6. **Czy zespół ma zdolność utrzymania własnego kodu/FOSS** (bus factor `grafana-oss-team-sync` = 1)?
7. **App registration** — czy admin tenanta ją utworzy (blocker #1)? Bez niej cała analiza mapowania
   grup jest bezprzedmiotowa.
8. **Akceptacja licencji GPL-3.0** `grafana-oss-team-sync` przez dział prawny (vs Apache 2.0 samej
   Grafany).
9. **Wymogi audytu/reportingu/SLA** — czy są twarde (przechylają ku Enterprise/Cloud)?
10. **Czy „self-hosted na AKS" jest wymogiem twardym**, czy Cloud jest dopuszczalny (to całkowicie
    zmienia rekomendację — Cloud ma team sync od Free)?

---

### Źródła (dostęp 2026-07-20)
- Team sync = Enterprise/Cloud: <https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-team-sync/>
- Cennik Grafana Cloud (Free/Pro/Advanced), self-managed „contact sales": <https://grafana.com/pricing/>
- `org_mapping`/`org_attribute_path` (OSS, generic-oauth/entraid): <https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/>, <https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/entraid/>
- Wersja org mapping (11.2.0): <https://github.com/grafana/grafana/issues/73448>
- Azure Managed Grafana cennik: <https://azure.microsoft.com/en-us/pricing/details/managed-grafana/>
- Azure Managed Grafana FAQ (Enterprise pod spodem, aktywny user, Essential deprecacja): <https://learn.microsoft.com/en-us/azure/managed-grafana/faq>
- Azure team sync z Entra: <https://learn.microsoft.com/en-us/azure/managed-grafana/how-to-sync-teams-with-entra-groups>
- Widełki Enterprise (nieoficjalne, third-party): <https://costbench.com/software/business-intelligence/grafana-enterprise/>
- `grafana-oss-team-sync`: <https://github.com/skuethe/grafana-oss-team-sync>
- `grafana-ldap-sync-script`: <https://github.com/NovatecConsulting/grafana-ldap-sync-script>
- grafana-operator (brak GrafanaTeam CRD): <https://github.com/grafana/grafana-operator>, <https://github.com/grafana-operator/grafana-operator/issues/549>
