# diagrams/ — diagramy serii (self-hosted LGTM na AKS)

Katalog zawiera **dwie serie** diagramów, każda w formatach D2 + Excalidraw (+ SVG jako
dowód renderu D2) o **identycznej treści logicznej** między formatami:

1. **`architektura-target.*`** — architektura docelowa self-hosted LGTM (poniżej).
2. **`rbac-lgtm*.*`** — **schemat RBAC**: tenanci (`X-Scope-OrgID`) i organizacje Grafany;
   opis i kanoniczna specyfikacja w [`rbac-lgtm.md`](rbac-lgtm.md).

---

## Seria RBAC — tenanci (X-Scope-OrgID) i organizacje Grafany

Kompletny model RBAC dla self-hosted LGTM: jak tenanci `X-Scope-OrgID` i organizacje
Grafany odwzorowują granularny RBAC dla 3 systemów z `rbac_input.csv`
(RA0395/OCMS_KLIENT, RA0766/OLIMPS, opc. RA0341/DINGO) i teamów = grup Entra —
w modelu analogicznym do `managed_grafana_internal`, **rozszerzonym o organizacje/tenantów**.
Rozbity na **3 diagramy o identycznym podziale w obu formatach**:

| Diagram | D2 / Excalidraw / SVG | Co przedstawia |
|---|---|---|
| **1 — Przepływ danych i tenanci** | `rbac-lgtm-1-dataflow.{d2,excalidraw,svg}` | Źródła → kolektory → backendy LGTM → tenanci → organizacje/DS Grafany; zapis/odczyt z `X-Scope-OrgID`, ścieżki prywatne, izolacja sieci |
| **2 — Mapowanie Entra → RBAC** | `rbac-lgtm-2-entra-rbac.{d2,excalidraw,svg}` | Grupy Entra → org_mapping/team sync → organizacje/teamy/foldery/podfoldery → View/Edit/Admin (+ DS permissions Enterprise) |
| **3 — Dashboard cross-tenant** | `rbac-lgtm-3-crosstenant.{d2,excalidraw,svg}` | Org Platform/Shared: dashboard z 2 tenantów (`A\|B`), `Mimir–shared`, team `platform_observability`, wariant Enterprise/LBAC |

**Źródło prawdy:** [`rbac-lgtm.md`](rbac-lgtm.md) (kanoniczna specyfikacja węzłów/krawędzi
+ legenda + drzewo mapowania na obiekty Grafany/Terraform/kolektory + numery linii
transkrypcji). Oba rendery generowane z tego samego modelu — parytet 1:1. D2: `d2 0.7.1`,
`d2 fmt` czysty, render do SVG OK. Excalidraw: JSON zwalidowany (parsowanie + spójne
bindingi + indeksy frakcyjne). **Werdykt formatów** — patrz `rbac-lgtm.md §7`
(dla tego modelu **D2 oddaje go lepiej**: auto-layout zagnieżdżeń + docs-as-code + parytet).

---

## Seria architektury docelowej (self-hosted LGTM na AKS)

Jeden diagram architektury **docelowej** (self-hosted Grafana + Loki + Mimir + Tempo +
Prometheus + Vector + OpenTelemetry Collector na AKS) w **trzech reprezentacjach o
identycznej treści logicznej** — te same węzły, krawędzie, etykiety, strefy, legenda i paleta.

## Pliki

| Plik | Format | Rola |
|------|--------|------|
| `architektura-target.md` | **Mermaid** (+ źródło D2, osadzony SVG) | Render inline w IDE/GitHub — główny podgląd |
| `architektura-target.d2` | **D2 (Terrastruct)** | Źródło „docs as code", renderowalne CLI |
| `architektura-target.svg` | SVG | Dowód renderu D2 (wygenerowany w tym repo) |
| `architektura-target.excalidraw` | **Excalidraw** (JSON sceny) | Import na excalidraw.com / VS Code |

Model bezpieczeństwa jest **odwzorowany z realnego Terraform** PoC
(`../../grafana-poc-example/terraform`: `network.tf`, `aks.tf`, `dns.tf`,
`monitoring.tf`, `grafana.tf`, `rbac.tf`, `identity.tf`, `k8s/prometheus-values.yaml`),
a nie zgadywany — szczegóły w sekcji „Wierność względem Terraform" w
`architektura-target.md`.

## Jak renderować

### D2 → SVG (CLI)

```bash
d2 architektura-target.d2 architektura-target.svg      # jednorazowo
d2 --watch architektura-target.d2                      # podgląd na żywo w przeglądarce
d2 fmt architektura-target.d2                          # formatowanie źródła
```

