# Research: potwierdzenie źródłowe ograniczeń narzędzi wskazanych na spotkaniu

> **Cel:** skonfrontować „rzekome ograniczenia" narzędzi (Azure Managed Grafana,
> Managed Prometheus / Azure Monitor, Loki, Event Hub, Vector, self-hosted Grafana)
> wyartykułowane na spotkaniu — z autorytatywną dokumentacją.
> **Data weryfikacji:** 2026-07-10. Dokumentacja pobrana na żywo (Microsoft Learn,
> Grafana Labs, vector.dev; wersje z lutego–czerwca 2026).
> **Metoda:** cztery niezależne wątki researchowe, każdy z werdyktem
> POTWIERDZONE / CZĘŚCIOWO / OBALONE / BRAK JEDNOZNACZNYCH ŹRÓDEŁ + URL.
> **Powiązane:** [analiza_loki_zmiany_w_poc.md](analiza_loki_zmiany_w_poc.md),
> [podsumowanie_spotkania.md](podsumowanie_spotkania.md).

---

## Tabela zbiorcza

| # | Twierdzenie ze spotkania | Werdykt |
|---|---------------------------|---------|
| **AZURE — Grafana / Prometheus / Monitor / Event Hub** | | |
| 1 | Regionalna prywatna strefa DNS AMW współdzielona per region → private endpoint psuje pozostałe instancje; „wszystko private albo public" | **POTWIERDZONE** (mechanizm), CZĘŚCIOWO (framing) |
| 2 | Azure Monitor DS: *Current user* = RBAC per user, alerty nie działają; *MI/SP* = alerty działają, brak granularności | **POTWIERDZONE** |
| 3 | Azure Managed Grafana nie ma natywnego SMTP → potrzebny webhook → Logic App | **OBALONE (nieaktualne)** |
| 4 | Managed Grafana wyłącza service accounts → provider Terraform nie może się uwierzytelnić | **OBALONE co do sedna** |
| 5 | Grafana Cloud nie ma organizacji / multi-tenancy | **POTWIERDZONE** (z niuansem) |
| 6 | Event Hub: TU 1–40, auto-inflate skaluje w górę, nie w dół | **POTWIERDZONE** |
| 7 | Diagnostic settings → Event Hub; taniej niż Log Analytics przy długiej retencji | **CZĘŚCIOWO** (destynacja tak; teza kosztowa myląca) |
| **LOKI** | | |
| 8 | Multi-tenancy przez nagłówek `X-Scope-OrgID`, `auth_enabled` | **POTWIERDZONE** |
| 9 | Brak row/index-level security jak w Elasticsearch | **CZĘŚCIOWO** (brak ES-owego field/doc-level = prawda; istnieje LBAC label-level) |
| 10 | Brak full-text search; `message` nieindeksowane, indeks tylko po labelach | **POTWIERDZONE** |
| 11 | Loki ruler działa „w ingestion time", skaluje się lepiej niż Grafana cron | **CZĘŚCIOWO** — skalowanie tak; **„ingestion time" OBALONE** |
| **VECTOR / AGENCI** | | |
| 12 | Vector czyta z Event Huba przez protokół Kafka/AMQP (brak natywnego source EH) | **POTWIERDZONE** |
| 13 | Vector nie ma inputu Windows Event Log → do Windows trzeba Alloy/OTel | **OBALONE** |
| **SELF-HOSTED GRAFANA** | | |
| 14 | Grafana auto-wstrzykuje nienadpisywalny `X-Scope-OrgID` per organizacja użytkownika | **OBALONE** (w kluczowej części) |
| 15 | Domyślnie SQLite; HA / duża skala wymaga PostgreSQL/MySQL | **POTWIERDZONE** |
| 16 | Data-source-managed alert rules dla Mimir/Loki (ruler); nie dla Thanos | **POTWIERDZONE** (Prometheus tylko odczyt; Thanos = brak na liście) |

---

## Co się potwierdziło (twarde fakty)

