# Analiza: jak wdrożenie Loki zmieniłoby POC `grafana-poc-example`

> **Status:** wersja skorygowana po weryfikacji źródłowej.
> **Źródła:** [podsumowanie_spotkania.md](podsumowanie_spotkania.md),
> [transkrybcja](transkrybcja), kod POC w [grafana-poc-example/](grafana-poc-example/).
> **Weryfikacja tez:** [research_potwierdzenie_ograniczen_narzedzi_na_spotkaniu.md](research_potwierdzenie_ograniczen_narzedzi_na_spotkaniu.md).
> Cytaty `plik:linia` odnoszą się do plików w `sync/`.

---

## Changelog — poprawki naniesione po researchu (2026-07-10)

Względem pierwotnej analizy zmieniono następujące punkty (powód + źródło w pliku
researchu):

1. **Vector a Windows Event Log** — usunięto tezę „Vector nie ma inputu Windows
   Event Log". Vector **ma** natywny source `windows_event_log` (beta). *(research #13)*
2. **Multi-tenancy `X-Scope-OrgID`** — sprostowano: Grafana **nie** wstrzykuje
   automatycznie tenanta per organizacja użytkownika; jest tylko **statyczny nagłówek
   per data source**, konfigurowany ręcznie. Izolacja = ręczna robota, nie automat.
   *(research #14)*
3. **Loki ruler** — usunięto „ingestion time"; ruler ewaluuje reguły **okresowo**
   po stronie data source, skaluje się przez hash ring. Dodano, że Grafana
   rekomenduje Grafana-managed „whenever possible". *(research #11)*
4. **Teza kosztowa** — doprecyzowano: oszczędność daje **Loki na object storage**
   zamiast ingestu Log Analytics; Event Hub to transport/bufor, nie magazyn
   retencyjny. *(research #7)*
5. **Row-level security** — dodano niuans **LBAC** (kontrola po etykietach w
   Grafana Enterprise/Cloud) obok tezy o braku ES-owego field/doc-level security.
   *(research #9)*
6. **Dostarczanie alertów (SMTP)** — wcześniejsza „luka" złagodzona: Managed Grafana
   (Standard) **ma natywny SMTP**; webhook → Logic App niekonieczny (nadal potrzebny
   zewnętrzny serwer SMTP). *(research #3)*
7. **Service accounts w Managed Grafana** — są **domyślnie wyłączone, ale
   włączalne**; provider Terraform Grafany działa z tokenem SA. Komentarz
   `configure-grafana.sh:14-15` jest nieprecyzyjny. *(research #4)*
8. **Taksonomia Kroku 1** — ograniczenia/właściwości narzędzi rozdzielono od
   „twardych wymagań klienta" (osobna kategoria *ograniczenie/motywacja*).
9. **Krok 3** — AMW usunięte z listy źródeł diagnostic settings (nie emituje
   sensownych resource-logs do EH); Storage Account i Workload Identity
   przekwalifikowane z „koniecznych" na „opcje POC".

---

## Krok 1 — Zidentyfikowane potrzeby wokół Loki

Typy: **W** = twarde wymaganie klienta · **R** = rekomendacja eksperta ·
**O** = ograniczenie/właściwość narzędzia (do zaakceptowania) · **I** = inferencja.

| # | Punkt | Typ | Źródło |
|---|-------|:---:|--------|
| 1 | Ścieżka logów `Diagnostic settings → Event Hub → Vector → Loki` | W | [podsumowanie:59-61](podsumowanie_spotkania.md#L59-L61); [transkrybcja:638-639](transkrybcja#L638-L639) |
| 2 | Motywacja kosztowa: taniej niż Log Analytics przy długiej retencji — oszczędność z **Loki na object storage**, nie z Event Huba (transport) | R (motywacja) | [podsumowanie:63](podsumowanie_spotkania.md#L63); research #7 |
| 3 | Multi-tenancy przez nagłówek `X-Scope-OrgID` — **statyczny per data source, konfigurowany ręcznie** (brak auto-mapowania org→tenant) | W + O | [podsumowanie:53](podsumowanie_spotkania.md#L53); research #8, #14 |
| 4 | Model „organizacja = system / data stream"; DS wielokrotnie z uprawnieniami per team | R | [podsumowanie:55](podsumowanie_spotkania.md#L55); [transkrybcja:879](transkrybcja#L879) |
| 5 | Brak ES-owego row/field-level security; izolacja tenant-level, ale istnieje **LBAC** (label-level) w Enterprise/Cloud | O | [podsumowanie:54](podsumowanie_spotkania.md#L54); research #9 |
| 6 | Brak full-text search; `message` domyślnie nieindeksowane (indeks tylko po labelach) | O | [podsumowanie:77](podsumowanie_spotkania.md#L77); research #10 |
| 7 | Wymóg strukturyzowania logów (JSON) po stronie aplikacji („nie loguje dobrze = nie ma alertów") | W | [podsumowanie:78](podsumowanie_spotkania.md#L78),[:118](podsumowanie_spotkania.md#L118) |
| 8 | Alerty: **data-source-managed Loki ruler** (ewaluacja okresowa po stronie DS, skalowanie hash-ring), nie Grafana cron. Uwaga: Grafana rekomenduje Grafana-managed „whenever possible"; DS-managed dla skali | R | [podsumowanie:71](podsumowanie_spotkania.md#L71); [transkrybcja:1431](transkrybcja#L1431); research #11, #16 |
| 9 | Agent: **Vector** (lekki, szybki); alt. Alloy/OTel. *Wada „brak Windows Event Log" — nieaktualna: Vector ma `windows_event_log` (beta)* | R | [podsumowanie:100-104](podsumowanie_spotkania.md#L100-L104); research #12, #13 |
| 10 | Event Hub: TU 1–40, auto-inflate w górę, **nie w dół** (płacisz za provisioned); auto-inflate tylko tier Standard | O | [podsumowanie:92](podsumowanie_spotkania.md#L92); research #6 |
| 11 | W dużej skali: centralne Event Huby | R | [podsumowanie:93](podsumowanie_spotkania.md#L93); [transkrybcja:1686-1687](transkrybcja#L1686-L1687) |
| 12 | PostgreSQL zamiast SQLite pod (self-hosted) Grafaną — wymóg HA/wielu instancji | R | [podsumowanie:130](podsumowanie_spotkania.md#L130); research #15 |
| 13 | Docelowo self-hosted Grafana na AKS + Loki + Mimir + Vector | R | [podsumowanie:110](podsumowanie_spotkania.md#L110) |
| 14 | Mimir jako long-term store metryk (Azure Monitor tylko 90 dni) — oś metryk, poza rdzeniem tej analizy | R | [podsumowanie:64](podsumowanie_spotkania.md#L64) |
| 15 | Vector czyta z Event Huba przez endpoint **Kafka** (Standard+); brak dedykowanego source EH; `amqp` Vectora (0.9.1) nie pasuje do EH (AMQP 1.0) | I | [transkrybcja:1355-1358](transkrybcja#L1355-L1358); research #12 |

---

## Krok 2 — Stan POC dziś (potwierdzone z kodu)

POC jest **wyłącznie metrykowy**:
- Azure **Managed** Grafana, SKU Standard, publiczna — [grafana.tf:14](grafana-poc-example/terraform/grafana.tf#L14).
- 2× Azure Monitor Workspace: AMW-A prywatna ([monitoring.tf:23](grafana-poc-example/terraform/monitoring.tf#L23), [dns.tf:21](grafana-poc-example/terraform/dns.tf#L21)), AMW-B publiczna ([monitoring.tf:74](grafana-poc-example/terraform/monitoring.tf#L74)).
- managed-Prometheus/ama-metrics → AMW-A ([aks.tf:51](grafana-poc-example/terraform/aks.tf#L51)); self-hosted Prometheus → AMW-B ([prometheus-values.yaml:24](grafana-poc-example/terraform/k8s/prometheus-values.yaml#L24)).
- 4 data source'y, wszystkie metrykowe ([configure-grafana.sh:43-58](grafana-poc-example/terraform/configure-grafana.sh#L43-L58)); OMS/Container Insights celowo wyłączone ([aks.tf:53](grafana-poc-example/terraform/aks.tf#L53)).

**Brak jakiegokolwiek komponentu logowego** — `grep` po `terraform/`
(loki/eventhub/vector/diagnostic_setting/storage_account/mimir) = **0 trafień**.

---

## Krok 3 — Zmiany wprowadzone przez Loki

### Drzewo architektury PO wdrożeniu Loki

```
Azure — RG: rg-xyz-grafmon-lab                                    (ISTNIEJE  main.tf:8)
│
├─ ISTNIEJE  Azure Managed Grafana  (Standard, publiczna)          grafana.tf:14
│   ├─ ISTNIEJE  DS AMW-A / AMW-B / AzMon / OSS-Prometheus-PLS      configure-grafana.sh:43-58
│   ├─ NOWE      DS Loki × N  (jeden per organizacja=system;        [blok w configure-grafana.sh]
│   │             STATYCZNY nagłówek X-Scope-OrgID per DS — ręcznie)
│   ├─ NOWE      Loki ruler jako alerting „data-source managed"     (ewaluacja okresowa)
│   └─ (KONFIG)  natywny SMTP dla dostarczania alertów              (Managed Grafana Standard)
│
├─ ISTNIEJE  AKS  aks-xyz-grafmon-lab                              aks.tf:14
│   ├─ ISTNIEJE  managed-Prometheus → AMW-A / self-hosted Prom → AMW-B / PLS
│   ├─ NOWE      Loki  (Helm; write/read; ruler)                   [loki.tf + krok Helm]
│   └─ NOWE      Vector (Event Hub[Kafka] → Loki)                   [vector-values.yaml]
│
├─ ISTNIEJE  2× Azure Monitor Workspace                           monitoring.tf:23 / :74
│
├─ NOWE      Event Hub Namespace + hub(y)  (tier Standard: Kafka + auto-inflate)  [eventhub.tf]
├─ NOWE      Diagnostic settings → Event Hub  na źródłach PaaS:    [logging.tf]
│              realnie w TYM POC: AKS + Managed Grafana
│              (AMW pominięte — brak sensownych resource-logs do EH)
│
├─ OPCJA POC Storage Account (Blob) — backend Loki                 [storage.tf]
│              (lab może użyć filesystem/emptyDir jak Prometheus:
│               prometheus-values.yaml:51 persistentVolume=false)
├─ OPCJA     Private DNS zone privatelink.blob… / …servicebus…     [dns.tf — jeśli prywatne]
├─ ISTNIEJE  Private DNS zone privatelink.<region>.prometheus…     dns.tf:21
│
├─ OPCJA     Tożsamość Vector/Loki → Azure:                        [identity.tf / rbac.tf]
│              (A) kubelet MI + IMDS  — spójne z istniejącym wzorcem prometheus-values.yaml:17-21
│              (B) Workload Identity + OIDC issuer — alternatywa (nie konieczność)
│              Role: Vector→Event Hubs Data Receiver; Loki→Storage Blob Data Contributor
│
└─ OPCJA     Mimir (long-term metryk)                             [poza rdzeniem analizy logowej]
```

### Tabela zmian

| Zasób / Plik | Akcja | Powód |
|---|---|---|
| `eventhub.tf` (namespace **Standard**, hub, consumer group, auto-inflate) | NOWY | [podsumowanie:59-61](podsumowanie_spotkania.md#L59-L61),[:92-93](podsumowanie_spotkania.md#L92-L93); Kafka wymaga Standard (research #12) |
| `logging.tf` (`azurerm_monitor_diagnostic_setting` → Event Hub) | NOWY | wejście ścieżki; realne źródła: AKS [aks.tf:14](grafana-poc-example/terraform/aks.tf#L14), Grafana [grafana.tf:14](grafana-poc-example/terraform/grafana.tf#L14) |
| `loki.tf` (deployment Loki; ruler) | NOWY | [podsumowanie:59-61](podsumowanie_spotkania.md#L59-L61),[:71](podsumowanie_spotkania.md#L71) |
| `k8s/vector-values.yaml` + krok w `deploy-k8s.sh` | NOWY / MOD | [podsumowanie:100-104](podsumowanie_spotkania.md#L100-L104); wzorzec Helm [deploy-k8s.sh:70](grafana-poc-example/terraform/k8s/deploy-k8s.sh#L70) |
| `configure-grafana.sh` (DS Loki × N, statyczny `X-Scope-OrgID`; ew. włączenie SMTP) | MOD | [podsumowanie:53-55](podsumowanie_spotkania.md#L53-L55); research #14, #3 |
| `rbac.tf` (Vector→*Event Hubs Data Receiver*; Loki→*Storage Blob Data Contributor* jeśli Blob) | MOD | wzorzec ról [rbac.tf:59-78](grafana-poc-example/terraform/rbac.tf#L59-L78) |
| `storage.tf` (Blob pod Loki) | NOWY **opcjonalnie** | konieczne produkcyjnie; w labie można filesystem ([prometheus-values.yaml:51](grafana-poc-example/terraform/k8s/prometheus-values.yaml#L51)) |
| `identity.tf` / `aks.tf` (Workload Identity + OIDC) | MOD **opcjonalnie** | alternatywa dla istniejącego kubelet MI/IMDS ([prometheus-values.yaml:17-21](grafana-poc-example/terraform/k8s/prometheus-values.yaml#L17-L21)) |
| `dns.tf` / `network.tf` (strefy + subnet PE dla Blob/EH) | MOD **opcjonalnie** | tylko jeśli prywatne; wzorzec [dns.tf:21-35](grafana-poc-example/terraform/dns.tf#L21-L35) |
| `outputs.tf`, `teardown.sh` | MOD | endpoint Loki / EH; sprzątanie diagnostic settings |
| `monitoring.tf`, `main.tf`, `providers.tf`, `locals.tf`, `variables.tf` | bez zmian | rdzeń metrykowy nietknięty |

**„Wynika wprost z ustaleń":** DS Loki z `X-Scope-OrgID`, Loki ruler, Vector, ścieżka
Diagnostic settings→EH→Vector→Loki, Event Hub z auto-inflate.
**„Konsekwencja techniczna":** consumer group na EH, rola *Event Hubs Data Receiver*
dla Vectora, tożsamość i rola dla Loki (jeśli Blob).
**Opcje POC (nie konieczności):** Storage Account (vs filesystem), Workload Identity
(vs kubelet IMDS), prywatne PE/DNS dla Blob/EH.

---

## Kompromisy i ryzyka

1. **Tanio vs granularnie vs alerty** — nie da się mieć jednocześnie taniego Loki z
   pełnym row-level security ani per-user RBAC z działającymi alertami
   ([podsumowanie:114](podsumowanie_spotkania.md#L114)). Potwierdzone: current-user vs
   alerty (research #2).
2. **Brak ES-owego row/field-level security** — jest tylko LBAC na poziomie etykiet
   (Enterprise/Cloud), nie na wierszach/polach treści ([podsumowanie:54](podsumowanie_spotkania.md#L54); research #9).
3. **Jakość logów po stronie aplikacji** — bez JSON alerty na treści w Loki nie
   zadziałają ([podsumowanie:78](podsumowanie_spotkania.md#L78); research #10).
4. **Event Hub auto-inflate nie skaluje w dół** — po skoku płacisz za provisioned TU;
   zalecana funkcja resetująca ([podsumowanie:92](podsumowanie_spotkania.md#L92),[:132](podsumowanie_spotkania.md#L132); research #6).
5. **Multi-tenancy = ręczna robota** — brak auto-mapowania org→`X-Scope-OrgID`;
   izolację buduje się DS per tenant, co przy modelu „organizacja=system" oznacza
   realny nakład konfiguracyjny i operacyjny (research #14).

---

## Otwarte pytania

1. **Managed Grafana czy self-hosted?** Managed Grafana uniesie DS Loki + ruler +
   (Standard) natywny SMTP + service accounts (po włączeniu), więc dodanie Loki **nie
   wymusza** migracji. Ale rekomendacja PostgreSQL ([:130](podsumowanie_spotkania.md#L130))
   i dynamiczny model multi-tenancy dotyczą self-hosted. To rozstrzyga zakres.
2. **Loki single- czy multi-tenant** (`auth_enabled`)? Model „organizacja=system"
   implikuje multi-tenant.
3. **Storage Loki:** Azure Blob (produkcyjnie) czy filesystem/emptyDir (lab)?
4. **Tożsamość Vector/Loki → Azure:** kubelet MI/IMDS (spójne z kodem) czy Workload
   Identity?
5. **Dostarczanie alertów:** natywny SMTP Managed Grafana (Standard) — wystarczy?
   (wcześniejsza „luka" Logic App zbędna — research #3).
6. **Model Event Hubów:** per-RG czy centralny ([:93](podsumowanie_spotkania.md#L93))?
   Dla POC prawdopodobnie jeden namespace **Standard** (Kafka wymaga min. Standard).
7. **Czy Mimir wchodzi w zakres tego POC** (oś metryk) — czy demonstrujemy tylko oś
   logów?
