# ingesta_excel.ps1
# Lee los Excel de "TESORERIA - GV" (Google Drive) y los vuelca a las tablas dbo.Manual_*
# Uso:
#   .\ingesta_excel.ps1                          (rutas default Google Drive)
#   .\ingesta_excel.ps1 -PathBancos "D:\otra\ruta\BANCOS - GV.xlsx"
#   .\ingesta_excel.ps1 -SoloBancos              (solo saldos bancarios)
#   .\ingesta_excel.ps1 -SoloTarjetas            (solo acreditaciones tarjetas)
#
# Requiere: sql.ps1 en la raíz + Excel instalado (COM Interop) + acceso a Google Drive montado en G:\.

[CmdletBinding()]
param(
    [string]$PathBancos    = 'G:\.shortcut-targets-by-id\1TNAQJXrS9QVbXV1KoIy__J7pqdp4QsxG\Reportes Consultora Final\07 - GRUPO VIGIL\TESORERIA - GV\BANCOS\BANCOS - GV.xlsx',
    [string]$PathTarjetas  = 'G:\.shortcut-targets-by-id\1TNAQJXrS9QVbXV1KoIy__J7pqdp4QsxG\Reportes Consultora Final\07 - GRUPO VIGIL\TESORERIA - GV\ACREDITACIONES\ACREDITACIONES TARJETAS.xlsx',
    [string]$PathPrestamos = 'G:\.shortcut-targets-by-id\1TNAQJXrS9QVbXV1KoIy__J7pqdp4QsxG\Reportes Consultora Final\07 - GRUPO VIGIL\TESORERIA - GV\PRESTAMOS\PRESTAMOS - GV.xlsx',
    [string]$PathPlanes    = 'G:\.shortcut-targets-by-id\1TNAQJXrS9QVbXV1KoIy__J7pqdp4QsxG\Reportes Consultora Final\07 - GRUPO VIGIL\TESORERIA - GV\IMPOSITIVO\PRESTAMOS, PLANES Y DEUDAS.xlsx',
    [switch]$SoloBancos,
    [switch]$SoloTarjetas,
    [switch]$SoloPrestamos,
    [switch]$SoloPlanes,
    [switch]$SoloImpositivo
)

$ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$helper = Join-Path $root 'sql.ps1'
if (-not (Test-Path $helper)) { throw "No se encuentra sql.ps1 en $root" }

