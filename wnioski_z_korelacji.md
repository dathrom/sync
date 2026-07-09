# Wnioski z korelacji — zarządzanie RBAC na Azure Managed Grafana

> **Co koreluję:** analizę repo `managed_grafana_internal` (model CSV → RBAC w Grafanie)
> z [podsumowaniem spotkania](podsumowanie_spotkania.md) o budowie platformy observability.
> **Założenie ramowe:** Azure Managed Grafana to **etap przejściowy**; to repo zarządza
> uprawnieniami na niej *teraz*. Docelowo zespół idzie w self-hosted Grafanę na AKS.
> **Fokus:** wyłącznie zarządzanie RBAC.

---

## TL;DR

Spotkanie nie zmienia słuszności tego repo na etapie przejściowym — ale nakłada na model
CSV→RBAC **cztery wymagania projektowe**, jeśli ma przetrwać migrację do self-hosted:
1. **Warstwa team/folder RBAC (to repo) jest jedyną realną dźwignią granularności** na Managed
   Grafanie — bo RBAC per użytkownik na data source trzeba poświęcić na rzecz działających alertów.
2. **Model dostępu trzymać agnostycznie względem narzędzia** (CSV + grupy Entra w git), a poziom
   dostępu (`view/edit/admin`) **oddzielić od sposobu przypięcia** (rola Azure teraz → rola Grafany później).
3. **System/RA uczynić wymiarem pierwszej klasy** — dziś mapuje się na foldery, po migracji może stać
   się organizacją Grafany (rekomendacja ze spotkania: org = system/data stream).
4. **Oflagować zależności Enterprise-only** (zwłaszcza team sync grupa Entra → team) — działa „za darmo"
   na Managed Grafanie, ale w self-hosted OSS zniknie.

---

## Punkty ze spotkania istotne dla RBAC

### 1. current-user vs managed identity → team/folder RBAC jest jedyną granularnością (spotkanie §3)

Spotkanie: na data source Azure Monitor nie da się mieć jednocześnie **RBAC per użytkownik**
(*current user*) i **działających alertów** (te wykonują się w kontekście tożsamości Grafany).
Pełna elastyczność dopiero w self-hosted.

**Korelacja z RBAC:** na Managed Grafanie zespół wybierze najpewniej *managed identity* (żeby alerty
działały) → wtedy dostęp per użytkownik na poziomie danych **znika**. Cała granularność dostępu musi
więc pochodzić z warstwy **team → folder → uprawnienie**, którą zarządza to repo
([teams.tf](../managed_grafana_internal/teams.tf), [folders.tf](../managed_grafana_internal/folders.tf)).
To **podnosi wagę** modelu CSV→RBAC, nie obniża — jest jedynym miejscem, gdzie różnicujemy dostęp.
Konsekwencja dla schematu CSV: poziomy `view/edit/admin` muszą realnie odwzorować potrzeby biznesowe,
bo nie ma zapasowej warstwy per-user.

### 2. Team sync Entra → team to funkcja przejściowa „za darmo" (spotkanie §1, wniosek 4)

