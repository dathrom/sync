# Pytania do zespołu — projektowanie observability (Grafana + logi/metryki/ślady, RBAC)

> Cel: zebrać decyzje, które przesądzają architekturę, **zanim** zaczniemy implementować.
> Odpowiedzi wpisujcie pod pytaniami. Odniesienia do analiz: katalog
> [`grafana-poc-example-docs/`](grafana-poc-example-docs/) (dok. 08–14) oraz materiały ze
> spotkania ([`transkrybcja`](transkrybcja), [`jak_loki_zmienilby_drzewo_RBAC.md`](jak_loki_zmienilby_drzewo_RBAC.md)).

---

## 0. Trzy pytania, które przesądzają WSZYSTKO

Od tych trzech odpowiedzi zależy cała reszta (OSS vs Enterprise, multi-org, koszty):

1. **Czy LOGI muszą być izolowane per system/tenant** (zespół A nie widzi logów zespołu B)?
   - → TAK = potrzebne datasource permissions/LBAC (**Enterprise/Cloud**) **lub** multi-org (OSS).
   - → NIE = wystarczy Grafana OSS (+ reconciler dla folderów). Patrz [dok. 11](grafana-poc-example-docs/11-granulacja-uprawnien-warianty.md), [dok. 13](grafana-poc-example-docs/13-loki-wplyw-na-self-hosted-i-izolacje.md).
2. **Czy „self-hosted" to twardy wymóg**, czy w grze jest Grafana Cloud / pozostanie na Azure Managed Grafana?
   - → Cloud łamie „self-hosted"; Azure Managed Grafana daje team sync/LBAC „w cenie". Patrz [dok. 10](grafana-poc-example-docs/10-grafana-licencje-koszty-oss-reconciler.md).
3. **Ile realnie użytkowników (aktywnych) i ile systemów/RA?**
   - → Przesądza próg opłacalności (OSS+reconciler vs Azure Managed ~70–140 userów) i czy multi-org jest w ogóle wykonalny. Patrz [dok. 10](grafana-poc-example-docs/10-grafana-licencje-koszty-oss-reconciler.md), [dok. 11](grafana-poc-example-docs/11-granulacja-uprawnien-warianty.md).

---

## 1. Wymagania izolacji i bezpieczeństwa danych

4. **Metryki** — czy muszą być izolowane per system/tenant, czy koncesja „metryki widoczne dla
   wszystkich" jest OK? (Na spotkaniu przyjęto koncesję — [transkrybcja:1302](transkrybcja#L1302); z Azure Monitorem nie ma izolacji per team — [transkrybcja:1281](transkrybcja#L1281).)
5. **Ślady (traces / Tempo)** — czy będą w zakresie i czy wymagają izolacji per team? (Na
   spotkaniu **nieomówione** — luka do domknięcia.)
6. **Wrażliwość logów** — czy logi zawierają PII / tokeny / dane różnych klientów? Jaki poziom
   rozdziału jest wymagany (per system? per środowisko DEV/UAT/PROD? per linia logu)?
7. **Compliance / audyt** — czy są wymogi regulacyjne rozdziału danych lub audytu, kto co
   odczytał? (Jeśli tak — de facto wymusza Enterprise/LBAC.)
