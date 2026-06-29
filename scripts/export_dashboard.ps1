# =============================================================================
# scripts/export_dashboard.ps1
# Exporta los datos para el dashboard a dashboard/data.json
# Lee las vistas vw_Dashboard_* + Sueldos_Altas + Sueldos_Bajas y produce un
# JSON con todos los agregados ya calculados, listos para Chart.js.
# Refresca cada vez que corre.
# =============================================================================
[CmdletBinding()]
param(
    [string]$Server     = '192.168.10.17\SQLEXPRESS',
    [string]$Database   = 'ERP_Senales',
    [string]$User       = 'bi_gateway',
    [string]$OutFile    = (Join-Path $PSScriptRoot '..\dashboard\data.json'),
    # Periodo desde el que exportar (YYYYMM). Default: 202601.
    # CostoLaboralDetalle es lenta sobre la historia completa (82 periodos);
    # limitar la ventana mantiene el export en segundos.
    [string]$FromPeriod = '202601'
)

$ErrorActionPreference = 'Stop'

# --- Descifrar password DPAPI ---
$dpapiPath = Join-Path $PSScriptRoot '..\.sql-helper\password.dpapi'
$hex = (Get-Content $dpapiPath -Raw).Trim()
$bytes = [byte[]]::new($hex.Length / 2)
for ($i = 0; $i -lt $bytes.Length; $i++) {
    $bytes[$i] = [Convert]::ToByte($hex.Substring($i * 2, 2), 16)
}
Add-Type -AssemblyName System.Security
$decrypted = [System.Security.Cryptography.ProtectedData]::Unprotect(
    $bytes, $null,
    [System.Security.Cryptography.DataProtectionScope]::CurrentUser)
$password = [System.Text.Encoding]::Unicode.GetString($decrypted)

# --- Conexion ---
$csb = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$csb['Server']                 = $Server
$csb['Database']               = $Database
$csb['User ID']                = $User
$csb['Password']               = $password
$csb['TrustServerCertificate'] = $true
$csb['Encrypt']                = $true
$csb['Connect Timeout']        = 15

function Invoke-Sql {
    param(
        [string]$Query,
        [int]$Timeout = 300
    )
    $conn = New-Object System.Data.SqlClient.SqlConnection $csb.ConnectionString
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Query
    $cmd.CommandTimeout = $Timeout
    $da = New-Object System.Data.SqlClient.SqlDataAdapter $cmd
    $dt = New-Object System.Data.DataTable
    $null = $da.Fill($dt)
    $conn.Close()
    # Comma operator preserves DataTable so PowerShell does not unwrap it.
    return ,$dt
}

function ConvertTo-Array {
    param($DataTable)
    $rows = @()
    foreach ($row in $DataTable.Rows) {
        $obj = [ordered]@{}
        foreach ($col in $DataTable.Columns) {
            $val = $row[$col.ColumnName]
            if ($val -is [DBNull]) { $val = $null }
            $obj[$col.ColumnName] = $val
        }
        $rows += [PSCustomObject]$obj
    }
    return ,$rows
}

Write-Host "Conectando a $Server / $Database (desde $FromPeriod) ..." -ForegroundColor Cyan

