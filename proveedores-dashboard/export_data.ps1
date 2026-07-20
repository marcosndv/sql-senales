# export_data.ps1 — genera data.json para el dashboard de facturas pendientes de proveedores
# Uso: .\export_data.ps1
# Requiere que sql.ps1 esté en la raíz del repo.

$root   = Split-Path $PSScriptRoot -Parent
$helper = Join-Path $root "sql.ps1"
$out    = Join-Path $PSScriptRoot "data.json"

function Invoke-SQL($q) {
    $json = & $helper -Format Json $q 2>&1
    $result = $json | ConvertFrom-Json -ErrorAction Stop
    if ($result -isnot [array]) { $result = @($result) }
    return $result
}

Write-Host "Exportando datos de facturas pendientes..." -ForegroundColor Cyan

# --- Totales globales ---
$totales = (Invoke-SQL @"
SELECT
  SUM(SaldoPendiente)                                                AS TotalPendiente,
  COUNT(*)                                                           AS CantFacturas,
  COUNT(DISTINCT CUIT)                                               AS CantProveedores,
  COUNT(DISTINCT Empresa)                                            AS CantEmpresas,
  SUM(CASE WHEN DiasVencido > 0 THEN SaldoPendiente ELSE 0 END)     AS TotalVencido,
  SUM(CASE WHEN DiasVencido > 0 THEN 1             ELSE 0 END)      AS CantVencidas,
  AVG(CASE WHEN DiasVencido > 0 THEN CAST(DiasVencido AS float) END) AS DiasAtrasoPromedio
FROM dbo.vw_CtaCte_Proveedores
WHERE TipoBase = 'OFICIAL' AND SaldoPendiente > 0
"@)[0]

# --- Por empresa ---
$porEmpresa = Invoke-SQL @"
SELECT
  v.Empresa              AS EmpresaId,
  ce.NombreEmpresa,
  COUNT(*)               AS CantFacturas,
  SUM(v.SaldoPendiente)  AS TotalPendiente
FROM dbo.vw_CtaCte_Proveedores v
LEFT JOIN dbo.Config_Empresas ce ON ce.Empresa = v.Empresa
WHERE v.TipoBase = 'OFICIAL' AND v.SaldoPendiente > 0
GROUP BY v.Empresa, ce.NombreEmpresa
ORDER BY TotalPendiente DESC
"@

# --- Por antigüedad ---
$porAntiguedad = Invoke-SQL @"
SELECT
  TramoVencimiento       AS Tramo,
  COUNT(*)               AS CantFacturas,
  SUM(SaldoPendiente)    AS TotalPendiente
FROM dbo.vw_CtaCte_Proveedores
WHERE TipoBase = 'OFICIAL' AND SaldoPendiente > 0
  AND TramoVencimiento NOT IN ('Cancelado', 'A Vencer')
GROUP BY TramoVencimiento
ORDER BY MIN(DiasVencido)
"@

# --- Top 30 proveedores ---
$topProveedores = Invoke-SQL @"
SELECT TOP 30
  CUIT,
  MAX(RazonSocial)        AS NombreProveedor,
  COUNT(DISTINCT Empresa) AS CantEmpresas,
  COUNT(*)                AS CantFacturas,
  SUM(SaldoPendiente)     AS TotalPendiente
FROM dbo.vw_CtaCte_Proveedores
WHERE TipoBase = 'OFICIAL' AND SaldoPendiente > 0
GROUP BY CUIT
ORDER BY TotalPendiente DESC
"@

# --- Por tipo de comprobante ---
$porTipo = Invoke-SQL @"
SELECT
  CASE TipoComprobante
    WHEN 1    THEN 'Factura A'
    WHEN 2    THEN 'Nota Debito A'
    WHEN 3    THEN 'Nota Credito A'
    WHEN 6    THEN 'Factura B'
    WHEN 11   THEN 'Factura C'
    WHEN 51   THEN 'Factura M'
    WHEN 81   THEN 'Tique Factura A'
    WHEN 1001 THEN 'Ajuste CtaCte(+)'
    WHEN 1002 THEN 'Ajuste CtaCte(-)'
    ELSE CAST(TipoComprobante AS varchar)
  END                     AS TipoComprobante,
  COUNT(*)                AS CantFacturas,
  SUM(SaldoPendiente)     AS TotalPendiente
FROM dbo.vw_CtaCte_Proveedores
WHERE TipoBase = 'OFICIAL' AND SaldoPendiente > 0
GROUP BY TipoComprobante
ORDER BY TotalPendiente DESC
"@

# --- Detalle de facturas (todas, el filtrado es client-side) ---
Write-Host "  Exportando detalle de facturas..." -ForegroundColor Gray
$facturas = Invoke-SQL @"
SELECT
  v.Empresa                                      AS EmpresaId,
  ce.NombreEmpresa,
  v.RazonSocial                                  AS NombreProveedor,
  v.CUIT,
  CASE v.TipoComprobante
    WHEN 1    THEN 'Factura A'
    WHEN 2    THEN 'Nota Debito A'
    WHEN 3    THEN 'Nota Credito A'
    WHEN 6    THEN 'Factura B'
    WHEN 11   THEN 'Factura C'
    WHEN 51   THEN 'Factura M'
    WHEN 81   THEN 'Tique Factura A'
    WHEN 1001 THEN 'Ajuste CtaCte(+)'
    WHEN 1002 THEN 'Ajuste CtaCte(-)'
    ELSE CAST(v.TipoComprobante AS varchar)
  END                                            AS TipoComprobante,
  v.NumeroCompleto                               AS NroComprobante,
  CONVERT(varchar(10), v.FECHA,            120)  AS FechaFactura,
  CONVERT(varchar(10), v.FechaVencimiento, 120)  AS FechaVencimiento,
  v.SaldoPendiente,
  v.DiasVencido                                  AS DiasAtraso,
  ISNULL(v.COMENTARIO, '')                       AS Comentario
FROM dbo.vw_CtaCte_Proveedores v
LEFT JOIN dbo.Config_Empresas ce ON ce.Empresa = v.Empresa
WHERE v.TipoBase = 'OFICIAL' AND v.SaldoPendiente > 0
ORDER BY v.DiasVencido DESC, v.SaldoPendiente DESC
"@

# --- Armar el JSON final ---
$data = [ordered]@{
    lastUpdated    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    totales        = $totales
    porEmpresa     = $porEmpresa
    porAntiguedad  = $porAntiguedad
    topProveedores = $topProveedores
    porTipo        = $porTipo
    facturas       = $facturas
}

$data | ConvertTo-Json -Depth 5 -Compress | Set-Content $out -Encoding UTF8
Write-Host "OK → $out  ($([math]::Round((Get-Item $out).Length/1KB,0)) KB)" -ForegroundColor Green