Repo mapuje grupę Entra na team przez `grafana_team_external_group`
([teams.tf:9-14](../managed_grafana_internal/teams.tf#L9-L14)). Na **Azure Managed Grafanie** działa to
natywnie (Entra SSO + team sync w cenie). Spotkanie (wniosek 4) ostrzega jednak, że granularny dostęp
„pod prąd narzędzi" najpewniej wymaga **Enterprise** — a **team sync w self-hosted Grafanie jest funkcją
Enterprise**, niedostępną w OSS.

**Korelacja:** na etapie przejściowym mapowanie grupa→team jest bezpieczne. Ale to **punkt ryzyka migracji** —
po przejściu na self-hosted OSS trzeba będzie albo kupić Enterprise, albo zastąpić team sync innym
mechanizmem (np. przypisania z IdP / provisioning). Grupy Entra jako źródło prawdy w CSV zostają przenośne;
sam *mechanizm* synchronizacji — nie. Warto to zapisać jako założenie migracyjne już teraz.

### 3. Warstwa Azure RBAC instancji jest specyficzna dla Managed Grafany (spotkanie wniosek 1–2)

Repo nadaje role Azure na zasobie Grafany (`azurerm_role_assignment`, role `Grafana Admin/Editor/Viewer/
Limited Viewer`) w [rbac_azure.tf](../managed_grafana_internal/rbac_azure.tf) i
[variables.tf:44-53](../managed_grafana_internal/variables.tf#L44-L53). To konstrukcja **wyłącznie
Managed Grafany** — w self-hosted odpowiednikiem są role organizacji / RBAC Grafany, nie Azure RBAC.

**Korelacja:** w modelu CSV poziom dostępu należy trzymać **abstrakcyjnie** (`view/edit/admin`), a mapowanie
na konkretną rolę Azure zamknąć w jednej regule/mapie. Przy migracji podmienia się tylko tę regułę
(rola Azure → rola Grafany), a nie cały model danych. To wzmacnia rekomendację z mojej analizy, by
`access_level` w CSV był oderwany od nazw ról Azure.

### 4. Multi-tenancy / organizacje — System/RA jako wymiar pierwszej klasy (spotkanie §4)

Spotkanie: rekomendowany model to **organizacje mapowane na system / data stream**, nie na strukturę firmy;
ten sam data source dodawany wielokrotnie z uprawnieniami per team. Azure Managed Grafana ma jednak
ograniczone wsparcie organizacji — więc **na etapie przejściowym separację System/RA realizuje się przez
foldery + teamy**, dokładnie jak w moim modelu CSV (folder = RA/system, podfolder = środowisko).

**Korelacja:** to potwierdza hierarchię folder→podfolder z analizy. Kluczowe: **System/RA musi być
osobną kolumną/wymiarem w CSV** (nie „sklejką"), bo:
- dziś → mapuje się na folder nadrzędny,
- po migracji do self-hosted → może stać się **organizacją** Grafany.
Trzymanie System/RA jako pierwszej klasy czyni model przenośnym między oboma etapami bez przepisywania danych.

### 5. „Wszystko jako kod + git" spójne z modelem CSV (spotkanie: następne kroki)

Zalecenia operacyjne ze spotkania (sync dashboardów do GitHub + backup, PostgreSQL pod Grafaną przy 200+
dashboardach) idą w parze z ideą repo: źródło prawdy w git, wersjonowalny diff. Model CSV→RBAC to realizuje
dla uprawnień; [content.tf](../managed_grafana_internal/content.tf) — dla dashboardów. Utrzymać tę zasadę
przy przebudowie: CSV + reguły mapowania w repo, generowane, nie klikane ręcznie w UI.

---

## Implikacje dla przyszłego planu przebudowy (do rozstrzygnięcia przed kodowaniem)

1. **Zaprojektować CSV/model tak, by przetrwał migrację Managed → self-hosted:** grupy Entra + System/RA +
   `access_level` = warstwa przenośna; role Azure, team sync, org = warstwa wymienialna. Rozgraniczyć je
   w kodzie (osobne pliki/mapy), żeby migracja była podmianą reguł, nie przepisaniem.
2. **Uznać team/folder RBAC za jedyną granularność** i pod tym kątem zweryfikować, czy `view/edit/admin`
   wystarcza (skoro per-user na data source odpada).
3. **Zapisać zależności Enterprise-only** (team sync) jako znane ryzyko migracji — decyzja
   „Enterprise vs inny provisioning" wykracza poza to repo, ale determinuje trwałość modelu.
4. **System/RA jako wymiar pierwszej klasy** — jedna kolumna w CSV, dziś → folder, później → organizacja.

---

## Otwarte pytania (nowe, wynikłe z korelacji)

1. Czy na etapie przejściowym data source'y idą na *managed identity* (alerty) — potwierdzić, bo to przesądza,
   że repo jest jedyną warstwą granularności?
2. Czy po migracji do self-hosted planowany jest **Grafana Enterprise** (team sync, RBAC per-action), czy OSS?
   To determinuje, czy mechanizm grupa Entra→team jest przenośny.
3. Czy docelowo System/RA ma być **organizacją** Grafany (rekomendacja ze spotkania), czy zostajemy przy
   folderach? Wpływa na to, jak agresywnie wydzielić System/RA w schemacie CSV.
4. Czy zakres tego repo obejmuje tylko RBAC, czy również dashboardy/data source'y w fazie przejściowej
   (bo spotkanie mocno wiąże RBAC z modelem data source per organizacja/team)?
