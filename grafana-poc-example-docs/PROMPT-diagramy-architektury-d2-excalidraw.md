# PROMPT: kompletny diagram architektury docelowej — D2 (Terrastruct) + Excalidraw

> Prompt do odpalenia na agencie. Ma stworzyć **JEDEN, kompletny, szczegółowy diagram
> architektury docelowej** (self-hosted LGTM na AKS) w **dwóch formatach o identycznej treści**:
> **D2 (Terrastruct)** i **Excalidraw** — po to, by porównać jakość obu. Poziom i wzorce
> bezpieczeństwa **odwzoruj z realnego kodu Terraform** PoC, a nazewnictwo/usługi — z architektury
> Azure.

---

## Rola i cel

Jesteś architektem chmury + autorem diagramów. Narysuj **architekturę docelową**: **self-hosted
stack observability na AKS** (Grafana + Loki + Mimir + Tempo + Prometheus + Vector + OpenTelemetry
Collector), zasilany m.in. z **Azure Event Hub**, z **kompletem komponentów, połączeń i warstw
bezpieczeństwa**. To ma być diagram, po którym inżynier odtworzy setup: co gdzie działa, jak
płyną dane, jak działa tożsamość/sekrety/sieć, gdzie są granice zaufania.

Wynik: **dwa pliki o tej samej zawartości logicznej** — `.d2` (Terrastruct) i `.excalidraw` —
oraz krótki `README` z instrukcją renderowania i notą porównawczą.

## Krok 0 — przeczytaj realny model bezpieczeństwa (obowiązkowe)

Przeczytaj Terraform w `/Users/artur.prawdzik/repo/sync/grafana-poc-example/terraform` i wypisz
(na własny użytek) faktyczne wzorce bezpieczeństwa do odwzorowania — **nie zgaduj**:
- `network.tf` — VNet-y i podsieci, adresacja; `aks.tf` — Azure CNI **overlay**, `pod_cidr`,
  tożsamość klastra (SystemAssigned), kubelet identity, dodatek metryk.
- `dns.tf` — **prywatna strefa DNS** (`privatelink.*.prometheus.monitor.azure.com`) zlinkowana do
  VNet + **Private Endpoint**; wzorzec prywatnej ścieżki do danych.
