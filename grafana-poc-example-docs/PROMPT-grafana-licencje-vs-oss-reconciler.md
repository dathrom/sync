# PROMPT (subagent): Grafana Enterprise/Cloud vs OSS — koszty + OSS reconciler dla team sync

> Prompt do odpalenia na subagencie z dostępem do wyszukiwania w sieci. Rozwija wątek z
> [09 — Model dostępu (grupy Entra)](09-selfhosted-rbac-entra-model.md) §4 (blocker: team sync
> = Enterprise). Cel: policzyć koszty licencji vs OSS i przeanalizować wariant „OSS + własny
> reconciler" (jak zrobić, jakie gotowe narzędzia istnieją).

---

## Rola i cel

Jesteś inżynierem platformy + analitykiem kosztów. Masz **rozstrzygnąć dylemat licencyjny**
dla self-hosted Grafany na AKS w projekcie
`/Users/artur.prawdzik/repo/sync/grafana-poc-example` i dostarczyć **twardą analizę
koszt/korzyść**: kiedy opłaca się **Grafana Enterprise / Grafana Cloud**, a kiedy **OSS +
własny mechanizm synchronizacji** grup Entra na uprawnienia.

Kontekst (przeczytaj najpierw): dokumenty
`/Users/artur.prawdzik/repo/sync/grafana-poc-example-docs/08-self-hosted-grafana-analysis.md`
i `.../09-selfhosted-rbac-entra-model.md` oraz model źródłowy w
`/Users/artur.prawdzik/repo/managed_grafana_internal` (zwłaszcza `02-grafana-config`:
`rbac_input.csv`, `teams.tf`, `folders.tf` — model grupa Entra → team → uprawnienia
View/Edit/Admin na podfolderze systemu/środowiska).

**Kluczowy fakt wyjściowy do zweryfikowania i doprecyzowania:** granularny, per-folder model
z `rbac_input.csv` opiera się na **team sync** (`grafana_team_external_group`), który jest
funkcją **Grafana Enterprise / Cloud**, nie OSS. To jest sedno decyzji.

## Część A — analiza kosztów (wymaga wyszukania aktualnych cen)

Zbadaj i porównaj (podawaj **źródła/URL i datę**, oznaczaj wyraźnie, co jest „contact sales" /
niepubliczne / szacunkowe):

1. **Grafana OSS** — licencja (Apache 2.0, darmowa). Policz **realny koszt = nakład
   inżynierski**: budowa i utrzymanie reconcilera (część B), ryzyko, dług operacyjny.
2. **Grafana Enterprise (self-managed)** — model cennika (per użytkownik? per aktywny
   użytkownik? minimum? roczny kontrakt? „contact sales"?), co dokładnie odblokowuje istotnego
   tutaj (team sync, RBAC fine-grained, reporting, wsparcie). Jak liczą „aktywnych
   użytkowników".
3. **Grafana Cloud** — tiery (Free / Pro / Advanced), model per aktywny użytkownik +
   zużycie (metryki/logi), co zawiera team sync/SSO, limity. Zwróć uwagę: Cloud to Grafana
   *hostowana* — skonfrontuj z wymaganiem „self-hosted na AKS" (czy Cloud w ogóle spełnia
   założenia projektu, czy to inny model wdrożenia).
4. **Azure Managed Grafana (punkt odniesienia)** — koszt obecnego rozwiązania (per instancja +
   per aktywny użytkownik, SKU Essential/Standard). Po to, by porównać „ile kosztuje dziś" vs
   „ile kosztowałoby self-hosted Enterprise/OSS". Sprawdź aktualny cennik Azure.
5. **Tabela decyzyjna**: dla scenariuszy (np. 20 / 100 / 500 użytkowników, X systemów/RA)
   podaj przybliżony roczny koszt każdej opcji (licencja + szacowany nakład inżynierski dla
   OSS) i **próg opłacalności** — od ilu użytkowników/systemów Enterprise/Cloud bije OSS+reconciler.

> Ceny Grafany bywają „contact sales". Gdy brak publicznej ceny — powiedz to wprost, podaj co
> jest znane (widełki z publicznych źródeł, kalkulatory, oferty marketplace) i zaznacz jako
> szacunek do potwierdzenia z sales. **Nie zmyślaj konkretnych kwot.**

## Część B — wariant „OSS + własny reconciler" (jak to zrobić, czym)

