# ============================================================================
#  PROTOTIPO / SPEC — NO ejecutar en producción.
#  Sirve de referencia para arreglar el ETL oficial.
# ============================================================================
#
# Problema detectado (junio/2026):
#   El ETL deja `EMPR0006.OFICIAL_LIBROFONDOSDETALLADO` con 0 filas, pero el DBF
#   origen `librofondosdetallado.dbf` tiene 512.521 registros (143 MB) — ahí
#   están los echeqs emitidos por orden de pago que no tenemos en SQL.
#
# Tabla DBF clave:
#   librofondosdetallado.dbf  (Visual FoxPro, version 0x30, recLen=279, 29 col)
#   librofondos.dbf           (cabecera, recLen=158, 13 col, FECHA del asiento)
#
# Mapeo de campos importantes (offset dentro del record, +1 por deletion flag):
#     CUENTA       I (4)   off  9   código de cuenta contable
#     CHQFECHA     D (8)   off 21   YYYYMMDD — fecha emisión cheque
#     CHQVENCE     D (8)   off 29   YYYYMMDD — fecha "Cobro/Pago" (Excel)
#     CHQNUMERO    N (8)   off 37   número de echeq como ASCII
#     CHQORDEN     C (50)  off 45   beneficiario / orden
#     CONCILIADO   D (8)   off 210  YYYYMMDD — fecha conciliación bancaria
#     IMPORTE      N (15)  off 230  decimal — negativo egreso, positivo cancelación
#     LBRFONDOS    I (4)   off  1   FK a librofondos.CODIGO (FECHA del asiento)
#
# Reglas validadas para el informe "Cheques propios diferidos pendientes"
# (replica exacta del Excel ERP, validado al 31/7/2025: -497.752.237,96):
#
#   1) CUENTA = 211300        -- "Cheques de Pago Diferido a Pagar"
#   2) CHQNUMERO > 0
#   3) CHQVENCE > @FechaCorte -- aún no vence al corte
#   4) JOIN con librofondos por LBRFONDOS=CODIGO, filtrar FECHA <= @FechaCorte
#   5) Agrupar por CHQNUMERO, sumar IMPORTE
#       -> Pendientes = los que tienen SUM(IMPORTE) < 0
#       (los con SUM = 0 ya fueron cancelados con un asiento posterior)
#
# Validación realizada contra Excel "Los Valientes / Cheques a Pagar 31/7/2025":
#   - 103 cheques únicos en pendientes (Excel mostraba 105 líneas con splits)
#   - Total: -497.752.237,96 — EXACTO al Excel
#   - El echeq 90023688 (ECHOS DU TERRAIN, -1.590.579,39) coincide fila a fila.
#
# Empresas afectadas (también necesitan copiarse estos DBF al SQL):
#   EMPR0006, EMPR0010, EMPR0011, EMPR0012 (las que tienen chequeras configuradas).
#   EMPR0011 ya tiene la fuente alterna `OFICIAL_EMPR0011-DATOS` con los echeqs,
#   pero las demás no — todas dependen de LIBROFONDOSDETALLADO.
#
# Encoding: char fields en CP1252 (Latin-1 Windows), no UTF-8.
#
# ----------------------------------------------------------------------------
# Lo que hace este script (si se ejecuta):
#   * Parsea ambos DBF binariamente con PowerShell puro (sin VFP OLEDB).
#   * Bulk-insert con SqlBulkCopy a las tablas existentes en SQL.
#   * Mapea LIQTARJETA del DBF a "no-op" (la tabla SQL no tiene esa col).
#   * Ints binarios del DBF van como string a las cols nvarchar(255) de SQL
#     (consistente con cómo el ETL real carga las otras empresas).
#
# Por qué NO usarlo en producción:
#   * PowerShell parseando 512k records tarda ~5-10 min — el ETL real ya tiene
#     pipeline DBF→SQL probablemente vía VFP OLEDB / SSIS, mucho más rápido.
#   * No tiene control de incremental, idempotencia, ni manejo de errores
#     que un ETL serio necesita.
# ============================================================================