- `monitoring.tf` — AMW-A/AMW-B, DCE/DCR (to zostanie **zastąpione** przez Mimir/Loki/Tempo —
  patrz niżej; ale wzorzec „prywatny endpoint + strefa DNS" przenosimy).
- `grafana.tf` + `rbac.tf` + `identity.tf` — tożsamości i **role least-privilege**
  (`Monitoring Data Reader`, `Monitoring Metrics Publisher`, `Network Contributor`, `Grafana
  Admin/Viewer`), brak sekretów w kodzie, usunięty app-registration (blocker), Grafana MI.
- `k8s/prometheus-values.yaml` — **wewnętrzny LoadBalancer + Private Link Service**
  (`pls-prometheus`) i **Managed Private Endpoint** z Grafany; `remote_write` z auth `azuread`
  (tożsamość kubeleta z IMDS). To wzorce prywatnej łączności i tożsamości do przeniesienia.

**Mapowanie PoC → docelowe (zaznacz w diagramie, że to ewolucja):**
- Managed Grafana → **self-hosted Grafana na AKS**.
- AMW/DCR/DCE (managed Prometheus) → **self-hosted Mimir** (+ Prometheus jako scraper) na AKS.
- `remote_write` do AMW → `remote_write` do **Mimir**.
- Auth kubelet/IMDS (`azuread`) → **AKS Workload Identity (UAMI + federated credential)**.
- Prywatna ścieżka PE + strefa DNS → **Private Endpointy + prywatne strefy DNS** do usług Azure
  (Event Hub, Blob Storage, Key Vault).
- PLS + Managed Private Endpoint → wzorzec prywatnego wystawienia (dla UI Grafany / cross-VNet).

## Architektura do narysowania (KOMPLETNA — wszystkie węzły i krawędzie)

### Strefy/grupy (kontenery na diagramie)
1. **Użytkownicy i tożsamość** — użytkownicy końcowi; **Entra ID** (OAuth/OIDC dla logowania do
   Grafany; app registration; grupy → org/team).
2. **Źródła telemetrii** — aplikacje (OTLP), zasoby Azure z **diagnostic settings** (logi).
3. **Azure — usługi zarządzane** — **Event Hub**; **Storage Account (Blob)** (backend obiektowy
   dla Loki/Mimir/Tempo); **Key Vault** (sekrety); (opc.) **Azure DB for PostgreSQL** (stan/HA
   Grafany); **Private DNS Zones**; **Private Endpoints**; (opc.) **Application Gateway/WAF** lub
   **wewnętrzny Load Balancer** dla UI.
4. **Sieć** — **VNet + podsieci** (`snet-aks`, `snet-pe` dla PE, itd.), Azure **CNI overlay**
   (`pod_cidr` osobny), (opc.) prywatny API server AKS, network policies.
5. **Klaster AKS** (z podziałem na namespace'y):
   - **kolektory** (Deploymenty na AKS — to tu zwykle działają w takich setupach):
     - **Vector** (czyta z Event Hub, pcha do Loki),
     - **OpenTelemetry Collector** (gateway; odbiera OTLP, tail sampling, pcha do Tempo; opc.
       DaemonSet-agenci),
     - **Prometheus** (tryb agent/scrape; `remote_write` do Mimira);
   - **backendy LGTM** (na AKS, dane w Blob): **Loki**, **Mimir**, **Tempo** — z kluczowymi
     komponentami (np. distributor / ingester / querier / compactor / store-gateway; ruler dla
     Mimir/Loki);
   - **Grafana** (Deployment);
   - **wspólne**: Ingress controller / internal LB; **CSI Secrets Store** (Key Vault); webhook
     **Workload Identity**; ServiceAccounts z adnotacją `azure.workload.identity/client-id`.
6. **Tożsamości zarządzane** — **UAMI** per workload (np. `uami-vector`, `uami-lgtm`,
   `uami-grafana`) + **federated credentials** (issuer OIDC AKS → `system:serviceaccount:...`);
   role RBAC least-privilege (mapowane z PoC).

### Połączenia (każda krawędź z etykietą: protokół / auth / `X-Scope-OrgID` / prywatna?)
- Aplikacje/zasoby Azure → **Event Hub** (diagnostic settings; logi).
- **Vector** → Event Hub (odczyt; protokół Kafka/AMQP; auth **Workload Identity**, rola *Azure
  Event Hubs Data Receiver*; przez **Private Endpoint** + prywatna strefa DNS).
- **Vector** → **Loki** (push HTTP; **`X-Scope-OrgID`** = tenant).
- Aplikacje → **OTel Collector** (OTLP).
- **OTel Collector** → **Tempo** (OTLP; tail sampling; **`X-Scope-OrgID`**).
- **Prometheus** → scrape targetów (pull) **oraz** `remote_write` → **Mimir** (**`X-Scope-OrgID`**;
  auth Workload Identity).
- **Loki / Mimir / Tempo** → **Storage Account (Blob)** (chunks/blocks; auth **Workload
  Identity**, rola *Storage Blob Data Contributor*; przez **Private Endpoint** + strefa DNS).
- **Grafana** → **Loki / Mimir / Tempo** (query LogQL/PromQL/TraceQL; **`X-Scope-OrgID` przypięty
  per data source w danej organizacji**; łączność wewnątrzklastrowa ClusterIP).
- **Grafana** → **CSI Secrets Store** → **Key Vault** (hasło admina, client secret OAuth; auth
  Workload Identity, rola *Key Vault Secrets User*; przez Private Endpoint).
- **Grafana** → **Entra ID** (OIDC login; org_mapping/team sync).
- **Użytkownicy** → **Ingress / App Gateway / internal LB** → **Grafana UI** (HTTPS) — **tylko
  UI**.
- **Workload Identity**: ServiceAccount → federated credential → **UAMI** → **Entra ID** (wymiana
  tokenu).

### Adnotacje bezpieczeństwa (MUSZĄ być widoczne na diagramie)
- **Granica zaufania tenantów:** Loki/Mimir/Tempo **ufają nagłówkowi `X-Scope-OrgID`** → są
  **nieosiągalne bezpośrednio dla użytkowników** (ClusterIP, niepubliczne). Dostęp mają **tylko**
  kolektory (zapis) i Grafana (odczyt). Zaznacz to jako wyraźną strefę/granicę.
- **Prywatna łączność do Azure:** Event Hub, Blob, Key Vault dostępne przez **Private Endpoints +
  prywatne strefy DNS** (wzorzec z `dns.tf`).
- **Zero sekretów w kodzie:** tożsamość przez **Workload Identity**; sekrety w **Key Vault (CSI)**.
- **RBAC least-privilege:** wypisz na krawędziach/notatkach role (analogicznie do `rbac.tf`:
  Event Hubs Data Receiver, Storage Blob Data Contributor, Key Vault Secrets User; oraz role
  Grafany: Admin/Viewer / org_mapping).
- **Sieć:** Azure CNI overlay, BYO subnet, (opc.) prywatny API server; UI za Ingress/WAF lub
  wewnętrznym LB; backendy prywatne.

> Jeśli któryś element jest opcjonalny/decyzją otwartą (np. Postgres dla HA Grafany, App Gateway
> vs internal LB, DaemonSet OTel), **narysuj go z adnotacją „opcjonalne / do decyzji"** — nie
> pomijaj, ale oznacz.

## Wymagania formatu — D2 (Terrastruct)

- Poprawna składnia **D2** renderowalna CLI `d2` (jeśli `d2` jest dostępne — **zrenderuj do SVG**
  na dowód poprawności; jeśli nie, zaznacz to i zadbaj o `d2 fmt`-czystość).
- **Kontenery zagnieżdżone** dla stref/namespace'ów; `direction` ustawiony sensownie.
- **Klasy/style** kodujące warstwy kolorem (Azure-managed / AKS-workload / storage / identity /
  network / users) — spójny paletą z Excalidraw.
- **Etykiety krawędzi** z protokołem/auth/`X-Scope-OrgID`; styl linii: **przerywana = ścieżka
  prywatna** (PE/PLS), ciągła = w klastrze/publiczna.
- **Legenda** (co znaczą kolory i styl linii). Opcjonalnie ikony Azure, o ile plik zostaje
  samowystarczalny/renderowalny; w razie wątpliwości użyj kształtów z etykietą tekstową.

## Wymagania formatu — Excalidraw

- Poprawny plik `.excalidraw` (JSON sceny): `{"type":"excalidraw","version":2,"source":...,
  "elements":[...],"appState":{...},"files":{}}`.
- Elementy z **kompletem wymaganych pól** (id, type, x, y, width, height, angle, strokeColor,
  backgroundColor, fillStyle, strokeWidth, strokeStyle, roughness, opacity, groupIds, seed,
  version, versionNonce, isDeleted, boundElements, updated, link, locked; dla `text`: text,
  fontSize, fontFamily, textAlign, verticalAlign, containerId, originalText, lineHeight; dla
  `arrow`: points, startBinding/endBinding wiążące do kształtów).
- **Strefy** jako prostokąty/`frame` z tytułem; **grupowanie** (`groupIds`) węzłów w strefach;
  **strzałki powiązane** (bound) do węzłów z **etykietami** (protokół/auth/tenant); **legenda**;
  **paleta kolorów identyczna** z D2.
- Rozmieść elementy **czytelnie, bez nachodzenia**; plik musi się otworzyć na excalidraw.com
  (zadbaj o poprawny JSON — zweryfikuj parsowanie).

## Spójność między formatami (kluczowe — user porównuje)

- **Ten sam zbiór węzłów, krawędzi, etykiet, stref i legenda** w obu plikach. Różnić się może
  tylko styl renderowania właściwy narzędziu, **nie treść**.
- Ta sama paleta kolorów per warstwa. Ta sama konwencja linii (przerywana = prywatna).

## Pliki wyjściowe

- `grafana-poc-example-docs/diagrams/architektura-target.d2`
- `grafana-poc-example-docs/diagrams/architektura-target.excalidraw`
- `grafana-poc-example-docs/diagrams/architektura-target.md` — **render do Markdown** (patrz niżej).
- `grafana-poc-example-docs/diagrams/README.md` — jak renderować (`d2 architektura-target.d2 out.svg`;
  import `.excalidraw` na excalidraw.com), krótka **nota porównawcza** (mocne/słabe strony obu w
  tym przypadku) i lista elementów oznaczonych „opcjonalne/do decyzji".
- (Jeśli `d2` dostępne) `grafana-poc-example-docs/diagrams/architektura-target.svg` jako dowód renderu.

## Render do Markdown (`architektura-target.md`)

Cel: **diagram widoczny inline w Markdown** (IDE/GitHub) bez konieczności instalowania narzędzi.
W tym środowisku brak `d2`, `node`/`npx`, `rsvg-convert` — więc:

1. **Mermaid = gwarantowany render inline.** Umieść w `architektura-target.md` **wersję Mermaid
   TEJ SAMEJ architektury** (ten sam zbiór węzłów/krawędzi/stref/legenda) — renderuje się od razu
   w podglądzie Markdown. To główny „render do md".
2. Dołącz **pełne źródło D2** w bloku ```d2 (do wglądu/porównania) oraz instrukcję renderu.
3. Dołącz **instrukcję importu** `.excalidraw` na excalidraw.com (headless render niedostępny —
   brak node/przeglądarki).
4. **Best-effort:** spróbuj zainstalować `d2` (oficjalny skrypt lub `brew`) i zrenderować
   `architektura-target.d2` → `.svg`; jeśli się uda, **osadź SVG** w md. Jeśli instalacja wymaga
   zatwierdzenia/sieci lub zawiedzie — **nie blokuj się**, pomiń i zostaw Mermaid + źródła.
5. `architektura-target.md` ma też zawierać **notę porównawczą** (co lepiej wyszłoby w D2 vs
   Excalidraw) i legendę.

> Wersje Mermaid, D2 i Excalidraw muszą być **treściowo identyczne** (te same węzły/krawędzie/
> etykiety/strefy). Mermaid służy podglądowi w md; D2 i Excalidraw to formaty do porównania jakości.

## Kryteria akceptacji

- **Kompletność:** wszystkie węzły, połączenia i adnotacje bezpieczeństwa z sekcji wyżej są
  obecne w **obu** plikach; nic z listy nie pominięte (opcjonalne — oznaczone).
- **Poprawność:** D2 renderuje się (lub `d2 fmt`-czyste); Excalidraw to poprawny, otwieralny JSON.
- **Wierność bezpieczeństwa:** wzorce odwzorowane z Terraform (PE + prywatne DNS, Workload
  Identity, Key Vault/CSI, least-privilege RBAC, backendy prywatne, granica `X-Scope-OrgID`).
- **Spójność:** identyczna treść logiczna i paleta w obu formatach.
- **Czytelność:** logiczne warstwy, legenda, brak chaosu połączeń.

## Na koniec zwróć

Ścieżki utworzonych plików, informację czy D2 udało się zrenderować, oraz zwięzłą notę: co w tym
diagramie wyszło lepiej w D2, a co w Excalidraw (do porównania przez użytkownika).
