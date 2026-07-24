# 14 — Alternatywy dla Grafany z granularniejszym RBAC (OSS)

[◄ Loki: wpływ na self-hosted](13-loki-wplyw-na-self-hosted-i-izolacje.md) · [README](README.md) · [Dyskusja o wyborze narzędzi ►](15-dyskusja-ze-mna-na-temat-wyboru-narzedzi.md)

> Dokument analityczny. Odpowiada: **czy są narzędzia, które w wersji open-source dają
> drobniejsze zarządzanie uprawnieniami** niż Grafana OSS (gdzie datasource permissions / LBAC /
> custom roles są Enterprise — [11](11-granulacja-uprawnien-warianty.md),
> [13](13-loki-wplyw-na-self-hosted-i-izolacje.md)). Ważne zastrzeżenie: zmiana narzędzia
> wymienia jeden problem (licencja) na wiele innych (ekosystem, migracja, dojrzałość). Fakty
> zweryfikowane w dokumentacji projektów (dostęp 2026-07-21).

---

## 0. TL;DR

- **Tak — istnieją narzędzia z drobniejszym RBAC „za darmo"**, ale **żadne nie jest drop-in
  zamiennikiem Grafany**: albo są młodsze i uboższe (Perses), albo związane z konkretnym
  backendem danych (OpenSearch → logi/search), albo to BI, nie observability (Superset).
- **Zanim wymienisz narzędzie, rozważ architekturę:** wielotenantowość często taniej rozwiązać
  **osobnymi instancjami Grafany OSS per system/tenant** (naturalna izolacja, za darmo, zostajesz
  na Grafanie) niż przepisywaniem wszystkiego na inny stack (§3).
- Jeśli mimo to szukasz *narzędzia* z natywnym granularnym RBAC w OSS i profilem „jak Grafana":
  najbliżej jest **Perses (CNCF)** — z zastrzeżeniem dojrzałości.

---

## 1. Kandydaci — model uprawnień w OSS