W tym środowisku render **wykonano pomyślnie** (`d2 0.7.1`, `d2 fmt` czysty) —
zobacz `architektura-target.svg` oraz osadzenie w `architektura-target.md`.

### Excalidraw → import

1. <https://excalidraw.com> → menu (hamburger) → **Open** → `architektura-target.excalidraw`
   (albo przeciągnij plik na kanwę).
2. VS Code: rozszerzenie *Excalidraw* (`pomdtr.excalidraw-editor`) otwiera `.excalidraw`
   natywnie.

> **Headless render `.excalidraw → PNG/SVG` niedostępny** w tym środowisku (brak
> `node` / `npx` / przeglądarki). Plik został jednak zwalidowany jako **poprawny JSON**
> zgodny ze schematem sceny (`type: excalidraw`, `version: 2`); 181 elementów
> (54 prostokąty, 93 teksty, 34 strzałki), wszystkie powiązania (`startBinding`/
> `endBinding`/`containerId`/`boundElements`) wskazują na istniejące elementy, komplet
> wymaganych pól obecny.

### Mermaid

Renderuje się **automatycznie** w podglądzie Markdown (GitHub, VS Code z wtyczką Mermaid,
większość IDE) — nie wymaga instalacji narzędzi. To domyślny „render do md".

## Nota porównawcza — D2 vs Excalidraw (dla tego diagramu)

**D2 (Terrastruct)**
- **Mocne strony:** źródło tekstowe (wersjonowalne w gicie, czytelne diffy);
  auto-layout ogarnia ~30 węzłów i ~34 krawędzie bez ręcznego pozycjonowania; klasy =
  paleta zdefiniowana raz i spójna; zagnieżdżone kontenery wiernie oddają namespace'y
  AKS; `stroke-dash` czytelnie koduje ścieżki prywatne; render CLI → SVG (tu: sukces),
  nadaje się do CI / „docs as code".
- **Słabe strony:** ograniczona kontrola nad dokładnym układem (layout „jaki wyjdzie");
  bogate etykiety wieloliniowe potrafią rozdymać węzły; brak natywnych ikon Azure bez
  dołączania zasobów; przy gęstym grafie krawędzie bywają poprowadzone nieoptymalnie.

**Excalidraw**
- **Mocne strony:** pełna, ręczna kontrola układu i estetyki (styl „whiteboard");
  świetne na prezentacje i szybką, wspólną edycję (także przez nietechnicznych);
  strzałki bound trzymają się węzłów przy przesuwaniu.
- **Słabe strony:** źródło to duży JSON — słabo się diffuje i edytuje ręcznie; **brak
  auto-layoutu** (każdy węzeł/strzałka pozycjonowane ręcznie — pracochłonne przy tej
  skali); trudniej utrzymać spójność przy zmianach; headless render wymaga
  Node/przeglądarki (tu niedostępne).

**Wniosek:** przy ~30 węzłach, zagnieżdżonych namespace'ach i gęstej sieci połączeń z
etykietami **D2 wygrywa na utrzymywalności i szybkości** (auto-layout + docs-as-code +
render w CI). **Excalidraw** wygrywa, gdy diagram ma być **ręcznie dopieszczony pod
prezentację** lub edytowany wspólnie na tablicy. Treść logiczna w obu jest **identyczna**.

## Elementy oznaczone „opcjonalne / do decyzji"

Na wszystkich trzech diagramach wyróżnione białym tłem i **przerywanym obrysem**:

- **Azure DB for PostgreSQL** — zewnętrzny stan / HA Grafany (vs SQLite w podzie).
- **Application Gateway / WAF vs internal Load Balancer** — sposób wystawienia UI Grafany.
- **Prywatny API server AKS** — pełna prywatyzacja płaszczyzny sterowania klastra.
- **DaemonSet-agenci OTel** — obok gatewaya OpenTelemetry Collector (zbieranie węzłowe).

## Legenda (wspólna dla wszystkich formatów)

| Kolor | Warstwa |
|-------|---------|
| żółty `#FFF2CC` | Użytkownicy |
| fioletowy `#E1D5E7` | Tożsamość (Entra / UAMI) |
| niebieski `#DAE8FC` | Azure — usługi zarządzane |
| zielony `#D5E8D4` | Backend obiektowy (Blob) |
| szary `#F5F5F5` | Sieć / VNet / CNI |
| pomarańczowy `#FFE6CC` | Workload na AKS |
| czerwony `#F8CECC` | Źródła telemetrii |
| biały + obrys przerywany | Opcjonalne / do decyzji |

**Styl linii:** ciągła = łączność w klastrze / publiczna; **przerywana = ścieżka
PRYWATNA (Private Endpoint / PLS)**.
