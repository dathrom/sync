# 15 — Dyskusja o wyborze narzędzi (zapis rozmowy)

[◄ Alternatywy dla Grafany](14-alternatywy-dla-grafany-rbac.md) · [README](README.md) · [RBAC: OSS vs Enterprise ►](16-rbac-grafana-oss-vs-enterprise-organizacje.md)

> Zapis rozmowy, w której dochodziliśmy do docelowego stacku observability i modelu RBAC.
> Najpierw **podsumowanie z uzasadnieniem stacku**, potem **Q&A** (cytat pytania + odpowiedź).
> Szczegółowe analizy: dokumenty [08](08-self-hosted-grafana-analysis.md)–[14](14-alternatywy-dla-grafany-rbac.md).

---

## Podsumowanie — dlaczego taki stack

```
metryki → Prometheus → Mimir  → Grafana
logi    → Vector (Event Hub) → Loki  → Grafana
ślady   → OTel Collector     → Tempo → Grafana
```

Wspólny wzorzec dla każdego sygnału: **[źródło] → [kolektor] → [backend] → [Grafana]**. Backendy
(Mimir/Loki/Tempo) dzielą **ten sam model wielotenantowości** — nagłówek **`X-Scope-OrgID`** —
więc RBAC/izolacja jest jednym, spójnym modelem dla metryk, logów i śladów.

### Metryki: Prometheus → Mimir

- **Prometheus** zostaje jako **scraper/agent** (service discovery + pull + `remote_write`).
  Mimir **nie scrapuje**, więc kolektor jest potrzebny. Prometheus ustawia `X-Scope-OrgID` na
  `remote_write`, kierując metryki do właściwego tenanta.
- **Mimir** = wielotenantowy, skalowalny backend long-term (przejmuje storage + PromQL + ruler
  od Prometheusa). Wybrany zamiast **Thanos** (multi-tenancy to u niego dodatek, inny nagłówek)
  i **Cortex** (Mimir to jego ulepszony następca). Jedyny realny kontrargument: **licencja
  AGPLv3** (Cortex/Thanos są Apache 2.0) — do sprawdzenia z polityką organizacji.
- Zamiennik Azure Monitor/AMW: to wybór **self-hosted vs managed** dla backendu metryk. AMW nie
  wystawia Grafanie modelu `X-Scope-OrgID` — stąd dzisiejsza koncesja „metryki dla wszystkich".

### Logi: Vector (Event Hub) → Loki

- **Vector** czyta z **Azure Event Hub** i pcha do Loki. Wybrany, bo jest **mikro** (mały
  footprint) i ma dojrzałą ścieżkę Event Hub, a **do logów nie potrzeba pełnego Alloya**.
- **Loki** = wielotenantowy magazyn logów (`X-Scope-OrgID`). Uwaga: Loki **nie ma row/label
  security** w OSS — izolacja logów wymaga multi-org (OSS) albo LBAC/datasource-permissions
  (Enterprise). Patrz [dok. 13](13-loki-wplyw-na-self-hosted-i-izolacje.md).

### Ślady: OTel Collector → Tempo

- **OTel Collector** (nie Vector — Vector nie obsługuje śladów; nie Promtail — wycofany).
  Wybrany zamiast **Alloya**, bo jest **lżejszy** (zwłaszcza custom-build przez OCB), neutralny
  i przenośny. Robi **tail sampling** (decyzja o zachowaniu śladu — w kolektorze, nie w Tempo).
- **Tempo** = wielotenantowy magazyn śladów (`X-Scope-OrgID`, jak Loki/Mimir).

### Dlaczego wyspecjalizowane kolektory, a nie jeden Alloy