| Narzędzie | Granularność RBAC (OSS) | Model danych / profil | Dojrzałość i haczyki |
|---|---|---|---|
| **Perses** (CNCF Sandbox, Apache 2.0) | **RBAC inspirowane Kubernetesem**: role, role bindings, uprawnienia per **projekt** i globalnie; dashboardy w namespace'ach K8s | Observability „jak Grafana": Prometheus, Loki, Tempo, Pyroscope; GitOps / dashboard-as-code | **Młody** (CNCF od 08.2024, sandbox); mniej paneli/wtyczek, mniejszy ekosystem, wsparcie Loki/logów słabsze niż Grafana; brak parytetu funkcji |
| **OpenSearch Dashboards** (Apache 2.0) | **Fine-grained access control za darmo**: role na poziomie klastra/indeksu/**dokumentu/pola** + **tenants** (prywatne dashboardy zespołów) | Logi / full-text search na OpenSearch | RBAC bardzo drobny, ale **przywiązany do OpenSearch** jako store; **nie PromQL** (metryki przez konektory, słabiej); ciężki; inny język zapytań |
| **Apache Superset** (Apache 2.0) | **Dojrzały RBAC (Flask AppBuilder)** + **Row-Level Security** per rola (WHERE wstrzykiwane wg atrybutów usera); uprawnienia model/datasource/database | **BI/analityka na SQL**, nie observability | Brak natywnego PromQL/LogQL i UX obserwowalności; dane muszą być dostępne po SQL; nie zastąpi dashboardów metryk/logów |
| **Zabbix** (GPL) | Natywne uprawnienia per **grupa hostów / grupa userów** w OSS | Pełny system monitoringu (własna zbiórka) | Inny paradygmat — nie warstwa dashboardów nad Prometheus/Loki; migracja = zmiana całego modelu monitoringu |
| **SigNoz** (OSS, OTel-native) | RBAC głównie **rolowy (admin/editor/viewer)**, org-level | Metryki/logi/ślady na ClickHouse, OTLP | RBAC **nie drobniejszy** niż Grafana OSS w praktyce — nie rozwiązuje problemu izolacji per tenant |

---

## 2. Który do czego

- **Chcesz zostać w świecie „Grafana-like" (Prometheus/Loki/Tempo), K8s/GitOps, z natywnym
  granularnym RBAC bez licencji** → **Perses**. Najbliższy ideału koncepcyjnie (RBAC per projekt
  ≈ per system/RA, dashboard-as-code). **Ale** oceń dojrzałość: to nie jest jeszcze zamiennik
  Grafany 1:1 — zweryfikuj, czy Twoje panele, źródła i wolumen logów są wspierane.
- **Najbardziej wrażliwe są LOGI i chcesz darmowej, bardzo drobnej izolacji** (per indeks/
  dokument/pole, tenants) → **OpenSearch Dashboards** dla warstwy logów. Cena: logi lądują w
  OpenSearch (nie Loki), inny język, osobny store; metryki i tak zostają gdzie indziej.
- **Potrzebujesz BI z row-level security** (raporty na danych SQL, filtr wierszy per rola) →
  **Superset**. To nie jest narzędzie do metryk/logów observability — traktować jako uzupełnienie,
  nie zamiennik Grafany.

---

## 3. Częściej lepsze niż zmiana narzędzia: architektura

Problem z [11](11-granulacja-uprawnien-warianty.md)/[13](13-loki-wplyw-na-self-hosted-i-izolacje.md)
to **izolacja per tenant w JEDNEJ instancji OSS**. Zamiast wymieniać narzędzie, izolację można
przenieść na poziom wdrożenia — **zostając na Grafanie OSS**:

- **Instancja Grafany OSS per system/tenant** — każdy system dostaje własną (tanią, darmową)
  instancję. Izolacja jest **twarda i naturalna** (osobne procesy/DS), bez Enterprise i bez
  reconcilera. Koszt: N instancji do wdrożenia/aktualizacji (ale to powtarzalne Helmem,
  [08](08-self-hosted-grafana-analysis.md)) i brak współdzielenia dashboardów między systemami.
- **Multi-org w jednej Grafanie OSS** ([11](11-granulacja-uprawnien-warianty.md) wariant C) —
  lżejsze niż N instancji, cięższe operacyjnie niż jedna org.
- **Wielotenantowość na poziomie stacku** (Mimir/Loki/Tempo mają natywne tenanty) + brama/proxy —
  izolacja danych u źródła; warstwa wizualizacji dowolna.

Te opcje zwykle **taniej i mniej ryzykownie** dają izolację niż migracja na inny tool — bo
zachowują ekosystem Grafany.

---

## 4. Uczciwy bilans zmiany narzędzia

Wymiana Grafany „dla RBAC" to **wymiana jednego problemu na kilka**:

- **Ekosystem** — Grafana ma najwięcej wtyczek/źródeł danych; alternatywy mają mniej.
- **Migracja treści** — dashboardy Grafany (JSON) **nie są przenośne** do Perses/OpenSearch/
  Superset; trzeba je odtworzyć.
- **Kompetencje/UX** — inne języki (PPL/SQL zamiast PromQL/LogQL), nowa krzywa uczenia.
- **Integracje** — Alloy/OTel, Azure Managed Grafana, `managed_grafana_internal` (Terraform
  `grafana`) są pod Grafanę; alternatywa = własne integracje od zera.
- **Dojrzałość/ryzyko** — Perses jest młody (sandbox); ryzyko funkcji/porzucenia większe niż
  przy Grafanie.

**Reguła kciuka:** jeśli inwestycja jest głównie w Grafanę, a problem to izolacja tenantów →
najpierw **architektura (instancje/multi-org)** lub **Enterprise/LBAC**, a dopiero potem zmiana
narzędzia. Zmiana toola ma sens, gdy granularny RBAC jest *nadrzędnym* wymaganiem produktu i
akceptujesz koszt migracji — wtedy **Perses** (profil observability) lub **OpenSearch** (logi).

---

## 5. Otwarte pytania

1. **Czy granularny RBAC jest wymaganiem nadrzędnym**, czy problemem do obejścia? Jeśli obejściem —
   architektura (§3) bije zmianę narzędzia.
2. **Co jest najwrażliwsze** — logi (→ OpenSearch), metryki (→ Perses), czy dane SQL/BI (→ Superset)?
3. **Apetyt na dojrzałość vs nowość** — czy zespół zaakceptuje Perses (sandbox) zamiast Grafany?
4. **Koszt migracji** dashboardów i integracji (Alloy/OTel, Terraform) — policzalny i akceptowalny?
5. **Ile realnie tenantów** — przy niewielu instancje OSS per tenant są proste; przy wielu rośnie
   koszt operacyjny (przemawia za Enterprise/LBAC lub Perses).

---

## Źródła (dostęp 2026-07-21)

- **Perses** (CNCF Sandbox, K8s-inspired RBAC, Apache 2.0, Prometheus/Loki/Tempo/Pyroscope):
  [perses.dev](https://perses.dev/),
  [Perses — CNCF](https://www.cncf.io/projects/perses/),
  [github.com/perses/perses](https://github.com/perses/perses).
- **OpenSearch** fine-grained access control (indeks/dokument/pole, tenants):
  [About Security — OpenSearch docs](https://docs.opensearch.org/latest/security/).
- **Apache Superset** RBAC + Row-Level Security:
  [Security — Apache Superset](https://superset.apache.org/admin-docs/security/),
  [Row Level Security — Apache Superset](https://superset.apache.org/developer-docs/api/row-level-security/).
