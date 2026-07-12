# Debug apply managed_grafana_internal

Odpal to na maszynie przesiadkowej (PowerShell) i wklej wyniki.

Najpierw ustaw zmienną z URL-em (używana niżej):

```powershell
$Url = "https://gxyzck1ra0661grafadev1-che4epf0fgcpbtev.cfr.grafana.azure.com"
```

## Diagnostyka Grafany (problem 1)

```powershell
# 1. Czy token w ogóle jest ustawiony?
"GRAFANA_AUTH length: $($env:GRAFANA_AUTH.Length)"

# 2. DNS + osiągalność data plane (kluczowe: czy TCP:443 wchodzi)
Resolve-DnsName gxyzck1ra0661grafadev1-che4epf0fgcpbtev.cfr.grafana.azure.com
Test-NetConnection gxyzck1ra0661grafadev1-che4epf0fgcpbtev.cfr.grafana.azure.com -Port 443

# 2b. HTTP /api/health - bez tokenu (mierzy kod i czas)
try {
  $r = Invoke-WebRequest "$Url/api/health" -TimeoutSec 12 -SkipHttpErrorCheck
  "http=$($r.StatusCode)"
} catch { "FAIL: $($_.Exception.Message)" }

# 3. Z tokenem - czy autoryzacja przechodzi (oczekiwane 200)?
try {
  $r = Invoke-WebRequest "$Url/api/folders" -Headers @{ Authorization = "Bearer $env:GRAFANA_AUTH" } -TimeoutSec 12 -SkipHttpErrorCheck
  "http=$($r.StatusCode)"
} catch { "FAIL: $($_.Exception.Message)" }
```

> Uwaga: `-SkipHttpErrorCheck` wymaga PowerShell 7+. Na Windows PowerShell 5.1 kod błędu (401/403) wyląduje w `catch` — wtedy szczegół jest w `$($_.Exception.Response.StatusCode.value__)`.

**Interpretacja:**
- `Test-NetConnection` -> `TcpTestSucceeded: False`, albo HTTP wisi do timeoutu -> **sieć/private endpoint** (to samo co „context deadline exceeded").
- szybkie `http=401` -> **zły/brak GRAFANA_AUTH**.
- `http=200` -> Grafana OK, wtedy winna była tylko pusta zmienna w sesji apply.

## Diagnostyka RBAC (problem 2)

```powershell
# Kim jest terraform i czy ma prawo do roleAssignments/write?
az account show -o table

# Jakie role ma ten SP na resource group Grafany?
az role assignment list `
  --assignee 804a085a-4007-42f7-91cc-cbe742b7afd7 `
  --scope "/subscriptions/0c31f129-5f19-464d-a277-e1c8c35e6899/resourceGroups/gxyz-ck1-ra0661-resougroup-dev-1" `
  --include-inherited -o table
```

Jeśli w wyniku nie ma **Owner** ani **User Access Administrator** — to jest przyczyna 403.
Nadanie (musi zrobić ktoś z Owner na scope):

```powershell
az role assignment create `
  --assignee 804a085a-4007-42f7-91cc-cbe742b7afd7 `
  --role "User Access Administrator" `
  --scope "/subscriptions/0c31f129-5f19-464d-a277-e1c8c35e6899/resourceGroups/gxyz-ck1-ra0661-resougroup-dev-1"
```

Wklej wyniki tych komend, to potwierdzę, która gałąź (sieć vs token vs RBAC) i domkniemy fix.
