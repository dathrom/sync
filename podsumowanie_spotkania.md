# Podsumowanie spotkania — Platforma monitoringu na Azure

> **Temat:** Budowa platformy observability na Azure (Grafana · Prometheus · Loki · Mimir)
> **Format:** Sesja konsultacyjna (~2,5 h) — ekspert ds. observability/Azure + zespół klienta
> **Źródło:** [transkrybcja](transkrybcja) (transkrypcja automatyczna, mocno zniekształcona fonetycznie)

---

## Spis treści

- [Kontekst](#kontekst)
- [Omówione zagadnienia](#omówione-zagadnienia)
- [Wnioski](#wnioski)
- [Następne kroki](#następne-kroki)
- [Słowniczek zniekształceń transkrypcji](#słowniczek-zniekształceń-transkrypcji)

---

## Kontekst

Zapis technicznej sesji konsultacyjnej pomiędzy **ekspertem** (konsultant ds. observability / Azure) a **zespołem klienta**. Tematem jest budowa platformy monitoringu na Azure w oparciu o stos **Grafana + Prometheus + Loki + Mimir**.

Transkrypcja pochodzi z automatycznego rozpoznawania mowy i zawiera liczne zniekształcenia fonetyczne (patrz [słowniczek](#słowniczek-zniekształceń-transkrypcji)).

---

## Omówione zagadnienia

### 1. Private endpoint + Azure Managed Grafana / Managed Prometheus

Gdy w jednym regionie działa kilka instancji Managed Prometheus i którakolwiek włączy **private endpoint**, pozostałe przestają działać.

- **Przyczyna:** Azure automatycznie nadpisuje DNS — regionalna prywatna strefa DNS (`privatelink...`) jest współdzielona per region. Microsoft nie przewidział wielu Prometheusów w jednym regionie.
- **Rozwiązanie:** w danym regionie **wszystkie instancje private albo wszystkie public** (mieszać można wyłącznie między regionami).
- Potwierdzone testem eksperta oraz dokumentacją Microsoft.

### 2. Podpięcie własnego Prometheusa (AKS / on-prem)

- Realizowane przez **Private Link Service → managed private endpoint**, z hardkodowaniem adresu w konfiguracji Grafany.
- Dla źródeł poza Azure (on-prem) potrzebny **jump host / VM proxy** albo **Load Balancer (Standard)** + VPN / ExpressRoute.

### 3. Data sources Azure Monitor — dylemat *current user* vs *managed identity*

| Tryb | RBAC per użytkownik | Alerty |
|------|:---:|:---:|
| **Current user** | ✅ działa | ❌ nie działa |
| **Managed identity / Service Principal** | ❌ traci granularność | ✅ działa |

Alert wykonuje się w kontekście Grafany, a nie zalogowanego użytkownika — stąd konflikt. Pełna elastyczność dopiero w **self-hosted Grafanie na Kubernetes**.

### 4. Multi-tenancy / organizacje

- Grafana: organizacje; Loki: multi-tenancy przez nagłówek `X-Scope-OrgID`.
- **Ograniczenia:** Loki nie ma row/index-level security (to jest w Elasticsearch); data source trzeba definiować per organizacja.
- **Rekomendowany model:** organizacje w Loki mapowane na **system / data stream**, nie na strukturę firmy; ten sam data source dodawany wielokrotnie z uprawnieniami per team.

### 5. Zbieranie logów z PaaS — kluczowa rekomendacja kosztowa

```
Diagnostic settings ──▶ Event Hub ──▶ Vector ──▶ Loki
```

- Znacznie **taniej niż Log Analytics** przy długiej retencji.
- **Metryki:** exporter (Azure Monitor agent) ──▶ **Mimir** dla long-term (Azure Monitor trzyma tylko 90 dni).

### 6. Alerty — wydajność

| Typ | Mechanizm | Skalowalność |
|-----|-----------|--------------|
| **Grafana-managed** | cron robiący query | ❌ słaba, duplikacja przy HA |
| **Data-source managed (Mimir / Loki ruler)** | działa w *ingestion time* | ✅ dziesiątki tysięcy reguł |

Grafana słabo nadaje się do tysięcy „czujek" — do dużej skali używać rulera po stronie data source.

### 7. Loki — brak full-text search

- Trzeba wskazać konkretne pole; domyślnie **nie indeksuje `message`**.
- Alerty na tekście w logach wymagają **strukturyzowania logów (JSON)** po stronie aplikacji.

### 8. Grafana Cloud

- Brak organizacji / multi-tenancy (pod koniec ekspert przyznaje, że funkcja mogła zostać dodana niedawno).
- Uznane za powód, dla którego Grafana Cloud raczej **odpada** dla klienta.

### 9. Email / SMTP

- Brak natywnej wysyłki w Managed Grafana.
- Potrzebny **relay SMTP** albo **webhook → Azure Logic App**.

### 10. Event Hub

- Throughput units (1–40); **auto-inflate** skaluje w górę, ale **nie w dół** (płatność za provisioned).
- W dużej skali rekomendowane **centralne Event Huby** (mniej zasobów do zarządzania).

### 11. Lab / kod

- Ekspert przygotował **Terraform + skrypty** (deploy AKS, Prometheus, Azure Monitor agent) oraz **runbook** z krokami „jak zepsuć / naprawić".
- Problemy z przekazaniem: załącznik maila blokowany przez security, artefakty `._*` z macOS mylące na Windows → ustalono przekazanie przez **prywatne repo GitHub**.

### 12. Vector vs Alloy vs OpenTelemetry Collector

- **Vector** — lekki, szybki, open-source (Datadog). Wada: brak systemu pluginów (np. brak inputu Windows Event Log).
- **Alloy** — cięższy.
- **OpenTelemetry** — uniwersalny fallback.

---

## Wnioski

1. **Architektura docelowa się skrystalizowała** — self-hosted Grafana (OSS/Enterprise) na AKS + Loki + Mimir + Vector, z logami/metrykami z PaaS przez Event Hub. Prościej, taniej i elastyczniej niż walka z Azure Managed Grafana/Prometheus i ich private linkami.

2. **Azure Managed Grafana/Prometheus ma twarde ograniczenia** (DNS per region, brak kontroli nad managed vnet, sztywny wybór current-user vs identity). Sensowne głównie przy zakupie licencji Enterprise przez Azure commitment — ze względów zakupowych, nie technicznych.

3. **Fundamentalny konflikt: tanio vs bezpiecznie/granularnie vs alerty.** Nie da się jednocześnie mieć per-user RBAC (current user) i działających alertów, ani taniego Loki z pełnym row-level security. Trzeba świadomie wybrać kompromis.

4. **Model platformowy (jeden zespół dostarcza monitoring wszystkim) jest pod prąd narzędzi** — Grafana/Loki/Mimir zakładają model „jeden zespół = jeden stack". Granularny dostęp do logów będzie wymagał obejść i najpewniej Enterprise.

5. **Jakość logów jest po stronie aplikacji.** Bez ustrukturyzowanych logów (JSON z właściwymi polami) alerty na tekście w Loki nie zadziałają sensownie. Zespół chce to wymusić na deweloperach („nie loguje dobrze = nie ma alertów").

---

## Następne kroki

- [ ] Postawienie labu z przygotowanego kodu (Terraform + skrypty), dostarczonego przez prywatne repo GitHub.
- [ ] Potwierdzenie kwestii full-text search w Loki (ekspert obiecał sprawdzić „na jutro").
- [ ] Przejście do drugiej części zamówienia.

**Zalecenia operacyjne na start:**

- PostgreSQL zamiast SQLite pod Grafaną (przy 200+ dashboardach).
- Sync dashboardów do GitHub + backup.
- Centralne Event Huby z auto-inflate + funkcja resetująca throughput units.

---

## Słowniczek zniekształceń transkrypcji

| W transkrypcji | Właściwie |
|----------------|-----------|
| „private and point" | private endpoint |
| „a żur" / „ażurowy" | Azure |
| „lot balancer" / „blond balanser" | load balancer |
| „trupu unity" / „trójpodwórnity" | throughput units |
| „mecz" | message |
| „prawie link serwis" | Private Link Service |
| „karen dius" / „current user" | current user |
| „riler" / „rooler" | ruler |
| „i went hub" | Event Hub |
| „wektor" | Vector |
| „aloj" | Alloy |
| „lok fary" | Log4j |