8. **Granica izolacji** — na jakim poziomie ma przebiegać „security boundary": `(ra, system)`,
   `(ra, system, environment)`, czy inny? (Determinuje liczbę tenantów/data source'ów.)

## 2. Tożsamość i logowanie (Entra ID)

9. **App registration** — czy admin tenanta utworzy rejestrację aplikacji dla self-hosted
   Grafany (logowanie OAuth + claim grup)? Jaki status/termin? (Blocker — [dok. 09](grafana-poc-example-docs/09-selfhosted-rbac-entra-model.md).)
10. **Group overage** — czy użytkownicy należą do > ~200 grup? (Jeśli tak, app-reg potrzebuje
    uprawnień Microsoft Graph do dobierania grup — [dok. 09 §3](grafana-poc-example-docs/09-selfhosted-rbac-entra-model.md).)
11. **Model mapowania** — zostajemy przy modelu z [`rbac_input.csv`](jak_loki_zmienilby_drzewo_RBAC.md)
    (`ra / system / environment / grupa / access_level`)? Czy grupy Entra są już poukładane pod ten model?
12. **Kto administruje** Grafaną (rola Admin) i kto zarządza modelem dostępu (właściciel CSV)?

## 3. Licencja i budżet

13. **Apetyt na Grafana Enterprise / Cloud** — czy jest budżet, jeśli izolacja per tenant tego
    wymaga? (Enterprise self-managed = „contact sales"; Cloud = per aktywny user — [dok. 10](grafana-poc-example-docs/10-grafana-licencje-koszty-oss-reconciler.md).)
14. **Jeśli OSS** — akceptujecie utrzymanie **własnego reconcilera** (adaptacja
    `grafana-oss-team-sync`) albo **multi-org** ze świadomością kosztu operacyjnego? (Patrz
    [dok. 12](grafana-poc-example-docs/12-reconciler-architektura-mechanizmy.md).)
15. **Punkt odniesienia** — czy pozostanie na **Azure Managed Grafanie** (team sync/LBAC w
    cenie, per-user 72 USD/rok) jest rozważane zamiast self-hosted?

## 4. Stos danych — co, gdzie, jak długo

16. **Kierunek stosu** — przechodzimy na self-hosted **LGTM** (Loki + Mimir + Tempo), czy
    hybrydowo (logi → Loki, metryki zostają w **Azure Monitor / AMW**)?
17. **Metryki** — Azure Monitor/AMW (90 dni, brak izolacji per team) czy **Mimir** (long-term,
    izolacja per tenant tym samym modelem co Loki, per-tenant ruler)? (Mimir a RBAC — patrz notatka niżej / dok. 13.)
18. **Logi** — Loki potwierdzone? Jaki **kolektor**: Grafana **Alloy**, **OTel Collector** czy
    **Vector** czytający z **Event Hub**? (Promtail wycofany — [dok. 13 §4.2](grafana-poc-example-docs/13-loki-wplyw-na-self-hosted-i-izolacje.md).)
19. **Retencja** — jak długo trzymamy metryki i logi? (Przesądza sens Mimira/Loki long-term vs Azure.)
20. **Struktura logów** — czy aplikacje logują **strukturalnie (JSON)**? (Warunek sensownych
    alertów na treść — [transkrybcja:1530](transkrybcja#L1530), [jak_loki §6](jak_loki_zmienilby_drzewo_RBAC.md).)
21. **Własność infrastruktury** Loki/Mimir/Tempo (storage obiektowy, Event Hub, Vector, ruler) —
    kto ją posiada i utrzymuje? To inny state/zespół niż konfiguracja Grafany. (jak_loki §7.)

## 5. Alerty

22. **Gdzie alerty** — Azure Monitor, Grafana-managed, czy **ruler** (Loki/Mimir) na ingest?
    ([transkrybcja:1321](transkrybcja#L1321), [1399](transkrybcja#L1399).)
23. **Skala alertów** — dziesiątki czy setki reguł? (Grafana-managed słabo skaluje się przy
    setkach — [transkrybcja:609](transkrybcja#L609).)
24. **Alerty na metrykach vs logach** — które są priorytetem i na jakim backendzie mają żyć?

## 6. Wdrożenie i operacje (jeśli self-hosted)

25. **Metoda instalacji** — Helm (rekomendacja) i uwspólnienie z Prometheusem: zostać przy
    skrypcie `deploy-k8s.sh` czy migrować na `helm_release` w Terraform? ([dok. 08 §3](grafana-poc-example-docs/08-self-hosted-grafana-analysis.md).)
26. **Workload Identity** — zgoda na włączenie `oidc_issuer`/`workload_identity` na istniejącym
    AKS (auth Grafany do AMW/Mimir bez sekretów)? ([dok. 08 §4.1](grafana-poc-example-docs/08-self-hosted-grafana-analysis.md).)
27. **Ekspozycja UI** — ClusterIP + port-forward (PoC), wewnętrzny LB czy Ingress?
28. **Reconciler (jeśli OSS)** — auth do Grafany: token service-account (bez tworzenia userów,
    JIT z OAuth) czy basic auth (pełny sync userów, sekret w Key Vault)? Auth do Graph: Workload
    Identity czy `CLIENT_SECRET` w Key Vault? ([dok. 12 §4](grafana-poc-example-docs/12-reconciler-architektura-mechanizmy.md).)
29. **Trwałość/HA** — 1 replika bez PVC (PoC) czy HA z zewnętrzną bazą (Postgres)?

## 7. Dashboardy i ewentualna zmiana narzędzia

30. **Dashboardy „dokładna kopia"** — eksportujemy z żywej managed Grafany do repo i
    provisionujemy as-code? Kto jest właścicielem obecnych dashboardów? ([dok. 08 §4.2](grafana-poc-example-docs/08-self-hosted-grafana-analysis.md).)
31. **Zmiana narzędzia** — czy w ogóle rozważamy alternatywy dla Grafany dla granularniejszego
    RBAC (**Perses** / **OpenSearch**), czy zostajemy na Grafanie i rozwiązujemy RBAC
    architekturą/licencją? ([dok. 14](grafana-poc-example-docs/14-alternatywy-dla-grafany-rbac.md).)

---

## Mapa: jak odpowiedzi przekładają się na wariant

- **Logi bez izolacji** → Grafana OSS + reconciler (foldery). Tanio, skaluje się.
- **Logi z izolacją, budżet na licencję** → Enterprise/Cloud (LBAC — jeden data source,
  reguły etykietowe per team). Najczystsze.
- **Logi z izolacją, bez budżetu** → OSS **multi-org** (org per system) — działa, ale ciężkie
  przy wielu systemach.
- **Metryki mają być izolowane jak logi** → dołóż **Mimir** (ten sam model tenant-header);
  inaczej zostają w Azure Monitorze jako „widoczne dla wszystkich".
- **Granularny RBAC to cel nadrzędny, gotowi na migrację** → rozważ **Perses**.

> Notatka „Mimir a RBAC": Mimir nie daje nowej zdolności RBAC — **przenosi metryki w ten sam
> model multi-tenant co Loki** (`X-Scope-OrgID`), zamykając koncesję „metryki dla wszystkich".
> Dziedziczy ten sam sufit: w OSS izolacja per team tylko przez multi-org; per-team w jednej
> org = Enterprise (datasource permissions / LBAC dla metryk).
