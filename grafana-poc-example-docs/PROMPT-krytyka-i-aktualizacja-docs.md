# PROMPT: krytyka + krzyżowa weryfikacja + aktualizacja całej dokumentacji grafana-poc-example-docs

> Prompt do odpalenia na subagencie z dostępem do sieci (WebSearch/WebFetch) i do plików repo.
> Dwie fazy: **(1)** konstruktywna krytyka każdego pliku, **(2)** na jej podstawie krzyżowa
> weryfikacja i **nadpisanie** plików tak, by całość była rzetelna, sprawdzona i spójna.

---

## Rola i cel

Jesteś recenzentem technicznym (observability: Grafana/Loki/Mimir/Tempo, Azure/AKS, Terraform,
RBAC) **oraz** redaktorem. Masz **skrytykować, zweryfikować i naprawić** całą dokumentację w
`/Users/artur.prawdzik/repo/sync/grafana-poc-example-docs`. Efekt końcowy: pliki **rzetelne
(każde istotne twierdzenie sprawdzone lub jawnie oznaczone jako szacunek/opinia), spójne
LOGICZNIE i merytorycznie, bez sprzeczności.**

## PRIORYTET #1 — spójność LOGICZNA (nie kosmetyczna)

Najważniejsza jest **spójność logiczna i merytoryczna**, nie porządki formalne. To znaczy:
- **wnioski wynikają z przesłanek** (brak nieuzasadnionych skoków, „hand-wavingu", błędnych
  sylogizmów); rekomendacje wynikają z faktów podanych w dokumentach;
- **te same tezy dają te same wnioski w każdym dokumencie** — żaden plik nie może przeczyć
  drugiemu (ani sam sobie);
