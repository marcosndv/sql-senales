# Parser DBF / VFP minimo para inspeccionar schema y leer filas.
# Soporta tipos: C (char), N (numeric), F (float), D (date), L (logical), I (int32), B (double VFP), Y (currency VFP), T (datetime VFP), M (memo - solo flag).
# Uso:
#   .\read_dbf.ps1 -Path foo.dbf -Schema
#   .\read_dbf.ps1 -Path foo.dbf -Top 5
#   .\read_dbf.ps1 -Path foo.dbf -Top 5 -Columns CHEQUE_NUM,IMPORTE
#   .\read_dbf.ps1 -Path foo.dbf -Where { param($r) $r.CHEQUE_NUM -eq 90023688 } -Top 1
#   .\read_dbf.ps1 -Path foo.dbf -Count   # solo cantidad de registros
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$Schema,
    [switch]$Count,
    [int]$Top = 5,
    [string[]]$Columns,
    [scriptblock]$Where,
    [ValidateSet('List','Csv','Json')] [string]$Format = 'List'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $Path)) { throw "No existe: $Path" }

$fs = [System.IO.File]::OpenRead($Path)
$br = New-Object System.IO.BinaryReader($fs)
try {
    $version  = $br.ReadByte()
    $year     = $br.ReadByte()
    $month    = $br.ReadByte()
    $day      = $br.ReadByte()
    $records  = $br.ReadUInt32()
    $hdrLen   = $br.ReadUInt16()
    $recLen   = $br.ReadUInt16()
    $br.ReadBytes(20) | Out-Null

    if ($Count) {
        [PSCustomObject]@{ Path = $Path; Version = ('0x{0:X2}' -f $version); Registros = $records; HeaderLen = $hdrLen; RecordLen = $recLen } | Format-Table -AutoSize
        return
    }

    $fields = New-Object System.Collections.Generic.List[object]
    while ($true) {
        $first = $br.ReadByte()
        if ($first -eq 0x0D) { break }
        $nameBytes = New-Object 'byte[]' 11
        $nameBytes[0] = $first
        for ($i = 1; $i -lt 11; $i++) { $nameBytes[$i] = $br.ReadByte() }
        $name = [System.Text.Encoding]::ASCII.GetString($nameBytes).TrimEnd([char]0).Trim()
        $type = [char]$br.ReadByte()
        $br.ReadBytes(4) | Out-Null   # field data address
        $length = [int]$br.ReadByte()
        $decimals = [int]$br.ReadByte()
        $br.ReadBytes(14) | Out-Null
        $fields.Add([PSCustomObject]@{ Name = $name; Type = $type; Length = $length; Decimals = $decimals })
    }

    if ($Schema) {
        [PSCustomObject]@{ Path = $Path; Version = ('0x{0:X2}' -f $version); Registros = $records; CamposCount = $fields.Count } | Format-List | Out-String | Write-Output
        $fields | Format-Table Name, Type, Length, Decimals -AutoSize | Out-String -Width 200 | Write-Output
        return
    }

    # Saltar al inicio de los datos (hdrLen). Si terminator 0x0D fue leido, la posicion ya es buena, pero los bytes restantes del header pueden incluir backlink en VFP. Asi que forzamos seek.
    $fs.Position = $hdrLen

    $colSet = $null
    if ($Columns) { $colSet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase); foreach ($c in $Columns) { [void]$colSet.Add($c) } }

    $emitted = 0
    $rows = New-Object System.Collections.Generic.List[object]
    $cultureInv = [System.Globalization.CultureInfo]::InvariantCulture

    for ($n = 0; $n -lt $records -and $emitted -lt $Top; $n++) {
        $rec = $br.ReadBytes($recLen)
        if ($rec.Length -lt $recLen) { break }
        $deleted = ([char]$rec[0]) -eq '*'
        if ($deleted) { continue }
        $offset = 1
        $obj = [ordered]@{}
        foreach ($f in $fields) {
            $raw = [byte[]]::new($f.Length)
            [System.Array]::Copy($rec, $offset, $raw, 0, $f.Length)
            $offset += $f.Length
            $val = $null
            switch ($f.Type) {
                'C' { $val = ([System.Text.Encoding]::GetEncoding(1252).GetString($raw)).TrimEnd() }
                'N' {
                    $s = ([System.Text.Encoding]::ASCII.GetString($raw)).Trim()
                    if ($s -eq '' -or $s -eq '.' ) { $val = $null }
                    else {
                        if ($f.Decimals -eq 0) { [int64]$tmp = 0; if ([int64]::TryParse($s, [ref]$tmp)) { $val = $tmp } else { $val = $s } }
                        else { [decimal]$tmp = 0; if ([decimal]::TryParse($s, [System.Globalization.NumberStyles]::Any, $cultureInv, [ref]$tmp)) { $val = $tmp } else { $val = $s } }
                    }
                }
                'F' {
                    $s = ([System.Text.Encoding]::ASCII.GetString($raw)).Trim()
                    if ($s -eq '') { $val = $null } else { [decimal]$tmp = 0; if ([decimal]::TryParse($s, [System.Globalization.NumberStyles]::Any, $cultureInv, [ref]$tmp)) { $val = $tmp } else { $val = $s } }
                }
                'D' {
                    $s = ([System.Text.Encoding]::ASCII.GetString($raw)).Trim()
                    if ($s -eq '' -or $s -eq '00000000') { $val = $null }
                    else { [DateTime]$tmp = [DateTime]::MinValue; if ([DateTime]::TryParseExact($s, 'yyyyMMdd', $cultureInv, [System.Globalization.DateTimeStyles]::None, [ref]$tmp)) { $val = $tmp } else { $val = $s } }
                }
                'L' { $c = [char]$raw[0]; $val = ($c -eq 'T' -or $c -eq 't' -or $c -eq 'Y' -or $c -eq 'y') }
                'I' { $val = [System.BitConverter]::ToInt32($raw, 0) }
                'B' { $val = [System.BitConverter]::ToDouble($raw, 0) }
                'Y' { $val = [decimal]([System.BitConverter]::ToInt64($raw, 0)) / 10000d }   # currency
                'T' {
                    $days = [System.BitConverter]::ToInt32($raw, 0)
                    $ms   = [System.BitConverter]::ToInt32($raw, 4)
                    if ($days -eq 0 -and $ms -eq 0) { $val = $null }
                    else {
                        # Julian day 2299161 = 1582-10-15. VFP epoch is Julian day so adjust:
                        $jd0 = [DateTime]'0001-01-01'
                        $val = $jd0.AddDays($days - 1721426).AddMilliseconds($ms)
                    }
                }
                'M' { $val = "(memo)" }
                default { $val = ([System.Text.Encoding]::GetEncoding(1252).GetString($raw)).TrimEnd() }
            }
            if ($colSet -eq $null -or $colSet.Contains($f.Name)) { $obj[$f.Name] = $val }
        }
        $rowObj = [PSCustomObject]$obj
        if ($Where) {
            try { if (-not (& $Where $rowObj)) { continue } } catch { continue }
        }
        $rows.Add($rowObj) | Out-Null
        $emitted++
    }

    switch ($Format) {
        'List' { $rows | Format-List | Out-String | Write-Output }
        'Csv'  { $rows | ConvertTo-Csv -NoTypeInformation | Write-Output }
        'Json' { $rows | ConvertTo-Json -Depth 5 | Write-Output }
    }
} finally {
    $br.Close()
    $fs.Close()
}