# Auto-fallback: en algunos Drives la subcarpeta es "TESORERIA - GV (1)" en vez de "TESORERIA - GV"
$__fallback = @('TESORERIA - GV (1)')
foreach ($alt in $__fallback) {
    if (-not (Test-Path $PathBancos))    { $tmp = $PathBancos    -replace 'TESORERIA - GV\\', "$alt\"; if (Test-Path $tmp) { $PathBancos    = $tmp } }
    if (-not (Test-Path $PathTarjetas))  { $tmp = $PathTarjetas  -replace 'TESORERIA - GV\\', "$alt\"; if (Test-Path $tmp) { $PathTarjetas  = $tmp } }
    if (-not (Test-Path $PathPrestamos)) { $tmp = $PathPrestamos -replace 'TESORERIA - GV\\', "$alt\"; if (Test-Path $tmp) { $PathPrestamos = $tmp } }
    if (-not (Test-Path $PathPlanes))    { $tmp = $PathPlanes    -replace 'TESORERIA - GV\\', "$alt\"; if (Test-Path $tmp) { $PathPlanes    = $tmp } }
}

# --------- Helpers -----------------------------------------------------------

function Invoke-SqlNonQuery {
    param([string]$Query)
    # Ejecuta un batch SQL y devuelve texto (para logging)
    $out = & $helper $Query 2>&1 | Out-String
    return $out
}

function Invoke-SqlScalar {
    param([string]$Query)
    # Ejecuta un batch que devuelve JSON. Si el parseo falla o hay error de PS, lo propaga.
    $raw = & $helper -Format Json $Query 2>&1 | Out-String
    $errLine = $raw -split "`r?`n" | Where-Object { $_ -match '^\s*(sql\.ps1|Exception|System\.Data)' } | Select-Object -First 1
    if ($errLine) { throw "SQL falló:`n$raw" }
    try {
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "SQL: no se pudo parsear respuesta.`n$raw"
    }
    return $obj
}

function ConvertTo-SqlDecimal {
    param($v)
    if ($null -eq $v -or $v -eq '') { return 'NULL' }
    if ($v -is [double] -or $v -is [decimal] -or $v -is [int] -or $v -is [long]) {
        return ([decimal]$v).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    # A veces vienen como texto con formato AR: "5.933.415,55" o "$ 12.486.875,00"
    $s = ($v -replace '[^\d\-,]', '') -replace ',', '.'
    if ($s -match '^-?\d+(\.\d+)?$') {
        return ([decimal]$s).ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    return 'NULL'
}

function ConvertTo-SqlDate {
    param($v)
    if ($null -eq $v -or $v -eq '') { return $null }
    if ($v -is [double]) { return ([DateTime]::FromOADate($v)).ToString('yyyy-MM-dd') }
    if ($v -is [DateTime]) { return $v.ToString('yyyy-MM-dd') }
    # texto: intento parseo AR primero
    try {
        $d = [DateTime]::Parse($v, [System.Globalization.CultureInfo]::GetCultureInfo('es-AR'))
        return $d.ToString('yyyy-MM-dd')
    } catch { return $null }
}

function SqlStr {
    param([string]$s)
    if ($null -eq $s) { return 'NULL' }
    return "N'" + ($s -replace "'", "''") + "'"
}

# --------- Excel COM ---------------------------------------------------------

function Open-ExcelReadOnly {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "No existe: $Path" }
    $xl = New-Object -ComObject Excel.Application
    $xl.Visible = $false
    $xl.DisplayAlerts = $false
    $wb = $xl.Workbooks.Open($Path, 0, $true)
    return @{ App = $xl; Book = $wb }
}

function Close-Excel {
    param($ctx)
    if ($ctx.Book) { $ctx.Book.Close($false) }
    if ($ctx.App)  { $ctx.App.Quit() }
    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($ctx.App) | Out-Null
}

# --------- Ingesta: BANCOS - GV / RESUMEN -----------------------------------

function Ingest-Bancos {
    param([string]$Path)
    Write-Host "► Bancos: $Path" -ForegroundColor Cyan
    $ctx = Open-ExcelReadOnly -Path $Path
    try {
        $ws = $ctx.Book.Worksheets.Item('RESUMEN')
        $used = $ws.UsedRange
        $filas = $used.Rows.Count

        # Cols fijas (validado contra Excel real, no confío en la cabecera R1)
        # 1:RazonSocial  2:Banco  3:Cuenta  4:Fecha  5:Saldo  6:FCI  7:MPago  8:Pix  9:Descubierto  10:Disponible
        $registros = @()
        for ($r = 2; $r -le $filas; $r++) {
            $rs = [string]$ws.Cells.Item($r, 1).Text
            $bc = [string]$ws.Cells.Item($r, 2).Text
            $ct = [string]$ws.Cells.Item($r, 3).Text
            $fx = $ws.Cells.Item($r, 4).Value2
            if ([string]::IsNullOrWhiteSpace($rs) -or [string]::IsNullOrWhiteSpace($bc)) { continue }
            $fecha = ConvertTo-SqlDate $fx
            if (-not $fecha) { continue }
            $registros += [pscustomobject]@{
                Fecha        = $fecha
                RazonSocial  = $rs.Trim()
                Banco        = $bc.Trim()
                Cuenta       = ($ct ?? '').Trim()
                Saldo        = ConvertTo-SqlDecimal $ws.Cells.Item($r, 5).Value2
                FCI          = ConvertTo-SqlDecimal $ws.Cells.Item($r, 6).Value2
                MPago        = ConvertTo-SqlDecimal $ws.Cells.Item($r, 7).Value2
                Pix          = ConvertTo-SqlDecimal $ws.Cells.Item($r, 8).Value2
                Descubierto  = ConvertTo-SqlDecimal $ws.Cells.Item($r, 9).Value2
                Disponible   = ConvertTo-SqlDecimal $ws.Cells.Item($r, 10).Value2
            }
        }
        Write-Host "  Leídas $($registros.Count) filas útiles" -ForegroundColor Gray
        if ($registros.Count -eq 0) { throw "No se pudo leer ninguna fila de RESUMEN" }

        # MERGE por (FechaSaldo, RazonSocialExcel, Banco, Cuenta)
        # Construyo un VALUES batch y hago MERGE
        $archivo = Split-Path $Path -Leaf
        $rows = ($registros | ForEach-Object {
            "($(SqlStr $_.Fecha), $(SqlStr $_.RazonSocial), $(SqlStr $_.Banco), $(SqlStr $_.Cuenta), $($_.Saldo), $($_.FCI), $($_.MPago), $($_.Pix), $($_.Descubierto), $($_.Disponible), $(SqlStr $archivo))"
        }) -join ",`n"

        $sql = @"
MERGE dbo.Manual_SaldosBancos AS t
USING (VALUES
$rows
) AS s (FechaSaldo, RazonSocialExcel, Banco, Cuenta, Saldo, FCI, MPago, Pix, DescubiertoAutorizado, Disponible, _archivoOrigen)
ON  t.FechaSaldo       = CAST(s.FechaSaldo AS DATE)
AND t.RazonSocialExcel = s.RazonSocialExcel
AND t.Banco            = s.Banco
AND t.Cuenta           = s.Cuenta
WHEN MATCHED THEN UPDATE SET
    Saldo                 = s.Saldo,
    FCI                   = s.FCI,
    MPago                 = s.MPago,
    Pix                   = s.Pix,
    DescubiertoAutorizado = s.DescubiertoAutorizado,
    Disponible            = s.Disponible,
    _cargadoEn            = SYSDATETIME(),
    _archivoOrigen        = s._archivoOrigen
WHEN NOT MATCHED THEN INSERT
    (FechaSaldo, RazonSocialExcel, Banco, Cuenta, Saldo, FCI, MPago, Pix, DescubiertoAutorizado, Disponible, _archivoOrigen)
    VALUES (CAST(s.FechaSaldo AS DATE), s.RazonSocialExcel, s.Banco, s.Cuenta, s.Saldo, s.FCI, s.MPago, s.Pix, s.DescubiertoAutorizado, s.Disponible, s._archivoOrigen);

SELECT @@ROWCOUNT AS FilasAfectadas;
"@
        $r = Invoke-SqlScalar $sql
        Write-Host "  MERGE OK — filas afectadas: $($r.FilasAfectadas)" -ForegroundColor Green

        return @{ Filas = $registros.Count; Fechas = ($registros.Fecha | Sort-Object -Unique) }
    } finally { Close-Excel $ctx }
}

# --------- Ingesta: ACREDITACIONES TARJETAS ---------------------------------

function Ingest-Tarjetas {
    param([string]$Path)
    Write-Host "► Tarjetas: $Path" -ForegroundColor Cyan
    $ctx = Open-ExcelReadOnly -Path $Path
    try {
        $ws = $ctx.Book.Worksheets.Item(1)
        $used = $ws.UsedRange
        $filas = $used.Rows.Count

        # Cols: 1:Fecha  2:Vendido  3:Acreditado  4:Estado  5:RazonSocial
        $registros = @()
        for ($r = 2; $r -le $filas; $r++) {
            $fx = $ws.Cells.Item($r, 1).Value2
            $rs = [string]$ws.Cells.Item($r, 5).Text
            if ([string]::IsNullOrWhiteSpace($rs)) { continue }
            $fecha = ConvertTo-SqlDate $fx
            if (-not $fecha) { continue }
            $registros += [pscustomobject]@{
                Fecha       = $fecha
                RazonSocial = $rs.Trim()
                Vendido     = ConvertTo-SqlDecimal $ws.Cells.Item($r, 2).Value2
                Acreditado  = ConvertTo-SqlDecimal $ws.Cells.Item($r, 3).Value2
                Estado      = ([string]$ws.Cells.Item($r, 4).Text).Trim()
            }
        }
        Write-Host "  Leídas $($registros.Count) filas útiles" -ForegroundColor Gray
        if ($registros.Count -eq 0) { throw "No se pudo leer ninguna fila de tarjetas" }

        $archivo = Split-Path $Path -Leaf

        # Estrategia: DELETE por archivo (borra todo lo que cargó este mismo Excel)
        # + INSERT nuevos. Idempotente: correr N veces da el mismo resultado.
        # PK (Fecha, RazonSocial) evita duplicados dentro del batch.
        $rows = ($registros | ForEach-Object {
            "($(SqlStr $_.Fecha), $(SqlStr $_.RazonSocial), $($_.Vendido), $($_.Acreditado), $(SqlStr $_.Estado), $(SqlStr $archivo))"
        }) -join ",`n"

        $sql = @"
DELETE FROM dbo.Manual_AcreditacionesTarjetas WHERE _archivoOrigen = $(SqlStr $archivo);

;WITH src AS (
    SELECT FechaAcreditacion, RazonSocialExcel, Vendido, Acreditado, Estado, _archivoOrigen,
           rn = ROW_NUMBER() OVER (PARTITION BY FechaAcreditacion, RazonSocialExcel ORDER BY (SELECT 0))
    FROM (VALUES
$rows
    ) v (FechaAcreditacion, RazonSocialExcel, Vendido, Acreditado, Estado, _archivoOrigen)
)
INSERT INTO dbo.Manual_AcreditacionesTarjetas
    (FechaAcreditacion, RazonSocialExcel, Vendido, Acreditado, Estado, _archivoOrigen)
SELECT CAST(FechaAcreditacion AS DATE), RazonSocialExcel, Vendido, Acreditado, Estado, _archivoOrigen
FROM src WHERE rn = 1;

SELECT
    COUNT(*)                                                       AS Total,
    SUM(CASE WHEN Estado = 'PENDIENTE' THEN 1 ELSE 0 END)          AS Pendientes,
    SUM(CASE WHEN Estado = 'ACREDITADO' THEN 1 ELSE 0 END)         AS Acreditados
FROM dbo.Manual_AcreditacionesTarjetas WHERE _archivoOrigen = $(SqlStr $archivo);
"@
        $r = Invoke-SqlScalar $sql
        Write-Host "  Insertadas: $($r.Total) (Pendientes: $($r.Pendientes), Acreditadas: $($r.Acreditados))" -ForegroundColor Green

        return @{ Filas = $registros.Count }
    } finally { Close-Excel $ctx }
}

# --------- Ingesta: PRESTAMOS - GV / hoja "PRESTAMOS" -----------------------
# Header en R4. Grano: fila por cuota. DELETE por _archivoOrigen + INSERT completo.

function Ingest-Prestamos {
    param([string]$Path)
    Write-Host "► Préstamos: $Path" -ForegroundColor Cyan
    $ctx = Open-ExcelReadOnly -Path $Path
    try {
        $ws = $ctx.Book.Worksheets.Item('PRESTAMOS')
        $filas = $ws.UsedRange.Rows.Count
        # Cols (header R4): 1:Entidad 2:Empresa 3:Concepto 4:NroPrestamo 5:Cuota
        # 6:Capital 7:IVA 8:IntFin 9:Sellado 10:IntResarc 11:ImporteCuota
        # 12:FechaVto 13:Estado 14:MesAnio 15:Condicion 16:Op 17:Observacion
        $registros = @()
        for ($r = 5; $r -le $filas; $r++) {
            $entidad = ([string]$ws.Cells.Item($r, 1).Text).Trim()
            $empresa = ([string]$ws.Cells.Item($r, 2).Text).Trim()
            if ([string]::IsNullOrWhiteSpace($entidad) -or [string]::IsNullOrWhiteSpace($empresa)) { continue }
            $registros += [pscustomobject]@{
                Entidad         = $entidad
                Empresa         = $empresa
                Concepto        = ([string]$ws.Cells.Item($r, 3).Text).Trim()
                NroPrestamo     = ([string]$ws.Cells.Item($r, 4).Text).Trim()
                NroCuota        = [int]([string]$ws.Cells.Item($r, 5).Text -replace '[^\d\-]', '' -replace '^$','0')
                Capital         = ConvertTo-SqlDecimal $ws.Cells.Item($r, 6).Value2
                Iva             = ConvertTo-SqlDecimal $ws.Cells.Item($r, 7).Value2
                IntFin          = ConvertTo-SqlDecimal $ws.Cells.Item($r, 8).Value2
                Sellado         = ConvertTo-SqlDecimal $ws.Cells.Item($r, 9).Value2
                IntResarc       = ConvertTo-SqlDecimal $ws.Cells.Item($r,10).Value2
                ImporteCuota    = ConvertTo-SqlDecimal $ws.Cells.Item($r,11).Value2
                FechaVto        = ConvertTo-SqlDate    $ws.Cells.Item($r,12).Value2
                Estado          = ([string]$ws.Cells.Item($r,13).Text).Trim()
                Condicion       = ([string]$ws.Cells.Item($r,15).Text).Trim()
                Op              = ([string]$ws.Cells.Item($r,16).Text).Trim()
                Observacion     = ([string]$ws.Cells.Item($r,17).Text).Trim()
            }
        }
        Write-Host "  Leídas $($registros.Count) filas útiles" -ForegroundColor Gray
        if ($registros.Count -eq 0) { throw "No se pudo leer ninguna fila de PRESTAMOS" }

        $archivo = Split-Path $Path -Leaf
        $rows = ($registros | ForEach-Object {
            $fv = if ($_.FechaVto) { SqlStr $_.FechaVto } else { 'NULL' }
            "($(SqlStr $_.Entidad), $(SqlStr $_.Empresa), $(SqlStr $_.Concepto), $(SqlStr $_.NroPrestamo), $($_.NroCuota), $($_.Capital), $($_.Iva), $($_.IntFin), $($_.Sellado), $($_.IntResarc), $($_.ImporteCuota), $fv, $(SqlStr $_.Estado), $(SqlStr $_.Condicion), $(SqlStr $_.Op), $(SqlStr $_.Observacion), $(SqlStr $archivo))"
        }) -join ",`n"

        $sql = @"
DELETE FROM dbo.Manual_Prestamos WHERE _archivoOrigen = $(SqlStr $archivo);

INSERT INTO dbo.Manual_Prestamos
    (EntidadFinanciera, EmpresaExcel, Concepto, NumeroPrestamo, NroCuota,
     Capital, Iva, InteresFinanciero, Sellado, InteresResarcitorio, ImporteCuota,
     FechaVto, Estado, Condicion, Op, Observacion, _archivoOrigen)
SELECT EntidadFinanciera, EmpresaExcel, Concepto, NumeroPrestamo, NroCuota,
       Capital, Iva, InteresFinanciero, Sellado, InteresResarcitorio, ImporteCuota,
       CAST(FechaVto AS DATE), Estado, Condicion, Op, Observacion, _archivoOrigen
FROM (VALUES
$rows
) v (EntidadFinanciera, EmpresaExcel, Concepto, NumeroPrestamo, NroCuota,
     Capital, Iva, InteresFinanciero, Sellado, InteresResarcitorio, ImporteCuota,
     FechaVto, Estado, Condicion, Op, Observacion, _archivoOrigen);

SELECT COUNT(*) AS Total,
       SUM(CASE WHEN Estado='PENDIENTE' THEN 1 ELSE 0 END) AS Pendientes,
       SUM(CASE WHEN Estado='PENDIENTE' AND FechaVto >= CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) AS PorVencer
FROM dbo.Manual_Prestamos WHERE _archivoOrigen = $(SqlStr $archivo);
"@
        $r = Invoke-SqlScalar $sql
        Write-Host ("  Insertadas: {0}  (Pendientes: {1}, por vencer: {2})" -f $r.Total, $r.Pendientes, $r.PorVencer) -ForegroundColor Green
        return @{ Filas = $registros.Count; Pendientes = $r.Pendientes; PorVencer = $r.PorVencer }
    } finally { Close-Excel $ctx }
}

# --------- Ingesta: PLANES ARCA / hoja "PLANES" -----------------------------
# Header en R4. Grano: fila por cuota. Filtrado de vigencia se hace en la vista.

function Ingest-Planes {
    param([string]$Path)
    Write-Host "► Planes ARCA: $Path" -ForegroundColor Cyan
    $ctx = Open-ExcelReadOnly -Path $Path
    try {
        $ws = $ctx.Book.Worksheets.Item('PLANES')
        $filas = $ws.UsedRange.Rows.Count
        # Cols (header R4): 1:Entidad 2:Empresa 3:Concepto 4:EstadoDelPlan 5:NroPlan
        # 6:Cuota 7:Capital 8:IVA 9:IntFin 10:Sellado 11:IntResarc 12:ImporteCuota
        # 13:FechaVto 14:Estado 15:MesAnio 16:Condicion 17:Op
        $registros = @()
        for ($r = 5; $r -le $filas; $r++) {
            $entidad = ([string]$ws.Cells.Item($r, 1).Text).Trim()
            $empresa = ([string]$ws.Cells.Item($r, 2).Text).Trim()
            if ([string]::IsNullOrWhiteSpace($entidad) -or [string]::IsNullOrWhiteSpace($empresa)) { continue }
            $registros += [pscustomobject]@{
                Entidad         = $entidad
                Empresa         = $empresa
                Concepto        = ([string]$ws.Cells.Item($r, 3).Text).Trim()
                EstadoPlan      = ([string]$ws.Cells.Item($r, 4).Text).Trim()
                NroPlan         = ([string]$ws.Cells.Item($r, 5).Text).Trim()
                NroCuota        = [int]([string]$ws.Cells.Item($r, 6).Text -replace '[^\d\-]', '' -replace '^$','0')
                Capital         = ConvertTo-SqlDecimal $ws.Cells.Item($r, 7).Value2
                Iva             = ConvertTo-SqlDecimal $ws.Cells.Item($r, 8).Value2
                IntFin          = ConvertTo-SqlDecimal $ws.Cells.Item($r, 9).Value2
                Sellado         = ConvertTo-SqlDecimal $ws.Cells.Item($r,10).Value2
                IntResarc       = ConvertTo-SqlDecimal $ws.Cells.Item($r,11).Value2
                ImporteCuota    = ConvertTo-SqlDecimal $ws.Cells.Item($r,12).Value2
                FechaVto        = ConvertTo-SqlDate    $ws.Cells.Item($r,13).Value2
                Estado          = ([string]$ws.Cells.Item($r,14).Text).Trim()
                Condicion       = ([string]$ws.Cells.Item($r,16).Text).Trim()
                Op              = ([string]$ws.Cells.Item($r,17).Text).Trim()
            }
        }
        Write-Host "  Leídas $($registros.Count) filas útiles" -ForegroundColor Gray
        if ($registros.Count -eq 0) { throw "No se pudo leer ninguna fila de PLANES" }

        $archivo = Split-Path $Path -Leaf
        $rows = ($registros | ForEach-Object {
            $fv = if ($_.FechaVto) { SqlStr $_.FechaVto } else { 'NULL' }
            "($(SqlStr $_.Entidad), $(SqlStr $_.Empresa), $(SqlStr $_.Concepto), $(SqlStr $_.EstadoPlan), $(SqlStr $_.NroPlan), $($_.NroCuota), $($_.Capital), $($_.Iva), $($_.IntFin), $($_.Sellado), $($_.IntResarc), $($_.ImporteCuota), $fv, $(SqlStr $_.Estado), $(SqlStr $_.Condicion), $(SqlStr $_.Op), $(SqlStr $archivo))"
        }) -join ",`n"

        $sql = @"
DELETE FROM dbo.Manual_PlanesArca WHERE _archivoOrigen = $(SqlStr $archivo);

INSERT INTO dbo.Manual_PlanesArca
    (EntidadFinanciera, EmpresaExcel, Concepto, EstadoPlan, NumeroPlan, NroCuota,
     Capital, Iva, InteresFinanciero, Sellado, InteresResarcitorio, ImporteCuota,
     FechaVto, Estado, Condicion, Op, _archivoOrigen)
SELECT EntidadFinanciera, EmpresaExcel, Concepto, EstadoPlan, NumeroPlan, NroCuota,
       Capital, Iva, InteresFinanciero, Sellado, InteresResarcitorio, ImporteCuota,
       CAST(FechaVto AS DATE), Estado, Condicion, Op, _archivoOrigen
FROM (VALUES
$rows
) v (EntidadFinanciera, EmpresaExcel, Concepto, EstadoPlan, NumeroPlan, NroCuota,
     Capital, Iva, InteresFinanciero, Sellado, InteresResarcitorio, ImporteCuota,
     FechaVto, Estado, Condicion, Op, _archivoOrigen);

SELECT COUNT(*) AS Total,
       SUM(CASE WHEN Estado='PENDIENTE' AND EstadoPlan='VIGENTE' THEN 1 ELSE 0 END) AS VigentePendiente,
       SUM(CASE WHEN Estado='PENDIENTE' AND EstadoPlan='VIGENTE' AND FechaVto >= CAST(GETDATE() AS DATE) THEN 1 ELSE 0 END) AS PorVencer,
       SUM(CASE WHEN EstadoPlan='PLAN CADUCO' THEN 1 ELSE 0 END) AS Caducos
FROM dbo.Manual_PlanesArca WHERE _archivoOrigen = $(SqlStr $archivo);
"@
        $r = Invoke-SqlScalar $sql
        Write-Host ("  Insertadas: {0}  (Vig+Pend: {1}, por vencer: {2}, caducos: {3})" -f $r.Total, $r.VigentePendiente, $r.PorVencer, $r.Caducos) -ForegroundColor Green
        return @{ Filas = $registros.Count; PorVencer = $r.PorVencer; Caducos = $r.Caducos }
    } finally { Close-Excel $ctx }
}

function Ingest-Impositivo {
    param([string]$Path)
    Write-Host "► IMPOSITIVO: $Path" -ForegroundColor Cyan
    $ctx = Open-ExcelReadOnly -Path $Path
    try {
        $ws = $ctx.Book.Worksheets.Item('IMPOSITIVO')
        $filas = $ws.UsedRange.Rows.Count
        # Cols (header R3): 1:RazonSocial 2:Grupo 3:Concepto 4:Subconcepto 5:Periodo(date)
        # 6:Vencimiento(date) 7:Importe 8:Estado 9:Condicion 10:DiasMora 11:Registracion 12:Op 13:Observacion
        $registros = @()
        for ($r = 4; $r -le $filas; $r++) {
            $rs = ([string]$ws.Cells.Item($r, 1).Text).Trim()
            $imp = $ws.Cells.Item($r, 7).Value2
            if ([string]::IsNullOrWhiteSpace($rs) -or $null -eq $imp) { continue }
            $registros += [pscustomobject]@{
                RazonSocial   = $rs
                Grupo         = ([string]$ws.Cells.Item($r, 2).Text).Trim()
                Concepto      = ([string]$ws.Cells.Item($r, 3).Text).Trim()
                Subconcepto   = ([string]$ws.Cells.Item($r, 4).Text).Trim()
                Periodo       = ConvertTo-SqlDate $ws.Cells.Item($r, 5).Value2
                Vencimiento   = ConvertTo-SqlDate $ws.Cells.Item($r, 6).Value2
                Importe       = ConvertTo-SqlDecimal $imp
                Estado        = ([string]$ws.Cells.Item($r, 8).Text).Trim()
                Condicion     = ([string]$ws.Cells.Item($r, 9).Text).Trim()
                DiasMora      = [int]([string]$ws.Cells.Item($r,10).Text -replace '[^\d\-]', '' -replace '^$','0')
                Registracion  = ([string]$ws.Cells.Item($r,11).Text).Trim()
                Op            = ([string]$ws.Cells.Item($r,12).Text).Trim()
                Observacion   = ([string]$ws.Cells.Item($r,13).Text).Trim()
            }
        }
        Write-Host "  Leídas $($registros.Count) filas útiles" -ForegroundColor Gray
        if ($registros.Count -eq 0) { throw "No se pudo leer ninguna fila de IMPOSITIVO" }

        $archivo = Split-Path $Path -Leaf
        $rows = ($registros | ForEach-Object {
            $per = if ($_.Periodo)     { SqlStr $_.Periodo }     else { 'NULL' }
            $ven = if ($_.Vencimiento) { SqlStr $_.Vencimiento } else { 'NULL' }
            "($(SqlStr $_.RazonSocial), $(SqlStr $_.Grupo), $(SqlStr $_.Concepto), $(SqlStr $_.Subconcepto), $per, $ven, $($_.Importe), $(SqlStr $_.Estado), $(SqlStr $_.Condicion), $($_.DiasMora), $(SqlStr $_.Registracion), $(SqlStr $_.Op), $(SqlStr $_.Observacion), $(SqlStr $archivo))"
        }) -join ",`n"

        $sql = @"
DELETE FROM dbo.Manual_Impositivo WHERE _archivoOrigen = $(SqlStr $archivo);

INSERT INTO dbo.Manual_Impositivo
    (RazonSocialExcel, Grupo, Concepto, Subconcepto, Periodo, FechaVencimiento,
     Importe, Estado, Condicion, DiasMora, Registracion, OrdenPago, Observacion, _archivoOrigen)
SELECT RazonSocialExcel, Grupo, Concepto, Subconcepto,
       CAST(Periodo AS DATE), CAST(FechaVencimiento AS DATE),
       Importe, Estado, Condicion, DiasMora, Registracion, OrdenPago, Observacion, _archivoOrigen
FROM (VALUES
$rows
) v (RazonSocialExcel, Grupo, Concepto, Subconcepto, Periodo, FechaVencimiento,
     Importe, Estado, Condicion, DiasMora, Registracion, OrdenPago, Observacion, _archivoOrigen);

SELECT COUNT(*) AS Total,
       SUM(CASE WHEN Estado='PENDIENTE' THEN 1 ELSE 0 END) AS Pendientes,
       SUM(CASE WHEN Estado='PAGO'      THEN 1 ELSE 0 END) AS Pagos,
       SUM(CASE WHEN Estado='PLAN DE PAGO' THEN 1 ELSE 0 END) AS EnPlan,
       SUM(CASE WHEN Estado='PENDIENTE' THEN Importe ELSE 0 END) AS ImportePendiente
FROM dbo.Manual_Impositivo WHERE _archivoOrigen = $(SqlStr $archivo);
"@
        $r = Invoke-SqlScalar $sql
        Write-Host ("  Insertadas: {0}  (Pendientes: {1}, Pagos: {2}, EnPlan: {3}, `$ pendiente: {4})" -f $r.Total, $r.Pendientes, $r.Pagos, $r.EnPlan, $r.ImportePendiente) -ForegroundColor Green
        return @{ Filas = $registros.Count; Pendientes = $r.Pendientes; ImportePendiente = $r.ImportePendiente }
    } finally { Close-Excel $ctx }
}

# --------- Main --------------------------------------------------------------

$soloFlag = $SoloBancos -or $SoloTarjetas -or $SoloPrestamos -or $SoloPlanes -or $SoloImpositivo
$hazBancos     = -not $soloFlag -or $SoloBancos
$hazTarjetas   = -not $soloFlag -or $SoloTarjetas
$hazPrestamos  = -not $soloFlag -or $SoloPrestamos
$hazPlanes     = -not $soloFlag -or $SoloPlanes
$hazImpositivo = -not $soloFlag -or $SoloImpositivo

$resumen = @{ Bancos = $null; Tarjetas = $null; Prestamos = $null; Planes = $null; Impositivo = $null }

if ($hazBancos)     { $resumen.Bancos     = Ingest-Bancos     -Path $PathBancos }
if ($hazTarjetas)   { $resumen.Tarjetas   = Ingest-Tarjetas   -Path $PathTarjetas }
if ($hazPrestamos)  { $resumen.Prestamos  = Ingest-Prestamos  -Path $PathPrestamos }
if ($hazPlanes)     { $resumen.Planes     = Ingest-Planes     -Path $PathPlanes }
if ($hazImpositivo) { $resumen.Impositivo = Ingest-Impositivo -Path $PathPlanes }

Write-Host "`n=== Resumen ingesta ===" -ForegroundColor Cyan
if ($resumen.Bancos)     { Write-Host ("  Bancos:     {0} filas, fechas: {1}" -f $resumen.Bancos.Filas, ($resumen.Bancos.Fechas -join ', ')) }
if ($resumen.Tarjetas)   { Write-Host ("  Tarjetas:   {0} filas" -f $resumen.Tarjetas.Filas) }
if ($resumen.Prestamos)  { Write-Host ("  Prestamos:  {0} filas ({1} por vencer)" -f $resumen.Prestamos.Filas, $resumen.Prestamos.PorVencer) }
if ($resumen.Planes)     { Write-Host ("  Planes:     {0} filas ({1} vig. por vencer, {2} caducos)" -f $resumen.Planes.Filas, $resumen.Planes.PorVencer, $resumen.Planes.Caducos) }
if ($resumen.Impositivo) { Write-Host ("  Impositivo: {0} filas ({1} pendientes, `$ {2})" -f $resumen.Impositivo.Filas, $resumen.Impositivo.Pendientes, $resumen.Impositivo.ImportePendiente) }
Write-Host "OK" -ForegroundColor Green
