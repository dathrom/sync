# 08 — Self-hosted Grafana na AKS (dokładna kopia managed Grafany) — analiza i rekomendacja

[◄ Decyzje projektowe](07-design-decisions.md) · [README](README.md) · [Model dostępu (grupy Entra) ►](09-selfhosted-rbac-entra-model.md)

> Dokument analityczny. **Nie implementuje** — rekomenduje metodę, uwspólnienie z
> Prometheusem, rozstrzyga problemy techniczne i podaje plan krok-po-kroku. Kod tylko jako
> zwięzłe szkice. Spójny z decyzjami z [07 — Decyzje projektowe](07-design-decisions.md);
> każde odejście od nich jest zaznaczone wprost.

---

## 1. Streszczenie stanu faktycznego (Krok 0)

Przeczytałem realny stan repo w
[`../grafana-poc-example/terraform`](../grafana-poc-example/terraform). Ustalenia:

1. **Managed Grafana** to `azurerm_dashboard_grafana.grafana` o nazwie `grafana-xyz-lab`,
   SKU `Standard`, `grafana_major_version = "12"`, tożsamość `SystemAssigned`,
   `public_network_access_enabled = true`
   ([grafana.tf:9-23](../grafana-poc-example/terraform/grafana.tf#L9-L23)).
2. **Cztery źródła danych** tworzy imperatywnie `configure-grafana.sh`/`.ps1` przez
   `az grafana data-source create` (nie Terraform, bo Azure Managed Grafana wyłącza konta
   usługowe): `AMW-A` i `AMW-B` (typ `prometheus`, auth `azureCredentials.authType=msi`),
   `AzMon-CurrentUser` (typ `grafana-azure-monitor-datasource`, auth `currentuser`) oraz
   `OSS-Prometheus-PLS` (typ `prometheus`, bez auth, przez MPE→PLS)
   ([configure-grafana.sh:37-56](../grafana-poc-example/terraform/configure-grafana.sh#L37-L56)).
3. **Uwierzytelnianie do AMW**: MI Grafany (SystemAssigned) ma `Monitoring Data Reader` na
   `amw_a` i `amw_b` ([rbac.tf:15-25](../grafana-poc-example/terraform/rbac.tf#L15-L25)).
   Grafana odpytuje **query endpoint AMW** (`amw_a_query_endpoint`, `amw_b_query_endpoint` —
   [outputs.tf:15-28](../grafana-poc-example/terraform/outputs.tf#L15-L28)), nigdy
   Prometheusa wprost.
4. **Wzorzec instalacji na AKS jest imperatywny**: `k8s/deploy-k8s.sh`/`.ps1` czyta
   `terraform output`, podmienia placeholdery `sed`-em w
   [`prometheus-values.yaml`](../grafana-poc-example/terraform/k8s/prometheus-values.yaml) i
   robi `helm upgrade --install prometheus prometheus-community/prometheus -n monitoring`
   ([deploy-k8s.sh:80-97](../grafana-poc-example/terraform/k8s/deploy-k8s.sh#L80-L97)).
   Chart to świadomie `prometheus-community/prometheus`, **nie** `kube-prometheus-stack`.
5. **Namespace to `monitoring`**; `persistentVolume.enabled: false`, alertmanager i
   pushgateway wyłączone, node-exporter + kube-state-metrics włączone
   ([prometheus-values.yaml:47-70](../grafana-poc-example/terraform/k8s/prometheus-values.yaml#L47-L70)).
6. **Dashboardów NIE MA w repo.** Potwierdzone: `find ... -name "*.json"` w `terraform/`
   nie zwraca żadnego pliku dashboardu. Dashboardy managed Grafany są konfigurowane poza
   kodem — „dokładną kopię" trzeba najpierw **wyeksportować** z żywej Grafany.
7. **Ważny fakt sieciowy**: prywatna strefa DNS
   `privatelink.westeurope.prometheus.monitor.azure.com` jest **zlinkowana do `vnet-lab`**
   ([dns.tf:23-30](../grafana-poc-example/terraform/dns.tf#L23-L30)), a `pe-amw-a` utrzymuje
   w niej rekord A. Oznacza to, że **pod działający w AKS rozwiązuje FQDN AMW-A na prywatny
   adres PE** — Grafana *wewnątrz klastra* dosięgnie AMW-A prywatnie **bez** żadnego nowego
   Private Endpointu ani MPE.
8. **Konsekwencja tożsamościowa**: self-hosted Grafana nie ma MI Azure Managed Grafany, więc
   auth `msi` z managed świata nie przenosi się 1:1 — trzeba dać jej **własną tożsamość
   Azure** (rekomendacja: UAMI + AKS Workload Identity), albo łączyć się do in-cluster
   Prometheusa bez Azure.
9. Skrypty mają zawsze **dwa warianty** (`.sh` + `.ps1`), logowanie „z otoczenia"
   (`az login`), zero sekretów w kodzie ([providers.tf:28-30](../grafana-poc-example/terraform/providers.tf#L28-L30)).

---

## 2. Tabela porównawcza wariantów metody (Krok 1)

Kolumna „spójność z Prometheusem" ocenia zgodność z istniejącym wzorcem
`prometheus-community/prometheus` instalowanym imperatywnie Helmem w `deploy-k8s.sh`.

| Podejście | Dashboardy-as-code | Secrety | Spójność z obecnym Prometheusem | Koszt utrzymania | Werdykt |
|---|---|---|---|---|---|
| **A. Helm `grafana/grafana`** | Tak — `datasources`, `dashboardProviders`, sidecar/`dashboardsConfigMap` w `values.yaml` | `admin.existingSecret`; datasource bez sekretów (workload identity) | **Wysoka** — ten sam Helm, ten sam `deploy-k8s`, ns `monitoring` | Niski | **REKOMENDOWANY** |
| B. `kube-prometheus-stack` | Tak (wbudowane) | jw. | **Niska** — zastępuje świadomie wybrany `prometheus-community/prometheus`; wciąga operator, CRD, własny scraping — rozjazd z AMW-B `remote_write` i PLS | Średni (migracja) | Odrzucony — sprzeczny z [07: „prometheus, nie stack"](07-design-decisions.md) |
| C. Kustomize | Ręcznie (surowe manifesty/patche) | Ręcznie (Secret/CSI) | Niska — inny mechanizm niż Helm Prometheusa | Wysoki (ręczny YAML Grafany) | Odrzucony dla PoC |
| D. Grafana Operator (CRD `Grafana`, `GrafanaDatasource`, `GrafanaDashboard`) | Bardzo dobre (deklaratywne CRD) | Secret refs w CRD | Średnia — dokłada operator obok Helma Prometheusa (dwa modele) | Średni/wysoki | Dobry kierunek docelowy, przerost dla PoC |
| E. Terraform `helm_release` | Tak (values w Terraform/`templatefile`) | `existingSecret` / KV; unikać plaintext w stanie | Średnia — wymaga migracji też Prometheusa na `helm_release`, providerów helm/kubernetes | Średni | Rozważany jako docelowe uwspólnienie (patrz §3) |
| F. GitOps (Argo CD / Flux) | Najlepsze (repo = stan) | Sealed Secrets / SOPS / KV | Wymaga przeniesienia całości pod GitOps | Wysoki (bootstrap) | Kierunek docelowy, przerost dla PoC |

**Wniosek:** preferencja użytkownika (Helm) jest uzasadniona. `grafana/grafana` daje pełny
provisioning-as-code datasource'ów i dashboardów, a jednocześnie jest **tym samym
narzędziem (Helm) i tym samym wzorcem**, co już działający Prometheus. `kube-prometheus-stack`
odpada, bo świadomie odrzucono go w [07 — Decyzje projektowe](07-design-decisions.md) i
zaburzyłby ścieżki AMW-A/AMW-B/PLS.

---

## 3. Rekomendacja metody + uwspólnienie z Prometheusem (Krok 2)

### 3.1. Rekomendacja jednozdaniowa

**Wdrożyć self-hosted Grafanę chartem `grafana/grafana` z pełnym provisioningiem-as-code
(datasource'y + dashboardy w `values.yaml`/ConfigMap), instalowaną tym samym imperatywnym
Helmem co Prometheus — przez rozszerzony `k8s/deploy-k8s.sh`/`.ps1` — z uwierzytelnianiem do
AMW przez dedykowaną UAMI + AKS Workload Identity, a do self-hosted Prometheusa
bezpośrednio po sieci klastrowej.**

### 3.2. Uwspólnienie: jeden mechanizm dla obu chartów

Wymaganie „wszystkie rzeczy na tym AKS wgrywane tak samo" spełniamy **utrzymując istniejący
wzorzec imperatywnego Helma**, a nie wymieniając go. To najmniejszy rozjazd ze stanem
faktycznym i z [05 — Runbook](05-deployment-runbook.md):

- `deploy-k8s.sh`/`.ps1` pozostaje jedynym punktem instalacji na AKS, ale instaluje **dwa
  release'y w kolejności**: najpierw `prometheus`, potem `grafana` (Grafana zależy od gotowego
  Prometheusa i od endpointów AMW).
- Oba charty mają identyczny cykl: `terraform output` → `sed` placeholderów → `helm upgrade
  --install -n monitoring --wait`. `helm upgrade --install` jest idempotentny — spójne z
  obecną Grafaną-konfiguracją, która też jest idempotentna (kasuj-i-twórz).
- `configure-grafana.sh`/`.ps1` **przestaje być potrzebne dla self-hosted Grafany** —
  datasource'y idą as-code w values. Skrypt zostaje wyłącznie dla *managed* Grafany
  (ona nadal wymaga `az grafana`, bo wyłącza konta usługowe — [07](07-design-decisions.md#dlaczego-data-source-tworzy-skrypt-a-nie-terraform)).

**Alternatywa docelowa (`helm_release` w Terraform, wariant E):** jeśli zespół zechce śledzić
stan i mieć jeden `terraform apply`, migrujemy **oba** charty na `helm_release` z
`depends_on` (Grafana po Prometheusie) i wstrzykiwaniem outputów przez `templatefile`. To
czystsze, ale: (a) wymaga skonfigurowania providerów `helm`+`kubernetes` na AKS, (b)
przenosi też Prometheusa (inaczej znów mamy dwa mechanizmy), (c) trzeba pilnować, by żaden
sekret nie wpadł do stanu w plaintext. **Rekomendacja: zostać przy skryptach teraz** (parytet
z „jak jest"), a `helm_release` potraktować jako świadomy, osobny krok refaktoru całego repo.

### 3.3. Docelowe drzewo katalogów

```
terraform/
  k8s/
    helm/
      prometheus/
        values.yaml              # przeniesione z k8s/prometheus-values.yaml (bez zmian treści)
      grafana/
        values.yaml              # NOWE: datasources + dashboardProviders + sidecar + SA workload-identity
        dashboards/              # NOWE: JSON wyeksportowane z managed Grafany (re-mapowane UID)
          <uid-1>.json
          <uid-2>.json
    deploy-k8s.sh / deploy-k8s.ps1   # rozszerzone: instaluje prometheus, potem grafana
    debug-pod.yaml
  configure-grafana.sh / .ps1        # BEZ ZMIAN — dotyczy już tylko managed Grafany
  grafana-selfhosted.tf              # NOWE (opc.): UAMI + federated credential (lub w rbac.tf/identity.tf)
  ...
```

Wpasowanie w obecną kolejność [05 — Runbook](05-deployment-runbook.md):

```
1. terraform apply         # + UAMI grafany, federated credential, role Data Reader, OIDC/WI na AKS
2. k8s/deploy-k8s.sh        # prometheus  -> potem grafana (oba Helm, jak dziś)
3. configure-grafana.sh     # TYLKO managed Grafana (self-hosted nie potrzebuje)
```

---

## 4. Rozstrzygnięcia techniczne (Krok 3)

### 4.1. Źródła danych — parytet z managed Grafaną

Cel: self-hosted Grafana ma **te same nazwy źródeł** (żeby dashboardy działały) i te same
dane. Ścieżka sieciowa może się różnić — Grafana jest teraz *wewnątrz* klastra.

| Managed (dziś) | Self-hosted (rekomendacja) | Parytet | Uwagi |
|---|---|---|---|
| `AMW-A` (prometheus, MSI, prywatnie przez PE) | `AMW-A` (prometheus, `url=amw_a_query_endpoint`, auth **workloadidentity**) | **1:1 (dane), lepiej (sieć)** | Pod w AKS sam rozwiąże FQDN AMW-A na prywatny PE (strefa DNS zlinkowana do vnet-lab) — prywatnie, bez MPE |
| `AMW-B` (prometheus, MSI, publicznie) | `AMW-B` (prometheus, `url=amw_b_query_endpoint`, auth **workloadidentity**) | **1:1** | Publiczny query endpoint, ta sama rola Data Reader |
| `AzMon-CurrentUser` (Azure Monitor, `currentuser`) | **BRAK 1:1** | ⚠️ zastępnik | `currentuser` propaguje token zalogowanego usera przez Entra OAuth. Bez logowania Entra w self-hosted nie ma „current user". Najbliższy odpowiednik: ten sam typ z auth **workloadidentity/msi** (stała tożsamość) + `Monitoring Reader` na RG — ale to inna semantyka (jedna tożsamość zamiast per-user). Rekomendacja: pominąć lub dodać wariant „ServiceIdentity" i opisać różnicę. |
| `OSS-Prometheus-PLS` (prometheus, MPE→PLS) | `OSS-Prometheus-PLS` (prometheus, `url=http://prometheus-server.monitoring.svc.cluster.local`) | **1:1 (dane), prościej (sieć)** | Grafana w klastrze łączy się z Prometheusem **bezpośrednio** przez Service ClusterIP — MPE i PLS są zbędne. Te same metryki, inna (prostsza) droga. Zachowujemy nazwę i (jeśli trzeba) UID. |

**Auth do AMW — rekomendacja: UAMI + AKS Workload Identity.** To best-practice odpowiednik
MSI managed Grafany:

- Dedykowana `azurerm_user_assigned_identity` (np. `id-grafana-selfhosted`).
- `azurerm_federated_identity_credential` wiążący tę UAMI z OIDC issuerem AKS i kontem
  usługi poda Grafany (`system:serviceaccount:monitoring:grafana`).
- Nadania **lustrzane** do managed: UAMI → `Monitoring Data Reader` na `amw_a` i `amw_b`
  (i opc. `Monitoring Reader` na RG dla Azure Monitor).
- Na AKS: `oidc_issuer_enabled = true`, `workload_identity_enabled = true`.
- Pod Grafany dostaje label `azure.workload.identity/use: "true"`, a SA — adnotację
  `azure.workload.identity/client-id: <UAMI client_id>`. Webhook wstrzyknie
  `AZURE_CLIENT_ID`/`AZURE_TENANT_ID`/`AZURE_FEDERATED_TOKEN_FILE`, a datasource Prometheus
  używa `jsonData.azureCredentials.authType: workloadidentity`.

**Dlaczego nie kubelet MI przez IMDS (jak `remote_write`):** działałoby (`authType: msi`),
ale mieszałoby role (kubelet to tożsamość węzła, nie aplikacji), wymagałoby dania kubeletowi
`Monitoring Data Reader` i jest anty-wzorcem względem Workload Identity. Wspominam jako
fallback „gdyby WI było niedostępne".

**Odejście od [07](07-design-decisions.md):** managed Grafana używa `SystemAssigned` MI;
self-hosted **musi** użyć UAMI + federacji, bo nie istnieje MI Azure Managed Grafany. To
wymuszona różnica, nie zmiana filozofii (nadal zero sekretów, nadal tożsamości zarządzane).

### 4.2. Dashboardy „dokładnie takie same" — eksport, provisioning, re-mapowanie UID

Skoro dashboardów nie ma w repo, „kopia" = **eksport z żywej managed Grafany do repo**,
potem provisioning as-code.

**(a) Eksport** (dołożyć jako `export-dashboards.sh`/`.ps1` albo sekcja w runbooku):

```bash
GRAF=$(terraform output -raw grafana_name); RG=$(terraform output -raw resource_group_name)
mkdir -p k8s/helm/grafana/dashboards
# lista UID dashboardów:
for uid in $(az grafana dashboard list -n "$GRAF" -g "$RG" --query "[].uid" -o tsv); do
  # bierzemy sam model .dashboard, zerujemy id (provisioning nadaje własne):
  az grafana dashboard show -n "$GRAF" -g "$RG" --dashboard "$uid" \
    | jq '.dashboard | .id=null' > "k8s/helm/grafana/dashboards/$uid.json"
done
# zrzut mapowania UID/typów źródeł (do re-mapowania i do ustawienia stałych UID):
az grafana data-source list -n "$GRAF" -g "$RG" \
  --query "[].{name:name,uid:uid,type:type}" -o json > k8s/helm/grafana/datasources-map.json
```

**(b) Provisioning** — sidecar dashboards + ConfigMap z repo (skaluje się, pasuje do wzorca
„sed + kubectl apply"). W `deploy-k8s.sh`:

```bash
kubectl create configmap grafana-dashboards -n monitoring \
  --from-file=k8s/helm/grafana/dashboards/ \
  --dry-run=client -o yaml | kubectl label -f - --local -o yaml \
  grafana_dashboard=1 | kubectl apply -f -
```

a w `values.yaml` włączamy `sidecar.dashboards.enabled: true` z labelem `grafana_dashboard`.
(Alternatywnie `dashboardProviders` + `dashboards:` z inline JSON — gorzej się skaluje.)

**(c) Re-mapowanie UID datasource'ów — kluczowe, inaczej dashboardy będą puste.** Wyeksportowany
JSON odwołuje się do **UID źródeł z managed Grafany**. Dwie drogi (rekomendacja: pierwsza):

1. **Ustawić w provisioningu self-hosted te same UID**, co w managed (z
   `datasources-map.json`) — pole `uid:` w każdej definicji datasource w `values.yaml`.
   Wtedy referencje w dashboardach trafiają 1:1, bez modyfikacji JSON-ów.
2. **Przepisać UID w JSON-ach** `jq`-iem (mapowanie stary→nowy) przy eksporcie, lub
   utemplować przez `__inputs`/zmienną `${datasource}`. Fallback dla twardo zaszytych
   referencji.

**Zgodność wersji:** managed to major **12** — użyć obrazu OSS **Grafana 12.x** (tag obrazu w
`values.yaml` chartu), żeby schema dashboardów i panele były kompatybilne
([07: grafana_major_version=12](07-design-decisions.md)).

### 4.3. Sekrety i konto admina

- **Bez hardcode** w repo/values/stanie. Hasło admina przez `admin.existingSecret` w charcie,
  odwołujące się do Kubernetes Secret **tworzonego poza repo**.
- PoC: `deploy-k8s.sh` tworzy Secret z wartości spoza repo (zmienna środowiskowa lub
  `openssl rand`), np.:
  `kubectl create secret generic grafana-admin -n monitoring --from-literal=admin-user=admin --from-literal=admin-password="$GF_ADMIN_PW" --dry-run=client -o yaml | kubectl apply -f -`.
- Produkcyjnie: **Azure Key Vault + CSI Secrets Store driver** (add-on AKS) montujący hasło —
  to naturalne rozszerzenie modelu „zero sekretów w kodzie" z [04](04-rbac-identity.md).
- **Datasource'y nie mają sekretów** dzięki Workload Identity — duży plus względem
  ewentualnego client-secret.

### 4.4. Ekspozycja / dostęp do UI

Managed Grafana jest publiczna ([07: interfejs zostaje publiczny](07-design-decisions.md)),
ale self-hosted **nie musi** być — i lepiej, by nie była.

- **PoC (rekomendacja): `service.type=ClusterIP` + `kubectl port-forward svc/grafana 3000:80 -n monitoring`.**
  Zero ekspozycji, wystarczy do demo.
- Opcje docelowe: **wewnętrzny LoadBalancer** (ten sam wzorzec adnotacji co PLS Prometheusa,
  [prometheus-values.yaml:36-45](../grafana-poc-example/terraform/k8s/prometheus-values.yaml#L36-L45)),
  albo **Ingress** (kontroler + DNS/TLS).
- **Świadome odejście od parytetu:** UI self-hosted nie jest publiczny. To wzmocnienie
  bezpieczeństwa, a publiczność UI managed nie była celem PoC (prywatyzowano dane, nie UI) —
  zaznaczam jako dopuszczalną różnicę.

### 4.5. Trwałość i HA

- Datasource'y i dashboardy są **prowizjonowane (bezstanowe, w kodzie)** — po restarcie poda
  odtwarzają się same.
- Stanowe są tylko konta/preferencje/annotacje (SQLite). Dla PoC: **1 replika,
  `persistence.enabled: false`** — spójne z Prometheusem
  ([07: Prometheus PV=false](07-design-decisions.md)).
- HA (kilka replik) wymaga zewnętrznej bazy (Postgres/MySQL) — poza zakresem PoC; odnotować.

### 4.6. Uwierzytelnianie użytkowników

- Managed używa logowania Entra ID; odtworzenie tego to Azure AD OAuth w `grafana.ini`
  (`[auth.azuread]`: client id/secret, tenant, `allowed_groups`).
- **PoC: lokalny admin** (prościej, bez app registration — którego środowisko i tak nie może
  tworzyć, [07: usunięty SP](07-design-decisions.md#usunięty-app-registration--sp-s23)).
- Entra OAuth to opcja parytetu, ale wymaga rejestracji aplikacji → dziś niedostępne w tym
  środowisku. Odnotować jako świadomą różnicę (wiąże się z brakiem `AzMon-CurrentUser`, §4.1).

### 4.7. Idempotencja i kolejność

- `helm upgrade --install` (oba charty) + `kubectl apply --dry-run|apply` (ConfigMap, Secret) —
  wszystko idempotentne.
- Twarda kolejność zależności: **AMW/endpointy + Prometheus muszą istnieć zanim wstanie
  Grafana**. Egzekwujemy ją sekwencją w `deploy-k8s.sh` (prometheus `--wait`, potem grafana)
  oraz walidacją niepustych outputów `sed`-owanych do values — dokładnie jak istniejące
  guardy dla `remote_write` ([07: twarda walidacja](07-design-decisions.md#twarda-walidacja-pustych-wartości-w-deploy-k8ssh)).

---

## 5. Plan wdrożenia krok-po-kroku (pliki do dodania/zmiany)

Kolejność i punkty ryzyka. **Nie implementujemy tu — to plan.**

### Krok A — Terraform: tożsamość i RBAC dla self-hosted Grafany

1. **`aks.tf`** — włączyć OIDC/Workload Identity na klastrze:
   `oidc_issuer_enabled = true`, `workload_identity_enabled = true`.
   ⚠️ *Ryzyko:* zmiana na istniejącym klastrze; zweryfikować, że nie wymusza recreate
   (dla `azurerm` to zmiany in-place, ale zaplanować `terraform plan`).
2. **`grafana-selfhosted.tf`** (nowy) lub dopisać do `identity.tf`/`rbac.tf`:
   - `azurerm_user_assigned_identity "grafana_selfhosted"`,
   - `azurerm_federated_identity_credential` (issuer = `aks.oidc_issuer_url`, subject =
     `system:serviceaccount:monitoring:grafana`, audience `api://AzureADTokenExchange`),
   - role: `Monitoring Data Reader` na `amw_a` i `amw_b` (lustrzane do
     [rbac.tf:15-25](../grafana-poc-example/terraform/rbac.tf#L15-L25)); opc.
     `Monitoring Reader` na RG.
3. **`outputs.tf`** — dodać: `grafana_uami_client_id`
   (`...grafana_selfhosted.client_id`) do wstrzyknięcia w SA; `aks_oidc_issuer_url` (pomocniczo).
   Endpointy AMW (`amw_a_query_endpoint`, `amw_b_query_endpoint`) już są.

### Krok B — Helm values i struktura k8s

4. **Utworzyć `k8s/helm/`**, przenieść `k8s/prometheus-values.yaml` →
   `k8s/helm/prometheus/values.yaml` (treść bez zmian). ⚠️ *Ryzyko:* zaktualizować ścieżkę w
   `deploy-k8s.sh`/`.ps1`.
5. **`k8s/helm/grafana/values.yaml`** (nowy) — szkic §6: obraz 12.x, SA + workload identity,
   `admin.existingSecret`, `persistence.enabled=false`, `datasources.yaml` (AMW-A/AMW-B/OSS
   z ustawionymi UID), `sidecar.dashboards`, `service.type=ClusterIP`, `grafana.ini [azure]
   workload_identity_enabled=true`.
6. **`k8s/helm/grafana/dashboards/*.json`** — wyeksportowane i re-mapowane dashboardy (§4.2).

### Krok C — Skrypty (oba warianty)

7. **`deploy-k8s.sh` i `deploy-k8s.ps1`** — rozszerzyć:
   - po instalacji Prometheusa dodać: utworzenie Secret admina (§4.3), ConfigMap dashboardów
     (§4.2b), `sed` placeholderów do kopii `grafana/values.yaml`
     (`PLACEHOLDER_AMW_A_QUERY_ENDPOINT`, `PLACEHOLDER_AMW_B_QUERY_ENDPOINT`,
     `PLACEHOLDER_GRAFANA_UAMI_CLIENT_ID`), `helm upgrade --install grafana grafana/grafana
     -n monitoring --wait`;
   - dodać `helm repo add grafana https://grafana.github.io/helm-charts`;
   - zachować guardy „niepusta wartość" dla nowych outputów.
   ⚠️ *Ryzyko:* parytet `.sh`/`.ps1` — obie wersje muszą być zaktualizowane identycznie
   (konwencja repo).
8. **`export-dashboards.sh`/`.ps1`** (nowy, opc.) — jednorazowy eksport z managed Grafany (§4.2a).

### Krok D — Dokumentacja i weryfikacja

9. **`README.pl.md`** i [05 — Runbook](05-deployment-runbook.md) — dopisać, że
   `deploy-k8s` stawia teraz Prometheusa **i** Grafanę; `configure-grafana` dotyczy tylko
   managed.
10. **Weryfikacja** (checklista): pod `grafana` Running w ns `monitoring`; w UI „Test" na
    `AMW-A`/`AMW-B` przechodzi (workload identity → Data Reader); `OSS-Prometheus-PLS`
    odpowiada z `prometheus-server`; dashboardy renderują dane (poprawne UID); z poda Grafany
    `getent hosts <amw-a-fqdn>` zwraca adres z `10.10.1.0/24` (prywatny PE).

**Główne punkty ryzyka:** (1) re-mapowanie UID datasource'ów — najczęstsza przyczyna
„pustych" dashboardów; (2) włączenie WI na istniejącym AKS (`plan` przed `apply`);
(3) propagacja RBAC (Data Reader) — „Test" może chwilę zwracać 403 zanim rola się rozejdzie;
(4) parytet obu wariantów skryptów.

---

## 6. Szkice kodu (ilustracja, nie implementacja)

**UAMI + federacja + role (Terraform, skrót):**

```hcl
resource "azurerm_user_assigned_identity" "grafana_selfhosted" {
  name = "id-grafana-selfhosted"; resource_group_name = azurerm_resource_group.rg.name
  location = var.location; tags = local.tags
}
resource "azurerm_federated_identity_credential" "grafana" {
  name = "fic-grafana"; resource_group_name = azurerm_resource_group.rg.name
  parent_id = azurerm_user_assigned_identity.grafana_selfhosted.id
  issuer   = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject  = "system:serviceaccount:monitoring:grafana"
  audience = ["api://AzureADTokenExchange"]
}
resource "azurerm_role_assignment" "grafana_sh_reader_amw_a" {
  scope = azurerm_monitor_workspace.amw_a.id
  role_definition_name = "Monitoring Data Reader"
  principal_id = azurerm_user_assigned_identity.grafana_selfhosted.principal_id
}
# analogicznie amw_b
```

**`k8s/helm/grafana/values.yaml` (skrót):**

```yaml
image:
  tag: "12.1.0"                      # parytet z managed major 12
serviceAccount:
  create: true
  name: grafana
  annotations:
    azure.workload.identity/client-id: "PLACEHOLDER_GRAFANA_UAMI_CLIENT_ID"
podLabels:
  azure.workload.identity/use: "true"
admin:
  existingSecret: grafana-admin       # tworzony przez deploy-k8s.sh, NIE w repo
persistence: { enabled: false }
replicas: 1
service: { type: ClusterIP }
grafana.ini:
  azure: { workload_identity_enabled: true, cloud: AzureCloud }
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: AMW-A
        uid: <UID-z-managed>          # z datasources-map.json → parytet z dashboardami
        type: prometheus
        url: "PLACEHOLDER_AMW_A_QUERY_ENDPOINT"
        jsonData: { httpMethod: POST, azureCredentials: { authType: workloadidentity } }
      - name: AMW-B
        uid: <UID-z-managed>
        type: prometheus
        url: "PLACEHOLDER_AMW_B_QUERY_ENDPOINT"
        jsonData: { httpMethod: POST, azureCredentials: { authType: workloadidentity } }
      - name: OSS-Prometheus-PLS       # ta sama nazwa; w klastrze łączymy się wprost
        uid: <UID-z-managed>
        type: prometheus
        url: "http://prometheus-server.monitoring.svc.cluster.local"
        jsonData: { httpMethod: POST }
      # AzMon-CurrentUser: brak odpowiednika 1:1 — patrz §4.1
sidecar:
  dashboards: { enabled: true, label: grafana_dashboard, folder: /tmp/dashboards }
```

**Eksport dashboardów** — patrz §4.2a.

---

## 7. Otwarte pytania / decyzje do potwierdzenia

1. **Zakres parytetu `AzMon-CurrentUser`.** Pomijamy to źródło w self-hosted, czy dodajemy
   zastępnik z auth `workloadidentity`/`msi` (inna semantyka niż „current user")?
2. **Logowanie użytkowników i mapowanie grup Entra → role/foldery.** To najbardziej
   krytyczny obszar — analiza w osobnym dokumencie
   [09 — model dostępu (grupy Entra)](09-selfhosted-rbac-entra-model.md). W skrócie: parytet
   wymaga **rejestracji aplikacji** (dziś niedostępna,
   [07](07-design-decisions.md#usunięty-app-registration--sp-s23)) **oraz licencji Grafana
   Enterprise** (team sync). Bez app-reg brak logowania Entra i mapowania grup; bez Enterprise
   model per-folderowy degraduje się do globalnych ról. Potwierdzić oba.
3. **Mechanizm uwspólnienia — teraz vs docelowo.** Zostajemy przy imperatywnym Helmie w
   `deploy-k8s.sh` (rekomendacja), czy od razu migrujemy oba charty na `helm_release` w
   Terraform (większy refaktor, też Prometheus)?
4. **Ekspozycja UI.** ClusterIP + port-forward (PoC) akceptowalne, czy potrzebny wewnętrzny
   LB / Ingress od razu?
5. **Włączenie Workload Identity na istniejącym AKS.** Zgoda na `oidc_issuer_enabled` +
   `workload_identity_enabled` (zweryfikować `plan`, że nie ma recreate klastra)?
6. **Trwałość.** Potwierdzić 1 replika + `persistence=false` (spójne z Prometheusem), czy PVC
   dla users/prefs?
7. **UID datasource'ów.** Ustawiamy stałe UID = te z managed (rekomendacja), czy re-mapujemy
   JSON-y `jq`-iem? Zależy od tego, jak wyglądają realne referencje w wyeksportowanych
   dashboardach (do sprawdzenia po eksporcie).
8. **Retencja PLS/MPE.** Czy `OSS-Prometheus-PLS` w *managed* Grafanie zostaje (demo S1.6),
   podczas gdy self-hosted łączy się in-cluster? Zakładam „tak" — to dwa różne konsumenci.
```
