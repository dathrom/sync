# Grafana PoC — jak to jest zbudowane i jak działa

*Lab observability na Azure: Managed Grafana + 2× Azure Monitor Workspace karmione Prometheusem. Całość w Terraformie ([grafana-poc-example/terraform/](grafana-poc-example/terraform/)) plus kilka skryptów, które dokańczają robotę po `apply`.*

---

## Slajd 1 — Co to w ogóle jest

Cel PoC: pokazać **dwie różne ścieżki zbierania metryk** do Grafany i różnicę **prywatne vs publiczne** połączenie do źródeł danych. Wszystko opisane po polsku w [README.pl.md](grafana-poc-example/README.pl.md).

- **AMW-A** (prywatna) — metryki lecą z **dodatku managed-Prometheus** w AKS (agent `ama-metrics`), dostęp przez Private Endpoint + prywatny DNS.
- **AMW-B** (publiczna) — metryki z **self-hosted Prometheusa** (doinstalowany Helmem) przez `remote_write`.
- **Grafana** zostaje publiczna — prywatyzujemy *dane i źródła*, nie sam interfejs ([grafana.tf:6](grafana-poc-example/terraform/grafana.tf#L6)).

Kolejność odpalania: `terraform apply` → [k8s/deploy-k8s.sh](grafana-poc-example/terraform/k8s/deploy-k8s.sh) → [configure-grafana.sh](grafana-poc-example/terraform/configure-grafana.sh) → sprzątanie [teardown.sh](grafana-poc-example/terraform/teardown.sh) **przed** `terraform destroy`.

---

## Slajd 2 — Jak to działa (klocki)

```
        Managed Grafana (publiczna, MSI SystemAssigned)
         │ odczyt metryk       │ odczyt prywatnie (MPE→PLS)
   ┌─────┴─────┬───────────────┴────────┬──────────────┐
   ▼           ▼                        ▼              ▼
 AMW-A       AMW-B              self-hosted Prom   Azure Monitor
(prywatna) (publiczna)           (w AKS, PLS)      (Obszar 2)
   ▲ DCR-A     ▲ DCR-B (remote_write)  ▲
   └───────────┴──────────────────────┘
            Klaster AKS (1 węzeł)
   • ama-metrics  → AMW-A     • self-hosted Prometheus → AMW-B
```

- AKS gra podwójną rolę — hostuje dodatek *i* self-hosted Prometheusa ([aks.tf:1](grafana-poc-example/terraform/aks.tf#L1)).
- Każda AMW ma parę **DCE** (punkt wejścia) + **DCR** (reguła: skąd strumień, dokąd zapis) — [monitoring.tf](grafana-poc-example/terraform/monitoring.tf).
- Prywatna ścieżka do AMW-A: jawna strefa DNS + Private Endpoint ([dns.tf](grafana-poc-example/terraform/dns.tf)). Do AMW-B **celowo** nie ma PE — brak DNS pokazuje błąd NXDOMAIN w scenariuszu demo ([dns.tf:9](grafana-poc-example/terraform/dns.tf#L9)).

---

## Slajd 3 — Przepływ sekretów i wartości zmiennych 🔑

**Zasada numer jeden: zero sekretów w kodzie.** Logujemy się „z otoczenia", czyli po zwykłym `az login` — oba providery biorą poświadczenia z sesji az CLI ([providers.tf:4](grafana-poc-example/terraform/providers.tf#L4), [providers.tf:28](grafana-poc-example/terraform/providers.tf#L28)).

**Gdzie się da — passwordless.** Prawie wszystko chodzi na tożsamościach zarządzanych (MSI), bez żadnych haseł:
- Grafana → AMW: MSI Grafany.
- self-hosted Prometheus → AMW-B: tożsamość **kubeleta z IMDS** (`169.254.169.254`), blok `azuread` w remote_write — client_id, żadnego sekretu ([prometheus-values.yaml:13](grafana-poc-example/terraform/k8s/prometheus-values.yaml#L13)).

**Jedyne prawdziwe hasło w całym labie** to sekret service principala dla Obszaru 2 — generuje go Terraform ([identity.tf:21](grafana-poc-example/terraform/identity.tf#L21)). I tu ważna rzecz, wprost w komentarzu: **ten sekret ląduje w stanie Terraform i w outputs jako `sensitive`** ([identity.tf:5](grafana-poc-example/terraform/identity.tf#L5), [outputs.tf:62](grafana-poc-example/terraform/outputs.tf#L62)).

**Jak płyną wartości** — Terraform liczy, a skrypty czytają jego outputy przez `terraform output -raw` i wstrzykują dalej:

| Wartość | Skąd | Dokąd trafia |
|---|---|---|
| `app_reg_client_id` + `app_reg_secret` | outputs | do data source **Azure Monitor** w Grafanie jako `fallbackClientSecret` ([configure-grafana.sh:44](grafana-poc-example/terraform/configure-grafana.sh#L44)) |
| `amw_a/b_query_endpoint` | outputs | URL-e źródeł Prometheus w Grafanie ([configure-grafana.sh:40](grafana-poc-example/terraform/configure-grafana.sh#L40)) |
| remote_write URL + `kubelet_client_id` | outputs + `az resource show` | `sed` podmienia `PLACEHOLDER_*` w [prometheus-values.yaml](grafana-poc-example/terraform/k8s/prometheus-values.yaml) tuż przed `helm install` ([deploy-k8s.sh:90](grafana-poc-example/terraform/k8s/deploy-k8s.sh#L90)) |

Czyli: **Terraform = źródło prawdy dla wartości**, skrypty = „klej", który rozwozi je do data-plane Grafany i Prometheusa.

---

## Slajd 4 — Tożsamości, RBAC, SPN-y 👤

W grze jest **sześć** aktorów. Całe RBAC siedzi w jednym pliku: [rbac.tf](grafana-poc-example/terraform/rbac.tf).

| Kto | Typ | Rola → gdzie | Po co |
|---|---|---|---|
| Grafana | System MI | Monitoring Data Reader → AMW-A, AMW-B; Monitoring Reader → RG | odczyt metryk + źródło Azure Monitor |
| AKS control-plane | System MI | Monitoring Metrics Publisher → DCR-A; Network Contributor → vnet-lab | zapis metryk; postawienie wewn. LB / PLS |
| AKS kubelet | MI (z IMDS) | Metrics Publisher → DCR-A i DCR-B | zapis z self-hosted Prometheusa |
| App-reg (SPN) | Service Principal + sekret | Monitoring Reader → RG | „usługowe" źródło danych (Obszar 2) |
| Osoba wdrażająca | current user | **Grafana Admin** → Grafana | zarządzanie źródłami danych |
| User testowy (opcja) | AAD user | Grafana Viewer + Monitoring Reader | pusty domyślnie ([variables.tf:38](grafana-poc-example/terraform/variables.tf#L38)) |

Trzy rzeczy warte pokazania na spotkaniu:

1. **Nadanie roli OBU tożsamościom AKS „na wszelki wypadek"** — nie było pewne, którą MI bierze `ama-metrics` (control-plane czy kubelet), więc dostają obie. Nadmiarowo, ale zapis do AMW-A nie wywali się na 403 ([rbac.tf:45](grafana-poc-example/terraform/rbac.tf#L45)).
2. **Owner subskrypcji ≠ dostęp do Grafany.** Data-plane Grafany wymaga osobnej roli `Grafana Admin`, inaczej nie stworzysz źródeł danych ([rbac.tf:86](grafana-poc-example/terraform/rbac.tf#L86)).
3. **Po co w ogóle ten SPN.** Managed Grafana **wyłącza konta usługowe**, więc provider Grafany w Terraformie nie ma jak się zalogować — stąd konfiguracja przez `az grafana` w skrypcie ([configure-grafana.sh:11](grafana-poc-example/terraform/configure-grafana.sh#L11)). A sam SPN jest po to, że **alerty w Grafanie nie działają na „current user"** — muszą jechać na poświadczeniach usługowych ([podsumowanie_spotkania.md:42](podsumowanie_spotkania.md#L42)).

---

## Slajd 5 — Czego tu nie ma i co bym zrobił inaczej (to tylko PoC)

Większość poniższego jest **świadomie odpuszczona, bo to lab na demo** — ale warto to nazwać:

**Sekrety / stan:**
- Sekret SP siedzi w **lokalnym `terraform.tfstate`** — brak remote backendu i state lockingu (w [providers.tf](grafana-poc-example/terraform/providers.tf) nie ma bloku `backend`; na wierzchu repo leży nawet [state.tf_back](state.tf_back)). Na produkcji: Key Vault + backend na Azure Storage.
- Hasło SP **bez rotacji i bez daty wygaśnięcia** ([identity.tf:21](grafana-poc-example/terraform/identity.tf#L21)). Docelowo lepiej **workload identity federation** zamiast hasła w ogóle.
- [terraform.tfvars](grafana-poc-example/terraform/terraform.tfvars) z subscription ID **jest zakomitowany** do repo.

**Infra:**
- Nazwy zasobów **na sztywno** (`rg-xyz-grafmon-lab`, `grafana-xyz-lab`, `aks-...`) → dwie osoby nie postawią tego równolegle, będą kolizje ([main.tf:4](grafana-poc-example/terraform/main.tf#L4)).
- AKS: **1 węzeł, SKU Free, bez SLA**, Prometheus **bez persistence** ([aks.tf:16](grafana-poc-example/terraform/aks.tf#L16), [prometheus-values.yaml:48](grafana-poc-example/terraform/k8s/prometheus-values.yaml#L48)).
- **Data-plane poza Terraformem** — źródła danych i kroki S1.x/S2.x robione ręcznie skryptami i `az CLI`. To znaczy: **drift** i brak pełnej odtwarzalności z jednego `apply`.
- RBAC **nadmiarowy** (te „obie tożsamości") — świadomie nie-least-privilege.
- „Zarządzanie użytkownikami" praktycznie **nie istnieje** — jeden opcjonalny viewer, zero grup/zespołów/mapowania organizacji.

**Znane ograniczenia narzędzi (z ustaleń spotkania):**
- Prywatny endpoint na Managed Prometheus **psuje DNS pozostałym instancjom w regionie** — albo wszystkie private, albo wszystkie public ([podsumowanie_spotkania.md:29](podsumowanie_spotkania.md#L29)).
- Fundamentalny konflikt **current user (RBAC per user) vs managed identity (działające alerty)** — nie da się mieć obu naraz.
- **Brak logów** — PoC jest czysto metrykowy. Analizy, jak dołożyć Loki (Event Hub → Vector → Loki) i jak to zmienia RBAC, leżą w [jak_loki_zmienilby_obecny_grafana-poc-example.md](jak_loki_zmienilby_obecny_grafana-poc-example.md) i [jak_loki_zmienilby_drzewo_RBAC.md](jak_loki_zmienilby_drzewo_RBAC.md).
- Docelowo (wnioski ze spotkania) rozważane jest przejście na **self-hosted Grafana + Loki + Mimir na AKS** — taniej i elastyczniej niż walka z ograniczeniami wersji managed ([podsumowanie_spotkania.md:108](podsumowanie_spotkania.md#L108)).

---

### Do doczytania

[README.pl.md](grafana-poc-example/README.pl.md) · [podsumowanie_spotkania.md](podsumowanie_spotkania.md) · [wnioski_z_korelacji.md](wnioski_z_korelacji.md) · [research_potwierdzenie_ograniczen_narzedzi_na_spotkaniu.md](research_potwierdzenie_ograniczen_narzedzi_na_spotkaniu.md)