**Konflikt prywatnego DNS AMW (#1).** Udokumentowany jako *Known issue*. Strefa
`privatelink.<region>.prometheus.monitor.azure.com` jest regionalna; gdy workspace
w danym regionie dostaje private endpoint, klienci w VNecie z podpiętą strefą muszą
odtąd sięgać przez PE do **każdego** workspace'a w regionie, który też ma PE.
Doprecyzowanie: efekt nie jest „globalny i automatyczny", tylko ograniczony do
VNetów z podpiętą strefą. Dla zapytań z Managed Grafany MS zaleca **Managed Private
Endpoint** (nie zwykły PE) — co POC już realizuje.

**Current user vs alerty (#2).** Dosłownie w docs: *„Current User authentication
doesn't support background operations like alerting, reporting, and recording
rules"*, bo działają bez kontekstu użytkownika. Obejście: **fallback service
credentials** — ten sam trade-off (alerty działają, ale w uprawnieniach SP, nie
usera). Potwierdza konflikt widoczny w `configure-grafana.sh:47`.

**Event Hub TU / auto-inflate (#6).** Cytat: *„Auto inflate doesn't automatically
scale down the number of TUs when ingress or egress rates drop"*. TU 1–40;
auto-inflate **tylko w tier Standard** (Basic nie ma).

**Vector ↔ Event Hub przez Kafka (#12).** Event Hub wystawia endpoint zgodny z
Apache Kafka (tier **Standard+**, Basic nie), Vector ma source `kafka`, brak
dedykowanego source „Azure Event Hub". Uwaga: source `amqp` Vectora to AMQP **0.9.1**
(RabbitMQ), a Event Hub mówi AMQP **1.0** — realną ścieżką jest `kafka`, nie `amqp`.

**Loki: multi-tenancy, brak full-text, SQLite→Postgres, ruler dla Mimir/Loki
(#8, #10, #15, #16).** Potwierdzone dokumentacją Grafany. Loki indeksuje tylko
labele, treść skanuje brute-force (niuans: Loki 3.x ma bloom filters przyspieszające
skan — sprawdzić bieżący stan). Grafana HA wymaga współdzielonego Postgres/MySQL.
Data-source-managed rules: tworzenie **tylko Mimir/Loki**, Prometheus read-only,
Thanos poza listą.

**Grafana Cloud bez multi-org (#5).** Brak wielu organizacji w jednym stacku;
multi-tenancy osiąga się przez Teams/RBAC/Folders/LBAC lub wiele stacków. Wahanie
eksperta na spotkaniu słuszne — obszar aktywnie rozwijany.

---

## Co wymaga korekty (błędy / nieaktualności ze spotkania)

**❌ #13 — Vector JEDNAK zbiera Windows Event Log.** Vector ma natywny source
`windows_event_log` (status beta). Teza „do Windows trzeba Alloy/OTel, bo Vector nie
zbierze" jest **fałszywa**. Prawdą pozostaje, że Vector nie ma runtime'owego systemu
pluginów (monolit z wkompilowanymi funkcjami), ale to nie przekłada się na brak
Windows Event Log. (Alloy: `loki.source.windowsevent`; OTel: `windroweventlogreceiver`
w dystrybucji Contrib.)

**❌ #14 — Brak automatycznego wstrzykiwania `X-Scope-OrgID` per org.** Najważniejsza
korekta. Grafana **nie** mapuje automatycznie organizacji zalogowanego użytkownika na
tenant Loki. Jest tylko **statyczny custom HTTP header per data source** (admin wpisuje
wartość ręcznie; user jej nie nadpisze w UI zapytania — i tylko w tym sensie
„nienadpisywalny"). Dynamiczna propagacja org→tenant to otwarty feature request
(grafana/grafana#87364). Koryguje interpretację transkrybcji:625 i model
multi-tenancy — izolację buduje się **ręcznie** (osobny DS per org + zaszyty tenant),
a nie automatyką.

**❌ #11 — „Ingestion time" to błąd.** Loki/Mimir ruler **nie** ewaluuje reguł przy
zapisie. Ewaluuje je **okresowo** (interwał rule group, np. 1 min), po stronie data
source. Różnica względem Grafana-managed to *miejsce* ewaluacji (data source vs
Grafana) i **skalowanie horyzontalne przez hash ring**, a nie „ciągła vs cykliczna".
Konkretne liczby („dziesiątki tysięcy reguł") i „duplikacja przy HA" — kierunkowo
słuszne, ale bez jednoznacznego cytatu. Grafana oficjalnie **rekomenduje
Grafana-managed „whenever possible"**; data-source-managed wybiera się dla skali.

**❌ #3 — Managed Grafana MA natywny SMTP.** Konfigurowalny w Portalu /
`az grafana update --smtp` (wymaga planu **Standard**, tylko na istniejącym
workspace). Nadal potrzebny zewnętrzny serwer SMTP/relay (np. SendGrid; Exchange
Online odpada — brak Basic Auth), ale **webhook → Logic App nie jest konieczny**.
Łagodzi „lukę" wskazaną wcześniej w recenzji Kroku 3.

**❌ #4 — Managed Grafana wspiera service accounts.** Są tylko **domyślnie
wyłączone**; po włączeniu (`az grafana update --service-account Enabled`) provider
Terraform Grafany działa z tokenem SA. Komentarz w `configure-grafana.sh:14-15`
(„Managed Grafana disables service accounts") jest nieprecyzyjny — to kwestia
jednorazowego włączenia, nie stałe ograniczenie.

**⚠️ #7 — Teza kosztowa myląca.** Event Hub to **transport/bufor** (retencja
standardowo max 7 dni), nie magazyn retencyjny — jako tanią długą retencję MS
wskazuje **Storage account**, nie Event Hub. Oszczędność w ścieżce
`→ Event Hub → Vector → Loki` bierze się z tego, że **Loki na tanim object storage
zastępuje płatny ingest Log Analytics**, a nie z samego Event Huba. Intencja (unik
kosztów Log Analytics) słuszna, sformułowanie „Event Hub tańszy przy retencji" —
nieścisłe.

**⚠️ #9 — Istnieje LBAC.** „Brak ES-owego field/document-level security" — prawda.
Ale „izolacja **tylko** na poziomie tenanta" za mocne: Grafana Enterprise/Cloud ma
**Label-Based Access Control** (uprawnienia po selektorach etykiet, poniżej granicy
tenanta). To nie ekwiwalent ES (działa na etykietach strumieni, nie na dowolnych
polach/wierszach treści), ale daje granularność finszą niż tenant.

---

## Wnioski

1. **Rdzeń rekomendacji spotkania trzyma się faktów** — konflikt DNS AMW,
   current-user vs alerty, model indeksowania Loki, Event Hub auto-inflate,
   SQLite→Postgres, ruler dla skali: potwierdzone.
2. **Cztery tezy przestarzałe/błędne** do sprostowania w decyzjach: Vector *umie*
   Windows Event Log; Managed Grafana *ma* SMTP i service accounts; „ingestion time"
   rulera to nieporozumienie. Część to efekt dojrzewania funkcji Azure po sesji.
3. **Największa korekta modelowa:** `X-Scope-OrgID` nie jest automatyczny —
   multi-tenancy „organizacja = system" wymaga ręcznej konfiguracji DS per tenant
   (realny nakład, do wyceny).
4. **„Luka" dostarczania alertów mniejsza** — natywny SMTP w Managed Grafana
   (Standard) wystarcza, Logic App niekonieczny.

---

## Źródła

**Azure**
- Private Link dla Azure Monitor Workspace / Managed Prometheus (Known issues, DNS):
  https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/private-link-azure-monitor-workspace
- Kubernetes monitoring private link:
  https://learn.microsoft.com/en-us/azure/azure-monitor/containers/kubernetes-monitoring-private-link
- Event Hubs scalability (TU 1–40):
  https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-scalability
- Event Hubs auto-inflate (brak scale-down):
  https://learn.microsoft.com/en-us/azure/event-hubs/event-hubs-auto-inflate
- Diagnostic settings (destynacje):
  https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/diagnostic-settings
- Event Hubs Kafka overview:
  https://learn.microsoft.com/en-us/azure/event-hubs/azure-event-hubs-kafka-overview
- Managed Grafana SMTP:
  https://learn.microsoft.com/en-us/azure/managed-grafana/how-to-smtp-settings
- Managed Grafana service accounts:
  https://learn.microsoft.com/en-us/azure/managed-grafana/how-to-service-accounts
- Managed Grafana data-plane auth (Entra ID):
  https://learn.microsoft.com/en-us/azure/managed-grafana/how-to-authenticate-data-plane-api

**Grafana / Loki**
- Azure Monitor data source — alerting (current user limitation):
  https://grafana.com/docs/grafana/latest/datasources/azure-monitor/alerting/
- Current user authentication (what's new):
  https://grafana.com/whats-new/2024-03-22-azure-monitor-current-user-authentication/
- Loki multi-tenancy (X-Scope-OrgID, auth_enabled):
  https://grafana.com/docs/loki/latest/operations/multi-tenancy/
- Loki labels / indexing model:
  https://grafana.com/docs/loki/latest/get-started/labels/
- LogQL log queries:
  https://grafana.com/docs/loki/latest/query/log_queries/
- Loki alerting / ruler:
  https://grafana.com/docs/loki/latest/alert/
- Loki recording rules:
  https://grafana.com/docs/loki/latest/operations/recording-rules/
- Team LBAC:
  https://grafana.com/docs/grafana/latest/administration/data-source-management/teamlbac/
- Data source-managed alert rules:
  https://grafana.com/docs/grafana/latest/alerting/alerting-rules/create-data-source-managed-rule/
- Grafana HA (shared DB, SQLite default):
  https://grafana.com/docs/grafana/latest/setup-grafana/set-up-for-high-availability/
- Loki data source — custom HTTP headers (X-Scope-OrgID):
  https://grafana.com/docs/grafana/latest/datasources/loki/configure-loki-data-source/
- Feature request: propagate headers / dynamic tenant (grafana#87364):
  https://github.com/grafana/grafana/issues/87364
- Grafana Cloud stack architecture / multi-tenancy guidance:
  https://grafana.com/docs/grafana-cloud/security-and-account-management/cloud-stacks/stack-architecture-guidance/
- Multi-org feature request (grafana#24588):
  https://github.com/grafana/grafana/issues/24588

**Vector / agenci**
- Vector sources (lista; brak dedykowanego Event Hub):
  https://vector.dev/docs/reference/configuration/sources/
- Vector `windows_event_log` source:
  https://vector.dev/docs/reference/configuration/sources/windows_event_log/
- Grafana Alloy `loki.source.windowsevent`:
  https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.windowsevent/
- OpenTelemetry Collector `windowseventlogreceiver`:
  https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/receiver/windowseventlogreceiver/README.md
