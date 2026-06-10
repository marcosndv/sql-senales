# sql.ps1 - Helper para ejecutar consultas contra el servidor BI configurado.
# Uso:
#   .\sql.ps1 "SELECT TOP 10 * FROM sys.databases"
#   .\sql.ps1 -File .\query.sql
#   .\sql.ps1 -Database master "SELECT @@VERSION"
#   .\sql.ps1 -Format Json "SELECT name FROM sys.databases"
#   .\sql.ps1 -ShowConnection
[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromPipeline = $true)]
    [string]$Query,

    [Alias('f')]
    [string]$File,

    [Alias('d')]
    [string]$Database,

    [ValidateSet('Table', 'Json', 'Csv', 'List', 'Raw')]
    [string]$Format = 'Table',

    [int]$MaxRows = 0,

    [switch]$ShowConnection
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$helperDir = Join-Path $here '.sql-helper'
$configPath = Join-Path $helperDir 'connection.json'
$pwPath = Join-Path $helperDir 'password.dpapi'

if (-not (Test-Path $configPath)) { throw "Falta $configPath" }
if (-not (Test-Path $pwPath))     { throw "Falta $pwPath" }

$cfg = Get-Content $configPath -Raw | ConvertFrom-Json
$encrypted = Get-Content $pwPath -Raw
$secure = ConvertTo-SecureString -String $encrypted
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $password = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

$dataSource = if ($cfg.instance) { "$($cfg.server)\$($cfg.instance)" } else { $cfg.server }
$db = if ($Database) { $Database } else { $cfg.defaultDatabase }

$builder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$builder['Data Source'] = $dataSource
if ($db) { $builder['Initial Catalog'] = $db }
$builder['User ID'] = $cfg.user
$builder['Password'] = $password
$builder['Connect Timeout'] = [int]$cfg.connectionTimeout
$builder['TrustServerCertificate'] = [bool]$cfg.trustServerCertificate
$builder['Encrypt'] = [bool]$cfg.encrypt
$builder['Application Name'] = 'sql.ps1 helper'

if ($ShowConnection) {
    $safe = $builder.ConnectionString -replace 'Password=[^;]+', 'Password=***'
    Write-Output "Cadena: $safe"
    Write-Output "Servidor:    $dataSource"
    Write-Output "Base actual: $db"
    Write-Output "Usuario:     $($cfg.user)"
    return
}

if ($File) {
    if (-not (Test-Path $File)) { throw "No existe el archivo: $File" }
    $Query = Get-Content $File -Raw
}

if (-not $Query) { throw "Pasa una consulta como argumento, por -File, o por pipeline." }

$conn = New-Object System.Data.SqlClient.SqlConnection($builder.ConnectionString)
try {
    $conn.Open()
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $Query
    $cmd.CommandTimeout = [int]$cfg.commandTimeout

    $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $ds = New-Object System.Data.DataSet
    [void]$adapter.Fill($ds)

    if ($ds.Tables.Count -eq 0) {
        Write-Output "(sin resultset)"
        return
    }

    for ($i = 0; $i -lt $ds.Tables.Count; $i++) {
        $tbl = $ds.Tables[$i]
        if ($ds.Tables.Count -gt 1) { Write-Output "--- Resultset $($i + 1) ($($tbl.Rows.Count) filas) ---" }

        $cols = @($tbl.Columns | ForEach-Object { $_.ColumnName })
        $rows = @($tbl.Rows)
        if ($MaxRows -gt 0) { $rows = $rows | Select-Object -First $MaxRows }
        $shaped = $rows | Select-Object -Property $cols

        switch ($Format) {
            'Table' { $shaped | Format-Table -AutoSize | Out-String -Width 4096 | Write-Output }
            'List'  { $shaped | Format-List | Out-String | Write-Output }
            'Json'  { $shaped | ConvertTo-Json -Depth 6 | Write-Output }
            'Csv'   { $shaped | ConvertTo-Csv -NoTypeInformation | Write-Output }
            'Raw'   { $shaped | Write-Output }
        }
    }
} finally {
    if ($conn.State -eq 'Open') { $conn.Close() }
    $password = $null
}