Alloy pokryłby **wszystkie trzy** sygnały jednym agentem (plus i minus w [Q15](#q15)). Wybór
wyspecjalizowanych (Prometheus/Vector/OTel) to **mniejszy footprint i najlepsze dopasowanie per
sygnał** (Vector-mikro do Event Huba, lekki OTel do śladów) — kosztem większej liczby typów
komponentów. **Alloy pozostaje alternatywą**, jeśli priorytetem jest „jeden agent do wszystkiego".

### Przekrojowo: RBAC / tenanci

- Kolektor **ustawia** `X-Scope-OrgID` na zapisie; backend **egzekwuje** go na odczycie; Grafana
  **przypina** nagłówek do data source'a w danej organizacji (user nie nadpisze).
- Sufit izolacji: **OSS = multi-org**; **per-team w jednej org = Enterprise** (datasource
  permissions / LBAC). Team sync i custom roles też są Enterprise. Patrz
  [dok. 11](11-granulacja-uprawnien-warianty.md), [dok. 13](13-loki-wplyw-na-self-hosted-i-izolacje.md).
- Decyzje otwarte dla zespołu: [pytania_do_zespołu.md](../pytania_do_zespołu.md).

---

## Q&A (przebieg rozmowy)

### Q1 — prompt do analizy self-hosted Grafany
> „napisz bardzo dokładny prompt, który przeanalizuje jak najlepiej … dodać do aks … self hosted grafana … [Helm? Kustomize?] … weź pod uwagę jak teraz jest wgrywany prometheus … uwspólnić."

Napisany szczegółowy prompt (Krok 0: przeczytaj realny stan; warianty metody; uwspólnienie z
Prometheusem; problemy techniczne; format wyjścia). Zapisany jako
[PROMPT-self-hosted-grafana-na-aks.md](PROMPT-self-hosted-grafana-na-aks.md).

### Q2 — uruchom prompt + uwzględnij istniejące docs
> „tak. uruchom go i niech weźmie pod uwagę inne dokumenty z …-docs"

Subagent wykonał analizę → [dok. 08](08-self-hosted-grafana-analysis.md). Rekomendacja: Helm
`grafana/grafana`, provisioning as-code, ten sam Helm co Prometheus, auth do AMW przez Workload
Identity, do in-cluster Prometheusa wprost.

### Q3 — RBAC i logowanie: lokalny admin czy Entra OAuth — czemu niedostępne?
> „najbardziej istotna jest kwestia rbac i Logowanie userów — lokalny admin (PoC) czy Entra OAuth <- czemu niedostępne?"

Entra OAuth „niedostępne", bo self-hosted Grafana wymaga **rejestracji aplikacji** w Entra ID, a
środowisko nie ma do tego uprawnień (ten sam blocker, który usunął SP w `identity.tf`). Managed
Grafana tego nie potrzebuje (jest first-party). **Twoje ustalenia:** mapowanie grup Entra na
role/foldery jest krytyczne → analiza wzorca z `managed_grafana_internal`; źródeł danych będzie
wiele (AKS/Azure/on-prem); app-registration „postaram się uzyskać"; wątek licencji → osobny
subagent. Efekt: [dok. 09](09-selfhosted-rbac-entra-model.md) (dwa blokery: app-reg + team sync
= Enterprise) i [dok. 10](10-grafana-licencje-koszty-oss-reconciler.md) (koszty + reconciler).

### Q4 — diagram porównujący granulację uprawnień
> „przeanalizuj i narysuj diagram porównujący możliwości granulacji uprawnień do folderów, dashboardów i datasource w różnych wariantach."

→ [dok. 11](11-granulacja-uprawnien-warianty.md). Kluczowa oś: **foldery/dashboardy** granularne
w każdym OSS; **izolacja query datasource** = tylko Enterprise (datasource permissions/LBAC) lub
multi-org. Diagramy: mapa granulacji (quadrant) i poziomy egzekwowania.

### Q5 — custom role, w czym dostępne?
> „a custom role? w czym są dostępne?"

**Custom roles i fixed roles = tylko Enterprise/Cloud.** OSS ma jedynie **basic roles**
(Viewer/Editor/Admin). To ta sama warstwa fine-grained RBAC co datasource permissions i team sync
— wszystko po stronie Enterprise.

### Q6 — jak działałby reconciler?
> „a jak właściwie działałby ten reconciller? jakie miałby funkcjonalności i jak by je realizował, za pomocą jakich mechanizmów wbudowanych w grafana / azure"

→ [dok. 12](12-reconciler-architektura-mechanizmy.md). Bezstanowy CronJob: **odczyt** z Microsoft
Graph (`/groups/{id}/transitiveMembers`) + **zapis** przez Grafana HTTP API (teamy, foldery,
uprawnienia). Gotowiec: `grafana-oss-team-sync`. Omija „group overage" (czyta z Graph, nie z
claimu tokenu). Nie zrobi izolacji datasource ani custom roles (to Enterprise).

### Q7 — jak Loki zmienia całość? Czy integruje każdy rodzaj DS?
> „przeanalizuj bardzo dokładnie jak to wszystko zmieniłoby wprowadzenie LOKI'ego? Czy każdy rodzaj DS loki mógłby zintegrować czy są jakieś rodzaje, których nie potrafi?"

→ [dok. 13](13-loki-wplyw-na-self-hosted-i-izolacje.md). Loki nie rusza folderów/teamów; ląduje na
osi datasource — izolacja logów = datasource permissions/LBAC (Enterprise) lub multi-org.
**Loki to jeden typ (logi)** — nie zastępuje metryk/śladów. Ingest przez Alloy/OTel/Fluent/Vector;
nie robi full-text search (indeksuje etykiety), nie metryki, nie ślady.

### Q8 — Loki nie bierze metryk/śladów? + co znaczy „przesądza Enterprise"?
> „czyli loki NIE potrafi jako DS brać metryk jak / z prometheus? ani trace? … 2. 'Loki praktycznie przesądza Enterprise/Cloud (LBAC)' co masz na myśli? w sensie 'wymusza'?"

Potwierdzone: Loki jako DS obsługuje **tylko logi**. Nie bierze metryk z Prometheusa (choć LogQL
liczy metryki **z logów**), nie przechowuje śladów (ma tylko **derived fields** = link do Tempo).
„Przesądza Enterprise" to skrót myślowy — poprawnie: **warunkowo wymusza**, tylko gdy naraz: (1)
logi muszą być izolowane per tenant, (2) w jednej instancji OSS, (3) bez akceptacji multi-org.
Wtedy zostaje Enterprise/LBAC. Bez tych warunków OSS wystarcza.

### Q9 — alternatywy dla Grafany z granularniejszym RBAC?
> „czy są alternatywy dla grafana, które pozwalają na lepsze, granularniejsze zarządzanie uprawnieniami?"

→ [dok. 14](14-alternatywy-dla-grafany-rbac.md). **Perses** (CNCF, RBAC per projekt, młody),
**OpenSearch Dashboards** (fine-grained za darmo, ale store = OpenSearch, nie PromQL), **Superset**
(RBAC+RLS, ale BI/SQL). Żadna to drop-in. Częściej lepiej rozwiązać architekturą (**instancje OSS
per tenant / multi-org**) niż wymianą narzędzia.

### Q10 — sprawdź transkrypcję: czy pada, że Loki nie zastąpi Prometheusa?
> „sprawdź czy w transkrybcji … jest w kontekście lokiego info, że on nie zastąpi prometheus … wydaje mi się, że … loki po prostu mógł dać warstwę RBAC, ale bez zaznaczenia, że … nie zapewni jej dla metryk czy trace'ów"

Nie ma wprost „Loki nie zastąpi Prometheusa". RBAC opisany na spotkaniu to **multi-org +
`X-Scope-OrgID` całego stosu** (loki/mimir/tempo — [transkrybcja:625](../transkrybcja#L625)), nie
„funkcja Lokiego". Metryki: ograniczenie **zaznaczono** ([transkrybcja:1281](../transkrybcja#L1281))
jako koncesję „widoczne dla wszystkich" ([1302](../transkrybcja#L1302)). Ślady: Tempo **pada** w
transkrypcji jako element stosu i w kontekście korelacji log↔trace
([transkrybcja:625](../transkrybcja#L625), [699](../transkrybcja#L699),
[705](../transkrybcja#L705)), **ale ich izolacja/RBAC per tenant nie była omawiana** — więc Twoje
przeczucie o luce jest trafne: brak dotyczy właśnie **modelu dostępu do śladów**, nie samego
istnienia Tempo w stacku.

### Q11 — co dałby Mimir w kontekście RBAC?
> „co by dał mimr w tym systemie w kontekście rbac?"

Mimir **nie dodaje nowej zdolności RBAC** — **rozszerza ten sam model multi-tenant (`X-Scope-OrgID`)
na metryki**, więc metryki przestają być wyjątkiem „widoczne dla wszystkich" i wchodzą w model
logów. Zamyka koncesję z transkrypcji, daje per-tenant ruler i long-term. **Sufit ten sam co Loki**:
OSS → multi-org; per-team w jednej org → Enterprise (datasource permissions/LBAC dla metryk).

### Q12 — Mimir vs Thanos/Cortex?
> „w czym mimir byłby lepszy od tabos / cortex? a może lepiej użyć któreś z nich?"

**Mimir**: multi-tenancy pierwszoklasowa (`X-Scope-OrgID`, jak Loki), aktywny rozwój, integracja
LGTM; licencja **AGPLv3**. **Cortex**: ten sam model, Apache 2.0, mniejszy pęd — bierz przy
polityce „no AGPL". **Thanos**: model sidecar nad istniejącym Prometheusem, multi-tenancy to
dodatek (inny nagłówek) — bierz, gdy masz flotę Prometheusów i nie potrzebujesz twardej izolacji.
Dla naszego celu (izolacja per tenant + spójność z Loki) → **Mimir**.

### Q13 — czy Mimir może zastąpić Prometheusa?
> „a czy mimir może zastąpić prometheus'a?"

Częściowo. **Zastępuje** storage + query + ruler (backend). **Nie zastępuje scrape'owania** —
Mimir przyjmuje dane tylko przez `remote_write`. Nadal potrzebny **scraper** (Prometheus-agent /
Alloy). Monolityczny Prometheus rozpada się: scrape zostaje, storage+query idą do Mimira.

### Q14 — konsolidacja stacku (korekta)
> „czyli ostatecznie … stack: metryki → Prometheus → mimir → grafana; logi → loki → grafana"

Korekta: **logi też potrzebują kolektora** przed Loki (Loki nie zbiera sam). Symetrycznie:
`logi → Vector/Alloy/OTel → Loki`. Poprawny model: **[źródło] → [kolektor] → [backend] → [Grafana]**
dla każdego sygnału.

### Q15 — wady/zalety Alloya {#q15}
> „jakie byłyby wady i jakie zalety użycia Alloy"

**Zalety**: jeden agent na metryki+logi+ślady, Grafana-native, OTel-native, następca (Agent EOL,
Promtail wycofany), `X-Scope-OrgID` ready, Apache 2.0. **Wady**: cięższy niż wyspecjalizowane
(„Vector jest mikro, Alloy to duża koza" — [transkrybcja:1370](../transkrybcja#L1370)); niszowe
źródła (Event Hub) dojrzalsze na Vectorze; nowość + własny język konfiguracji; „wszystko w jednym"
= wspólny punkt zmian. Model mieszany (Alloy/Prometheus metryki, Vector logi) jest OK.

### Q16 — gdzie tworzone „organizacje"? miejsce dla Prometheusa? czy daje nagłówek?
> „te organizacje gdzie będą tworzone? … czy w tym stacku jest miejsce dla prometheus? … czy on potrafi dać taki nagłówek do grafana?"

**Organizacje** zakłada się **w Grafanie**; w Loki/Mimir nie ma „org do zakładania" — są **tenanci
= wartości `X-Scope-OrgID`**. **Prometheus** ma miejsce jako **scraper/forwarder** zasilający
Mimira. **Nagłówek**: na **zapisie** Prometheus potrafi ustawić `X-Scope-OrgID` (`remote_write`) →
kieruje dane do tenanta; na **odczycie** zwykły Prometheus jest single-tenant i **nie** daje
izolacji nagłówkiem — to rola Mimira.

### Q17 — ślady: Alloy czy OTel, czy coś innego?
> „co ze śladami? alloy czy otel? a może coś innego?"

Realny wybór to **OTel Collector vs Alloy** (ten sam silnik). **Vector odpada** (nie obsługuje
śladów), Promtail/Jaeger-agent legacy. Oba: OTLP/Jaeger/Zipkin/Kafka, **tail sampling**, eksport do
Tempo z `X-Scope-OrgID`. Alloy = jeden agent do wszystkiego; OTel = neutralny/portowalny standard.

### Q18 — czy Tempo też ustawia X-Scope-OrgID?
> „czy tempo też ustawia x-scope-org?"

**Tak** — identycznie jak Loki/Mimir (`multitenancy_enabled: true`, `X-Scope-OrgID` na zapisie i
odczycie). Cała trójka LGTM dzieli jeden model tenantów. Zastrzeżenie: backend ufa temu, kto
ustawia nagłówek → musi go wstrzykiwać zaufana warstwa (data source w org / brama), nie klient.

### Q19 — który kolektor lżejszy?
> „który jest 'lżejszy'?"

Między Alloyem a OTel — **lżejszy jest OTel Collector** (Alloy opakowuje OTel i dokłada narzut +
bundluje wszystko). Najlżejszy jest **custom-build OTela (OCB)** tylko z potrzebnymi komponentami.
Ranking (dla śladów): `custom OTel < otel-contrib ≈ Alloy`. Ogólnie najlżejszy jest **Vector**, ale
tylko do logów/metryk. Uwaga: przy śladach i tak dominuje pamięć na **tail sampling**, nie sam binarny.

---

## Źródła

Zebrane w dokumentach źródłowych: [08](08-self-hosted-grafana-analysis.md)–[14](14-alternatywy-dla-grafany-rbac.md)
(cenniki, licencje, multi-tenancy, LBAC, kolektory) oraz materiały ze spotkania
([transkrybcja](../transkrybcja), [jak_loki_zmienilby_drzewo_RBAC.md](../jak_loki_zmienilby_drzewo_RBAC.md)).