- **łańcuchy warunkowe i decyzyjne stosowane identycznie wszędzie** (np. „jeśli logi wymagają
  izolacji → Enterprise/LBAC lub multi-org; jeśli nie → OSS"); progi, warunki i „to zależy od X"
  nie mogą się różnić między plikami;
- **kluczowe zastrzeżenia stosowane konsekwentnie** tam, gdzie zmieniają wniosek (np. LBAC
  fail-open, izolacja sieci backendów, Mimir nie scrapuje, Loki nie obsługuje metryk/traces jako
  DS, tenant vs organizacja Grafany, `X-Scope-OrgID` nie znika w Enterprise) — nie może być tak,
  że zastrzeżenie jest w jednym pliku, a w drugim wniosek je ignoruje;
- **diagramy zgodne z tekstem** (model przepływu, kto ustawia/egzekwuje `X-Scope-OrgID`, model
  zaufania) — diagram nie może przeczyć opisowi;
- **wniosek oparty na szacunku nie jest podawany jako pewnik.**

Numeracja, linki, terminologia i styl są **ważne, ale drugorzędne** — porządkujesz je *po* tym,
jak zapewnisz spójność logiczną i faktograficzną. Nie poświęcaj poprawności merytorycznej dla
kosmetyki; jeśli „ładny" opis jest logicznie błędny — priorytetem jest naprawić logikę.

## Zakres

- **Do recenzji i NADPISANIA:** wszystkie `*.md` w `grafana-poc-example-docs/`:
  `01-architecture`, `02-metrics-flow`, `03-networking-dns`, `04-rbac-identity`,
  `05-deployment-runbook`, `06-scenarios`, `07-design-decisions`,
  `08-self-hosted-grafana-analysis`, `09-selfhosted-rbac-entra-model`,
  `10-grafana-licencje-koszty-oss-reconciler`, `11-granulacja-uprawnien-warianty`,
  `12-reconciler-architektura-mechanizmy`, `13-loki-wplyw-na-self-hosted-i-izolacje`,
  `14-alternatywy-dla-grafany-rbac`, `15-dyskusja-ze-mna-na-temat-wyboru-narzedzi`,
  `16-rbac-grafana-oss-vs-enterprise-organizacje`, `README.md`.
- **Poza zakresem — ArgoCD/GitOps jako temat wiodący:** dokument o ArgoCD został **świadomie
  usunięty**. **Nie** traktuj jego braku jako luki, **nie** przywracaj analizy ArgoCD, **nie**
  rozbudowuj wątku GitOps. Pojedyncze, ogólne wzmianki „GitOps (Argo CD / Flux)" w tabelach metod
  wdrożenia (np. w `08`, `14`) mogą zostać, jeśli są trafne — ale bez rozwijania.
- **Artefakty procesowe** (`ANALYSIS_PROMPT.md`, `PROMPT-*.md`, w tym ten plik) — uwzględnij w
  krytyce **tylko** pod kątem, czy zawierają błędy faktograficzne wprowadzające w błąd; **nie
  przepisuj** ich stylistycznie. Nie usuwaj.
- **Źródła prawdy read-only (NIE nadpisuj):** kod Terraform w
  `/Users/artur.prawdzik/repo/sync/grafana-poc-example/terraform`, wzorzec RBAC w
  `/Users/artur.prawdzik/repo/managed_grafana_internal`, oraz materiały ze spotkania w
  `/Users/artur.prawdzik/repo/sync` (`transkrybcja`, `podsumowanie_spotkania.md`,
  `jak_loki_zmienilby_drzewo_RBAC.md`, `pytania_do_zespołu.md`). Używaj ich do **weryfikacji
  krzyżowej** twierdzeń w docs; jeśli docs są z nimi sprzeczne — popraw docs (albo, gdy to docs
  mają rację, odnotuj rozjazd w krytyce, nie ruszając plików źródłowych).

## Zasady nadrzędne (twarde)

1. **Weryfikuj, nie zgaduj.** Każde istotne twierdzenie produktowe (funkcja/edycja/wersja/limit/
   cena) potwierdź w **autorytatywnym źródle** (docs Grafana/Loki/Mimir/Tempo/Azure, oficjalne
   repo) i podaj **URL + datę dostępu**. Twierdzenia repo-specyficzne potwierdź, **czytając kod**
   (`.tf`) / transkrypcję / `managed_grafana_internal`.
2. **Nie zmyślaj — zwłaszcza cen.** Gdy cena jest „contact sales" / nieznana, napisz to wprost.
   Rozdzielaj jawnie: **fakt (ze źródłem)** / **szacunek (oznaczony)** / **opinia-rekomendacja**.
3. **Zachowaj intencję i wartość.** To naprawa, nie kasowanie. Nie gub trafnych treści; usuwaj/
   poprawiaj tylko to, co błędne, nieaktualne, sprzeczne lub mylące.
4. **Po polsku**, z zachowaniem konwencji serii: nagłówek nawigacyjny
   (`[◄ ...](poprz.md) · [README ►](README.md)`), diagramy Mermaid, odnośniki do kodu w formacie
   ścieżek względnych, sekcja „Źródła" z URL+datą tam, gdzie są twierdzenia do potwierdzenia.
5. **Data odniesienia: 2026-07-21.** Sprawdzaj aktualność (wersje, deprecacje, cenniki).

## Faza 1 — konstruktywna krytyka każdego pliku

Najpierw **przeczytaj każdy plik w całości.** Dla **każdego** utwórz wpis krytyki zawierający:

- **Co zawiera** (2–4 zdania: cel, kluczowe tezy).
- **Co jest dobre** (mocne strony, trafne ujęcia).
- **Błędy i ryzyka** — konkretnie, z cytatem/linią i **dowodem**:
  - *faktograficzne* (nieprawda / przestarzałe / zła wersja/edycja/limit),
  - *nieuprawnione* (twierdzenie bez źródła, szacunek podany jak fakt, cena zmyślona),
  - *logiczne/rozumowanie* (**priorytet**: wniosek nie wynika z przesłanek, nieuprawniony skok,
    sprzeczność w obrębie pliku, rekomendacja niespójna z podanymi faktami, diagram niezgodny z
    tekstem, wniosek ze szacunku podany jak pewnik),
  - *repo-rozjazd* (sprzeczność z kodem `.tf` / transkrypcją / `managed_grafana_internal`).
- **Braki** (czego istotnego brakuje, jakie zastrzeżenie pominięto).
- **Rekomendowane zmiany** (konkretnie, co i jak poprawić).

Zapisz to jako **`REVIEW-krytyka.md`** w katalogu docs (osobny plik, nie nadpisuj nim niczego).

## Faza 1b — weryfikacja KRZYŻOWA (spójność między plikami)

W `REVIEW-krytyka.md` dodaj sekcję „Spójność całości". **Kolejność ważności: najpierw logika,
potem fakty/liczby, na końcu porządki formalne.**

**A. Spójność LOGICZNA i rekomendacji (NAJWAŻNIEJSZE):**
- **Brak sprzeczności tez między plikami** — to samo twierdzenie nie może prowadzić do różnych
  wniosków w różnych dokumentach; żaden plik nie przeczy drugiemu.
- **Łańcuchy warunkowe/decyzyjne identyczne wszędzie** — np. „datasource permissions/LBAC/team
  sync/custom roles = Enterprise" i wynikające z tego „izolacja per tenant w OSS = tylko
  multi-org" muszą brzmieć i **prowadzić do tych samych wniosków** w 04/05/09/11/12/13/16;
  definicja docelowego stacku (kolektory→backendy→Grafana, `X-Scope-OrgID`) identyczna w 13/15/16;
  model zaufania (backend ufa nagłówkowi → izolacja sieci) spójny wszędzie.
- **Zastrzeżenia stosowane konsekwentnie** — LBAC fail-open, izolacja sieci backendów, Mimir nie
  scrapuje, Loki nie jest DS metryk/traces, tenant vs organizacja, `X-Scope-OrgID` nie znika w
  Enterprise: jeśli zastrzeżenie zmienia wniosek w jednym miejscu, nie może być pominięte w innym.
- **Rekomendacje wynikają z faktów** i nie zakładają czegoś, co inny (lub ten sam) dokument obala.
- **Diagramy zgodne z opisem** i ze sobą nawzajem.

**B. Spójność faktów/liczb/wersji** (fundament pod logikę) — te same wartości wszędzie:
`org_mapping` (OSS, od której wersji), foldery zagnieżdżone (OSS, od której), team sync /
datasource permissions / LBAC / fixed+custom roles (Enterprise/Cloud), Promtail (deprecacja/EOL),
Loki OTLP, Mimir (multi-tenancy, **licencja**, rodowód Cortex, brak scrapingu), Tempo
(`X-Scope-OrgID`), progi kosztowe (break-even userów — jako **szacunek**), limit reguł LBAC,
cenniki Cloud/Azure Managed. **Jedna wartość — jedna liczba we wszystkich plikach.**

**C. Zgodność z ustaleniami spotkania** — twierdzenia „za spotkaniem" zgodne z `transkrybcja`
(cytuj numery linii): RBAC to wzorzec multi-org całego stosu (nie „funkcja Lokiego"), koncesja
„metryki dla wszystkich", ślady/Tempo nieomówione, Loki bez row-level security.

**D. Porządki formalne (DRUGORZĘDNE — dopiero po A–C):** jednolita terminologia (AMW, DCR,
PLS/MPE, `X-Scope-OrgID`, tenant vs organizacja, basic/fixed/custom roles, LBAC); działające
linki i odnośniki `§`; spójny łańcuch nawigacji 01→16 bez sierot; brak luk/duplikatów numeracji;
brak rozjazdów w powtórzonych opisach tego samego faktu.

## Hotspoty faktograficzne — potwierdź u źródła (lista minimalna)

Zweryfikuj (URL + data) i popraw, jeśli w docs inaczej:
1. `org_mapping` w OSS i od której wersji Grafany; czy mapuje na org+rola.
2. Foldery zagnieżdżone (subfolders) — edycja/wersja GA; uprawnienia folderów we wszystkich
   edycjach; kaskadowanie.
3. **Team sync, datasource permissions, LBAC, fixed+custom roles = Enterprise/Cloud** (nie OSS).
4. LBAC: obejmuje logi i metryki; limit reguł na DS; zachowanie **fail-open** (brak reguły =
   pełny dostęp).
5. Loki: brak row/index-level security w OSS; `X-Scope-OrgID`; **Promtail** deprecacja/EOL; OTLP
   natywnie w Loki 3.x; LogQL metric queries (metryki z logów) i derived fields (link do Tempo).
6. Mimir: multi-tenancy `X-Scope-OrgID`; **licencja AGPLv3**; rodowód (fork Cortex); ruler per-
   tenant (i jego ograniczenia); brak scrapingu (tylko `remote_write`).
7. Cortex/Thanos: multi-tenancy (pierwszoklasowa vs dodatek), licencje (Apache 2.0), nagłówek
   Thanos vs `X-Scope-OrgID`.
8. Tempo: `multitenancy_enabled`, `X-Scope-OrgID` na zapisie i odczycie.
9. Kolektory: Alloy = dystrybucja OTel Collectora; Vector — brak realnej obsługi traces; footprint
   Alloy vs OTel (jakościowo — **bez zmyślania liczb MB/RAM**); custom-build OTel (OCB).
10. `grafana-oss-team-sync`: istnienie, licencja (GPL-3.0), zakres (teamy/userzy/foldery), auth do
    Grafany (token vs basic), auth do Graph (uprawnienia), wersja min. Grafany.
11. Koszty w `10-*`: Grafana Cloud (plany, per aktywny user), Azure Managed Grafana (SKU + per
    user), Grafana Enterprise self-managed (**„contact sales" — bez zmyślonej kwoty**); wszystkie
    progi/break-eveny jawnie jako **szacunki**.
12. Repo (`08-16` i `01-07`): AMW-A/B, DCR-A/B, PLS/MPE, `monitor_metrics{}`, brak dashboardów w
    repo, blocker app-registration (`identity.tf`), rekomendacja Workload Identity — **potwierdź
    czytając kod**.

## Faza 2 — aktualizacja i NADPISANIE plików

Na podstawie krytyki i weryfikacji **popraw i nadpisz** pliki w `grafana-poc-example-docs/`:

- Wprowadź poprawki faktograficzne; ujednolić liczby/wersje/terminologię w całej serii.
- Uzupełnij brakujące **sekcje „Źródła" (URL + data)** wszędzie, gdzie padają twierdzenia
  produktowe. Oznacz szacunki i „contact sales".
- Usuń/rozwiąż sprzeczności; napraw linki i odnośniki `§`; napraw łańcuch nawigacji.
- **Zaktualizuj `README.md`** (indeks obejmuje wszystkie istniejące dokumenty `01`–`16`, w
  poprawnej kolejności, z trafnymi opisami); usuń z indeksu ewentualne wpisy do nieistniejących
  plików (w tym do usuniętego ArgoCD, jeśli gdzieś został).
- Zachowaj konwencje, styl i wartościowe treści. Diagramy Mermaid popraw, jeśli są błędne
  merytorycznie lub składniowo.
- **Nie** zmieniaj plików źródłowych (terraform, transkrypcja, `managed_grafana_internal`,
  `jak_loki_zmienilby_drzewo_RBAC.md`, `pytania_do_zespołu.md`).

Na końcu dodaj do `REVIEW-krytyka.md` sekcję **„CHANGELOG"** — per plik, zwięźle: co zmieniono i
dlaczego (z odniesieniem do zweryfikowanego źródła). Wszystko, czego **nie** dało się potwierdzić,
wypisz w sekcji **„Do potwierdzenia przez człowieka"** (zamiast usuwać lub zgadywać).

## Metoda i narzędzia

- **WebSearch/WebFetch** — fakty produktowe (docs/oficjalne repo). Każdy → URL + data.
- **Read/Grep** — kod `.tf`, transkrypcja, `managed_grafana_internal` (twierdzenia repo/spotkania).
- Pracuj **plik po pliku** w Fazie 1, potem **przekrojowo** (1b), potem edytuj (Faza 2).
- Zmiany rób **konserwatywnie i atomowo** (edycje, nie hurtowe przepisywanie od zera, chyba że
  plik jest fundamentalnie błędny — wtedy odnotuj to w CHANGELOG).

## Kryteria akceptacji (definicja „gotowe")

- **(najważniejsze) Spójność logiczna:** zero sprzeczności między dokumentami i wewnątrz nich;
  wnioski wynikają z przesłanek; łańcuchy warunkowe i zastrzeżenia stosowane identycznie wszędzie;
  rekomendacje zgodne z faktami; diagramy zgodne z tekstem.
- **Rzetelność:** brak twierdzeń niepotwierdzonych bez etykiety (fakt/szacunek/opinia); sekcja
  „Źródła" tam, gdzie trzeba; żadna cena nie została zmyślona; fakty/liczby/wersje jednolite.
- `REVIEW-krytyka.md` zawiera: krytykę per plik, sekcję spójności (A–D), CHANGELOG, „Do potwierdzenia".
- Żaden plik źródłowy (read-only) nie został zmieniony.
- **(drugorzędne) Porządki:** terminologia jednolita; linki i odnośniki `§` działają; nawigacja
  01→16 spójna, bez sierot; README kompletny.

## Na koniec zwróć

Ścieżkę `REVIEW-krytyka.md`, listę nadpisanych plików, 5–10 najważniejszych wykrytych i
naprawionych błędów/niespójności, oraz listę „Do potwierdzenia przez człowieka".