# --- 1. Periodos disponibles (fuente liviana: vw_Sueldos_Liquidaciones) ---
$periodos = ConvertTo-Array (Invoke-Sql @"
SELECT DISTINCT PERIODO AS Periodo
FROM dbo.vw_Sueldos_Liquidaciones
WHERE CLASE = 3 AND PERIODO >= '$FromPeriod'
ORDER BY PERIODO;
"@)

# --- 2. Catalogo de CC desde el snapshot de activos + nomina mensual ---
$centrosCosto = ConvertTo-Array (Invoke-Sql @"
SELECT DISTINCT CodigoCC, NombreCC
FROM (
    SELECT CodigoCC, NombreCC FROM dbo.vw_Dashboard_NominaMensual_PorCC
    WHERE Periodo >= '$FromPeriod'
    UNION
    SELECT CAST(CodigoCC AS NVARCHAR(20)), NombreCC FROM dbo.vw_Dashboard_NominaActiva_PorCC
) t
WHERE NombreCC IS NOT NULL
ORDER BY NombreCC;
"@)

# --- 3. Empresas ---
$empresas = ConvertTo-Array (Invoke-Sql @"
SELECT DISTINCT m.Empresa, COALESCE(ce.NombreEmpresa, m.Empresa) AS RazonSocial
FROM (
    SELECT Empresa FROM dbo.vw_Dashboard_NominaMensual_PorCC
    WHERE Periodo >= '$FromPeriod'
) m
LEFT JOIN dbo.Config_Empresas_Sueldos ce ON ce.Empresa = m.Empresa
ORDER BY m.Empresa;
"@)

# --- 4. Nomina mensual ---
Write-Host "Agregando nomina mensual..." -ForegroundColor Cyan

# Fact table: 1 fila por (Periodo, Empresa, CC, TipoTrabajo). Permite que el
# front cruze libremente todos los filtros (Periodo, Empresa, CC, Tipo).
$nominaFact = ConvertTo-Array (Invoke-Sql @"
SELECT Periodo, Empresa, CodigoCC, NombreCC, TipoTrabajo,
       COUNT(DISTINCT IdEmpleado) AS Personas
FROM dbo.vw_Dashboard_NominaMensual_PorCC
WHERE Periodo >= '$FromPeriod'
GROUP BY Periodo, Empresa, CodigoCC, NombreCC, TipoTrabajo
ORDER BY Periodo, Empresa, NombreCC, TipoTrabajo;
"@)

# --- 5. Costo mensual ---
Write-Host "Agregando costo empresa..." -ForegroundColor Cyan

# Fact table de costo: 1 fila por (Periodo, Empresa, CC, TipoTrabajo, Categoria).
$costoFact = ConvertTo-Array (Invoke-Sql @"
SELECT Periodo, Empresa, CodigoCC, NombreCC, TipoTrabajo, Categoria,
       ROUND(SUM(CostoTotal),2) AS CostoTotal
FROM dbo.vw_Dashboard_CostoMensual_PorCC
WHERE Periodo >= '$FromPeriod'
GROUP BY Periodo, Empresa, CodigoCC, NombreCC, TipoTrabajo, Categoria
ORDER BY Periodo, Empresa, NombreCC, TipoTrabajo, Categoria;
"@)

# --- 6. Nomina activa actual ---
Write-Host "Snapshot de nomina activa actual..." -ForegroundColor Cyan

$peDt = Invoke-Sql "SELECT TOP 1 PeriodoEvaluado FROM dbo.vw_Dashboard_NominaActiva_PorCC;"
$periodoEvaluado = if ($peDt.Rows.Count -gt 0) { $peDt.Rows[0]['PeriodoEvaluado'] } else { $null }

$activaPorTipoTrabajo = ConvertTo-Array (Invoke-Sql @"
SELECT TipoTrabajo, COUNT(*) AS Personas
FROM dbo.vw_Dashboard_NominaActiva_PorCC
GROUP BY TipoTrabajo
ORDER BY Personas DESC;
"@)

$activaPorCC = ConvertTo-Array (Invoke-Sql @"
SELECT CAST(CodigoCC AS NVARCHAR(20)) AS CodigoCC, NombreCC,
       COUNT(*) AS Personas
FROM dbo.vw_Dashboard_NominaActiva_PorCC
GROUP BY CodigoCC, NombreCC
ORDER BY Personas DESC;
"@)

$activaMatriz = ConvertTo-Array (Invoke-Sql @"
SELECT CAST(CodigoCC AS NVARCHAR(20)) AS CodigoCC, NombreCC, TipoTrabajo,
       COUNT(*) AS Personas
FROM dbo.vw_Dashboard_NominaActiva_PorCC
GROUP BY CodigoCC, NombreCC, TipoTrabajo
ORDER BY NombreCC, TipoTrabajo;
"@)

$activaPorPuesto = ConvertTo-Array (Invoke-Sql @"
SELECT UltimoPuestoNombre AS Puesto, TipoTrabajo, COUNT(*) AS Personas
FROM dbo.vw_Dashboard_NominaActiva_PorCC
GROUP BY UltimoPuestoNombre, TipoTrabajo
ORDER BY COUNT(*) DESC, UltimoPuestoNombre;
"@)

$activaEmpleados = ConvertTo-Array (Invoke-Sql @"
SELECT Empresa, RazonSocial, CUIL, NombreEmpleado, IdEmpleado,
       CAST(CodigoCC AS NVARCHAR(20)) AS CodigoCC, NombreCC,
       TipoTrabajo, UltimoPuestoNombre AS Puesto
FROM dbo.vw_Dashboard_NominaActiva_PorCC
ORDER BY NombreCC, NombreEmpleado;
"@)

# Costo por empleado del periodo activo, query separada para evitar
# que el optimizer haga explotar el plan al joinar con CostoMensual_PorCC.
$costoPorEmpleadoPeriodo = ConvertTo-Array (Invoke-Sql @"
SELECT Empresa, IdEmpleado, ROUND(SUM(TotalCostoLaboral), 0) AS Costo
FROM dbo.vw_Sueldos_CostoLaboralDetalle
WHERE PERIODO = '$periodoEvaluado'
GROUP BY Empresa, IdEmpleado;
"@)

# Merge Costo en activaEmpleados
$costoMap = @{}
foreach ($r in $costoPorEmpleadoPeriodo) {
    $costoMap["$($r.Empresa)|$($r.IdEmpleado)"] = $r.Costo
}
foreach ($e in $activaEmpleados) {
    $key = "$($e.Empresa)|$($e.IdEmpleado)"
    $costo = if ($costoMap.ContainsKey($key)) { $costoMap[$key] } else { 0 }
    $e | Add-Member -NotePropertyName 'Costo' -NotePropertyValue $costo -Force
}

$activaTotalActivos = ($activaPorTipoTrabajo | Measure-Object -Property Personas -Sum).Sum

# --- 7. Altas y bajas por periodo ---
Write-Host "Altas y bajas..." -ForegroundColor Cyan

$altasBajasPorPeriodo = ConvertTo-Array (Invoke-Sql @"
WITH alt AS (
    SELECT PeriodoAlta AS Periodo, COUNT(*) AS Altas
    FROM dbo.Sueldos_Altas
    WHERE PeriodoAlta >= '$FromPeriod'
    GROUP BY PeriodoAlta
),
baj AS (
    SELECT PeriodoBaja AS Periodo, COUNT(*) AS Bajas
    FROM dbo.Sueldos_Bajas
    WHERE PeriodoBaja >= '$FromPeriod'
    GROUP BY PeriodoBaja
)
SELECT
    COALESCE(alt.Periodo, baj.Periodo) AS Periodo,
    ISNULL(alt.Altas, 0) AS Altas,
    ISNULL(baj.Bajas, 0) AS Bajas
FROM alt
FULL OUTER JOIN baj ON baj.Periodo = alt.Periodo
ORDER BY Periodo;
"@)

$altasBajasDetalle = ConvertTo-Array (Invoke-Sql @"
WITH ccs AS (
    SELECT DISTINCT Empresa, CUIL, Periodo, CodigoCC, NombreCC, TipoTrabajo
    FROM dbo.vw_Dashboard_NominaMensual_PorCC
    WHERE Periodo >= '$FromPeriod'
)
SELECT a.PeriodoAlta AS Periodo, CAST('ALTA' AS VARCHAR(4)) AS Tipo,
       a.Empresa, a.CUIL, a.NombreEmpleado,
       c.CodigoCC, c.NombreCC, c.TipoTrabajo,
       a.TipoAlta AS Motivo
FROM dbo.Sueldos_Altas a
LEFT JOIN ccs c ON c.Empresa = a.Empresa AND c.CUIL = a.CUIL AND c.Periodo = a.PeriodoAlta
WHERE a.PeriodoAlta >= '$FromPeriod'
UNION ALL
SELECT b.PeriodoBaja AS Periodo, CAST('BAJA' AS VARCHAR(4)) AS Tipo,
       b.Empresa, b.CUIL, b.NombreEmpleado,
       c.CodigoCC, c.NombreCC, c.TipoTrabajo,
       b.MotivoBaja AS Motivo
FROM dbo.Sueldos_Bajas b
LEFT JOIN ccs c ON c.Empresa = b.Empresa AND c.CUIL = b.CUIL AND c.Periodo = b.PeriodoBaja
WHERE b.PeriodoBaja >= '$FromPeriod'
ORDER BY Periodo, Tipo;
"@)

# --- 8. Armar JSON ---
$payload = [ordered]@{
    lastUpdated      = (Get-Date).ToString('s')
    periodoEvaluado  = $periodoEvaluado
    totalActivos     = $activaTotalActivos
    periodos         = $periodos
    centrosCosto     = $centrosCosto
    empresas         = $empresas
    nominaMensual    = [ordered]@{
        fact = $nominaFact
    }
    costoMensual     = [ordered]@{
        fact = $costoFact
    }
    nominaActiva     = [ordered]@{
        porTipoTrabajo = $activaPorTipoTrabajo
        porCC          = $activaPorCC
        matriz         = $activaMatriz
        porPuesto      = $activaPorPuesto
        empleados      = $activaEmpleados
    }
    altasBajas       = [ordered]@{
        porPeriodo = $altasBajasPorPeriodo
        detalle    = $altasBajasDetalle
    }
}

$json = $payload | ConvertTo-Json -Depth 10 -Compress:$false

# Crear directorio si no existe
$outDir = Split-Path $OutFile -Parent
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

Set-Content -Path $OutFile -Value $json -Encoding UTF8

$size = (Get-Item $OutFile).Length
Write-Host ""
Write-Host "OK -> $OutFile ($([math]::Round($size/1KB,1)) KB)" -ForegroundColor Green
Write-Host "  Periodos:         $($periodos.Count)"
Write-Host "  Centros de Costo: $($centrosCosto.Count)"
Write-Host "  Empresas:         $($empresas.Count)"
Write-Host "  Periodo activo:   $periodoEvaluado ($activaTotalActivos personas)"