[CmdletBinding()]
param(
    [string]$DbfDir = "C:\Users\marco\OneDrive\Documentos\Desarrollos Claude\Sql Señales\Los valientes\EMPR0006",
    [string]$Schema = "EMPR0006",
    [switch]$Truncate
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$cfg = Get-Content (Join-Path $root '.sql-helper\connection.json') -Raw | ConvertFrom-Json
$secure = ConvertTo-SecureString -String (Get-Content (Join-Path $root '.sql-helper\password.dpapi') -Raw)
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try { $pwd = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

$ds = if ($cfg.instance) { "$($cfg.server)\$($cfg.instance)" } else { $cfg.server }
$cs = "Data Source=$ds;Initial Catalog=$($cfg.defaultDatabase);User ID=$($cfg.user);Password=$pwd;Encrypt=True;TrustServerCertificate=True;Connect Timeout=30"

$encAscii = [System.Text.Encoding]::ASCII
$encWin   = [System.Text.Encoding]::GetEncoding(1252)
$inv      = [System.Globalization.CultureInfo]::InvariantCulture

function Read-DbfHeader {
    param([byte[]]$Bytes)
    [PSCustomObject]@{
        Records = [System.BitConverter]::ToUInt32($Bytes, 4)
        HdrLen  = [System.BitConverter]::ToUInt16($Bytes, 8)
        RecLen  = [System.BitConverter]::ToUInt16($Bytes, 10)
    }
}

function Parse-Date($s) {
    $s = $s.Trim()
    if ($s -eq '' -or $s -eq '00000000') { return [DBNull]::Value }
    $dt = [DateTime]::MinValue
    if ([DateTime]::TryParseExact($s, 'yyyyMMdd', $inv, [System.Globalization.DateTimeStyles]::None, [ref]$dt)) { return $dt }
    return [DBNull]::Value
}
function Parse-IntN($s) {
    $s = $s.Trim()
    if ($s -eq '') { return [DBNull]::Value }
    $v = [int64]0
    if ([int64]::TryParse($s, [ref]$v)) { return [int]$v }
    return [DBNull]::Value
}
function Parse-Dec($s) {
    $s = $s.Trim()
    if ($s -eq '') { return [DBNull]::Value }
    $v = [decimal]0
    if ([decimal]::TryParse($s, [System.Globalization.NumberStyles]::Any, $inv, [ref]$v)) { return $v }
    return [DBNull]::Value
}
function ToStr($v) { if ($v -eq $null) { return [DBNull]::Value } else { return [string]$v } }

# ---------- LIBROFONDOS ----------
$lfDt = New-Object System.Data.DataTable
foreach ($c in 'CODIGO','COMPROB','ENTIDAD','ENTEESTABL','COBRADOR','ARCHIVO','COMENTARIO','FIRMA') { [void]$lfDt.Columns.Add($c, [string]) }
foreach ($c in 'FECHA')                            { [void]$lfDt.Columns.Add($c, [DateTime]) }
foreach ($c in 'PTOEMISOR','NUMERO')              { [void]$lfDt.Columns.Add($c, [int]) }
foreach ($c in 'TOTAL')                            { [void]$lfDt.Columns.Add($c, [decimal]) }
foreach ($c in 'CERRADO')                          { [void]$lfDt.Columns.Add($c, [bool]) }
[void]$lfDt.Columns.Add('_fecha_carga', [DateTime])
[void]$lfDt.Columns.Add('_id_carga',    [Guid])

# Orden final igual al de la tabla SQL (sin _id IDENTITY)
$lfCols = @('CODIGO','FECHA','COMPROB','PTOEMISOR','NUMERO','ENTIDAD','ENTEESTABL','COBRADOR','COMENTARIO','TOTAL','CERRADO','FIRMA','ARCHIVO','_fecha_carga','_id_carga')

$lfPath = Join-Path $DbfDir 'librofondos.dbf'
$lfBytes = [System.IO.File]::ReadAllBytes($lfPath)
$lfH = Read-DbfHeader $lfBytes
$now    = [DateTime]::Now
$loadId = [Guid]::NewGuid()
Write-Host "librofondos: $($lfH.Records) records (recLen=$($lfH.RecLen))..."

for ($i = 0; $i -lt $lfH.Records; $i++) {
    $b = $lfH.HdrLen + $i * $lfH.RecLen
    if ($lfBytes[$b] -eq 0x2A) { continue }
    $row = $lfDt.NewRow()
    # offsets desde $b (saltando deletion flag con +1)
    $row.CODIGO       = ToStr ([System.BitConverter]::ToInt32($lfBytes, $b + 1))
    $row.FECHA        = Parse-Date ($encAscii.GetString($lfBytes, $b + 5, 8))
    $row.COMPROB      = ToStr ([System.BitConverter]::ToInt32($lfBytes, $b + 13))
    $row.PTOEMISOR    = Parse-IntN ($encAscii.GetString($lfBytes, $b + 17, 5))
    $row.NUMERO       = Parse-IntN ($encAscii.GetString($lfBytes, $b + 22, 8))
    $row.ENTIDAD      = ToStr ([System.BitConverter]::ToInt32($lfBytes, $b + 30))
    $row.ENTEESTABL   = ToStr ([System.BitConverter]::ToInt32($lfBytes, $b + 34))
    $row.COBRADOR     = ToStr ([System.BitConverter]::ToInt32($lfBytes, $b + 38))
    $row.COMENTARIO   = $encWin.GetString($lfBytes, $b + 42, 80).TrimEnd()
    $row.TOTAL        = Parse-Dec ($encAscii.GetString($lfBytes, $b + 122, 15))
    $row.CERRADO      = ([char]$lfBytes[$b + 137] -in 'T','t','Y','y')
    $row.FIRMA        = $encWin.GetString($lfBytes, $b + 138, 16).TrimEnd()
    $row.ARCHIVO      = ToStr ([System.BitConverter]::ToInt32($lfBytes, $b + 154))
    $row['_fecha_carga'] = $now
    $row['_id_carga']    = $loadId
    $lfDt.Rows.Add($row)
}
Write-Host "  DataTable construida: $($lfDt.Rows.Count) filas"

# ---------- LIBROFONDOSDETALLADO ----------
$ldDt = New-Object System.Data.DataTable
foreach ($c in 'LBRFONDOS','CLASEFONDO','CUENTA','CENTRO','CHQTERCERO','CHQORDEN','RETREGIM','TARJETA','COMENTARIO','REFERENCIA','LIBROBANCO','MONEDA') { [void]$ldDt.Columns.Add($c, [string]) }
foreach ($c in 'CHQFECHA','CHQVENCE','RETFECHA','CONCILIADO') { [void]$ldDt.Columns.Add($c, [DateTime]) }
foreach ($c in 'CHQNUMERO','RETEMISOR','RETNUMERO','RETIMPUES','TARJLOTE','TARJCUPON','TARJCUOTAS') { [void]$ldDt.Columns.Add($c, [int]) }
foreach ($c in 'RETBASE','RETTASA','IMPORTE','TIPOCAMBIO','IMPORTEME') { [void]$ldDt.Columns.Add($c, [decimal]) }
[void]$ldDt.Columns.Add('_fecha_carga', [DateTime])
[void]$ldDt.Columns.Add('_id_carga',    [Guid])

$ldPath = Join-Path $DbfDir 'librofondosdetallado.dbf'
$ldBytes = [System.IO.File]::ReadAllBytes($ldPath)
$ldH = Read-DbfHeader $ldBytes
Write-Host "librofondosdetallado: $($ldH.Records) records (recLen=$($ldH.RecLen))..."

$sw = [System.Diagnostics.Stopwatch]::StartNew()
for ($i = 0; $i -lt $ldH.Records; $i++) {
    $b = $ldH.HdrLen + $i * $ldH.RecLen
    if ($ldBytes[$b] -eq 0x2A) { continue }
    $row = $ldDt.NewRow()
    $row.LBRFONDOS    = ToStr ([System.BitConverter]::ToInt32($ldBytes, $b + 1))
    $row.CLASEFONDO   = ToStr ([System.BitConverter]::ToInt32($ldBytes, $b + 5))
    $row.CUENTA       = ToStr ([System.BitConverter]::ToInt32($ldBytes, $b + 9))
    $row.CENTRO       = ToStr ([System.BitConverter]::ToInt32($ldBytes, $b + 13))
    $row.CHQTERCERO   = ToStr ([System.BitConverter]::ToInt32($ldBytes, $b + 17))
    $row.CHQFECHA     = Parse-Date ($encAscii.GetString($ldBytes, $b + 21, 8))
    $row.CHQVENCE     = Parse-Date ($encAscii.GetString($ldBytes, $b + 29, 8))
    $row.CHQNUMERO    = Parse-IntN ($encAscii.GetString($ldBytes, $b + 37, 8))
    $row.CHQORDEN     = $encWin.GetString($ldBytes, $b + 45, 50).TrimEnd()
    $row.RETFECHA     = Parse-Date ($encAscii.GetString($ldBytes, $b + 95, 8))
    $row.RETEMISOR    = Parse-IntN ($encAscii.GetString($ldBytes, $b + 103, 5))
    $row.RETNUMERO    = Parse-IntN ($encAscii.GetString($ldBytes, $b + 108, 8))
    $row.RETIMPUES    = Parse-IntN ($encAscii.GetString($ldBytes, $b + 116, 1))
    $row.RETREGIM     = ToStr ([System.BitConverter]::ToInt32($ldBytes, $b + 117))
    $row.RETBASE      = Parse-Dec ($encAscii.GetString($ldBytes, $b + 121, 15))
    $row.RETTASA      = Parse-Dec ($encAscii.GetString($ldBytes, $b + 136, 6))
    $row.TARJETA      = ToStr ([System.BitConverter]::ToInt32($ldBytes, $b + 142))
    $row.TARJLOTE     = Parse-IntN ($encAscii.GetString($ldBytes, $b + 146, 4))
    $row.TARJCUPON    = Parse-IntN ($encAscii.GetString($ldBytes, $b + 150, 8))
    $row.TARJCUOTAS   = Parse-IntN ($encAscii.GetString($ldBytes, $b + 158, 2))
    $row.COMENTARIO   = $encWin.GetString($ldBytes, $b + 160, 50).TrimEnd()
    $row.CONCILIADO   = Parse-Date ($encAscii.GetString($ldBytes, $b + 210, 8))
    $row.REFERENCIA   = ToStr ([System.BitConverter]::ToInt32($ldBytes, $b + 218))
    $row.LIBROBANCO   = ToStr ([System.BitConverter]::ToInt32($ldBytes, $b + 222))
    # LIQTARJETA en DBF (offset 226, len 4) — la tabla SQL no la tiene, se omite.
    $row.IMPORTE      = Parse-Dec ($encAscii.GetString($ldBytes, $b + 230, 15))
    $row.MONEDA       = ToStr ([System.BitConverter]::ToInt32($ldBytes, $b + 245))
    $row.TIPOCAMBIO   = Parse-Dec ($encAscii.GetString($ldBytes, $b + 249, 15))
    $row.IMPORTEME    = Parse-Dec ($encAscii.GetString($ldBytes, $b + 264, 15))
    $row['_fecha_carga'] = $now
    $row['_id_carga']    = $loadId
    $ldDt.Rows.Add($row)
    if ($i % 50000 -eq 0 -and $i -gt 0) { Write-Host ("  parseados {0:N0} en {1:N1}s" -f $i, $sw.Elapsed.TotalSeconds) }
}
Write-Host "  DataTable construida: $($ldDt.Rows.Count) filas en $($sw.Elapsed.TotalSeconds)s"

# ---------- Bulk insert ----------
$conn = New-Object System.Data.SqlClient.SqlConnection($cs)
$conn.Open()
try {
    if ($Truncate) {
        foreach ($t in 'OFICIAL_LIBROFONDOS','OFICIAL_LIBROFONDOSDETALLADO') {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "TRUNCATE TABLE $Schema.$t"
            $cmd.ExecuteNonQuery() | Out-Null
            Write-Host "TRUNCATE $Schema.$t OK"
        }
    }

    $sw.Restart()
    $bc = New-Object System.Data.SqlClient.SqlBulkCopy($conn, [System.Data.SqlClient.SqlBulkCopyOptions]::TableLock, $null)
    $bc.DestinationTableName = "[$Schema].[OFICIAL_LIBROFONDOS]"
    $bc.BatchSize = 5000
    foreach ($c in $lfDt.Columns) { [void]$bc.ColumnMappings.Add($c.ColumnName, $c.ColumnName) }
    $bc.WriteToServer($lfDt)
    Write-Host "Bulk LIBROFONDOS: $($lfDt.Rows.Count) filas en $($sw.Elapsed.TotalSeconds)s"

    $sw.Restart()
    $bc2 = New-Object System.Data.SqlClient.SqlBulkCopy($conn, [System.Data.SqlClient.SqlBulkCopyOptions]::TableLock, $null)
    $bc2.DestinationTableName = "[$Schema].[OFICIAL_LIBROFONDOSDETALLADO]"
    $bc2.BatchSize = 5000
    foreach ($c in $ldDt.Columns) { [void]$bc2.ColumnMappings.Add($c.ColumnName, $c.ColumnName) }
    $bc2.WriteToServer($ldDt)
    Write-Host "Bulk LIBROFONDOSDETALLADO: $($ldDt.Rows.Count) filas en $($sw.Elapsed.TotalSeconds)s"
} finally {
    $conn.Close()
    $pwd = $null
}