1. **Na czym polega luka.** Wyjaśnij precyzyjnie, czego OSS *nie* ma (team sync), a co *ma* i
   można wykorzystać: `[auth.azuread]`/`[auth.generic_oauth]` z `role_attribute_path` i
   **`org_mapping`** (mapowanie grup na org+rola — od której wersji, co dokładnie potrafi),
   JIT user provisioning przy logowaniu OAuth, uprawnienia folderów per team/rola przez API.
2. **Warianty architektury zamknięcia luki** — opisz i porównaj co najmniej:
   - **(a) Reconciler grup→teamów**: usługa/CronJob w AKS czyta członkostwo grup z **Microsoft
     Graph** i przez **Grafana HTTP API** synchronizuje `teams` + membership + folder
     permissions wg modelu z `rbac_input.csv`. Problem „user musi istnieć w Grafanie" (JIT
     dopiero po pierwszym logowaniu) — jak go rozwiązać.
   - **(b) Multi-org + `org_mapping` (OSS!)**: każdy system/RA = osobna organizacja Grafany,
     grupy Entra mapowane na org+rola przez `org_mapping` w grafana.ini — **bez** reconcilera i
     **bez** Enterprise. Oceń wady (izolacja per-org, duplikacja dashboardów/DS między orgami,
     UX przełączania orgów, brak współdzielenia).
   - **(c) Terraform provider `grafana` jako reconciler stanu** — czy i jak `grafana_team` +
     membership da się utrzymywać deklaratywnie w OSS (ograniczenia: membership po user id, nie
     po grupie).
3. **Gotowe narzędzia — research (podaj URL, gwiazdki/aktywność, licencję, status utrzymania):**
   poszukaj istniejących projektów OSS do synchronizacji Entra/AAD/LDAP → teamy/uprawnienia
   Grafany (np. społecznościowe „grafana sync", operatory, skrypty Graph→Grafana API),
   **Grafana Operator** (grafana-operator/grafana-operator — czy `GrafanaTeam`/uprawnienia i
   czy ogarnia team sync w OSS), oraz czy Grafana ma to na roadmapie/w OSS w nowszych wersjach.
   Dla każdego: czy realnie rozwiązuje problem, dojrzałość, ryzyko porzucenia.
4. **Jeśli budować własny** — naszkicuj: język/stack, gdzie działa (CronJob w ns `monitoring`),
   tożsamość do Graph (Workload Identity — spójnie z [08 §4.1]), idempotencja, obsługa
   „group overage" (>200 grup), usuwanie dostępu (deprovisioning), obserwowalność, tryb
   dry-run, źródło prawdy = `rbac_input.csv`. **Oszacuj nakład** (roboczodni na budowę +
   utrzymanie/rok) i ryzyka (dryf, rate-limit Graph/Grafana, bezpieczeństwo tokenu).

## Zasady

- Pisz **po polsku**, spójnie z terminologią docs (AMW, DCR, team sync, `rbac_input.csv`,
  RA/system/environment, View/Edit/Admin).
- Rozdzielaj **fakty ze źródłem** od **szacunków**. Każda cena/twierdzenie o feature „tylko
  Enterprise" — z URL i datą dostępu. Wersje Grafany, w których coś się zmieniło (np.
  `org_mapping`), podawaj konkretnie.
- Nie rekomenduj Cloud, jeśli łamie wymaganie „self-hosted na AKS" — chyba że wyraźnie jako
  alternatywę z konsekwencjami.
- Zakończ **jednoznaczną rekomendacją warunkową** („jeśli >N userów lub >M systemów →
  Enterprise; w PoC/małej skali → OSS + multi-org lub reconciler, bo…").

## Wymagane wyjście

Dokument z sekcjami: (1) streszczenie decyzji w 5 zdaniach; (2) tabela kosztów opcji +
tabela progów opłacalności wg skali; (3) analiza „OSS + reconciler": luka, warianty
architektury (a/b/c), przegląd gotowych narzędzi z URL, szkic własnego rozwiązania + nakład;
(4) rekomendacja warunkowa; (5) otwarte pytania (w tym co potwierdzić z Grafana sales i ile
realnie jest użytkowników/systemów/RA). Fragmenty konfiguracji (`org_mapping`, przykładowy
zarys reconcilera) zwięźle, jako ilustracja.

**Zapisz wynik jako** `/Users/artur.prawdzik/repo/sync/grafana-poc-example-docs/10-grafana-licencje-koszty-oss-reconciler.md`
(kontynuacja serii 01–09; dodaj nagłówek nawigacyjny i dopisz pozycję w README.md tej serii).
