# export_data.ps1 — genera data.json para el dashboard de facturas pendientes de proveedores
# Uso: .\export_data.ps1
# Requiere que sql.ps1 esté en la raíz del repo.

$root   = Split-Path $PSScriptRoot -Parent
$helper = Join-Path $root "sql.ps1"
$out    = Join-Path $PSScriptRoot "data.json"

function Invoke-SQL($q) {
    $json = & $helper -Format Json $q 2>&1
    $result = $json | ConvertFrom-Json -ErrorAction Stop
    # Si es un objeto único, envolverlo en array para uniformidad
    if ($result -isnot [array]) { $result = @($result) }
    return $result
}

Write-Host "Exportando datos de facturas pendientes..." -ForegroundColor Cyan

# --- Totales globales ---
$totales = (Invoke-SQL @"
SELECT
  SUM(SaldoPendiente)                                      AS TotalPendiente,
  COUNT(*)                                                 AS CantFacturas,
  COUNT(DISTINCT CUIT)                                     AS CantProveedores,
  COUNT(DISTINCT EmpresaId)                                AS CantEmpresas,
  SUM(CASE WHEN DiasAtraso > 0 THEN SaldoPendiente ELSE 0 END) AS TotalVencido,
  SUM(CASE WHEN DiasAtraso > 0 THEN 1 ELSE 0 END)         AS CantVencidas,
  AVG(CASE WHEN DiasAtraso > 0 THEN CAST(DiasAtraso AS float) END) AS DiasAtrasoPromedio
FROM dbo.vw_Compras_FacturasPendientes
WHERE SaldoPendiente > 0
"@)[0]

# --- Por empresa ---
$porEmpresa = Invoke-SQL @"
SELECT
  EmpresaId, NombreEmpresa,
  COUNT(*)          AS CantFacturas,
  SUM(SaldoPendiente) AS TotalPendiente
FROM dbo.vw_Compras_FacturasPendientes
WHERE SaldoPendiente > 0
GROUP BY EmpresaId, NombreEmpresa
ORDER BY TotalPendiente DESC
"@

# --- Por antigüedad ---
$porAntiguedad = Invoke-SQL @"
SELECT
  CASE
    WHEN DiasAtraso <= 30  THEN 'Vencida 1-30d'
    WHEN DiasAtraso <= 60  THEN 'Vencida 31-60d'
    WHEN DiasAtraso <= 90  THEN 'Vencida 61-90d'
    WHEN DiasAtraso <= 180 THEN 'Vencida 91-180d'
    WHEN DiasAtraso <= 365 THEN 'Vencida 181d-1a'
    ELSE                        'Vencida >1 año'
  END AS Tramo,
  COUNT(*)            AS CantFacturas,
  SUM(SaldoPendiente) AS TotalPendiente
FROM dbo.vw_Compras_FacturasPendientes
WHERE SaldoPendiente > 0 AND DiasAtraso >= 0
GROUP BY
  CASE
    WHEN DiasAtraso <= 30  THEN 'Vencida 1-30d'
    WHEN DiasAtraso <= 60  THEN 'Vencida 31-60d'
    WHEN DiasAtraso <= 90  THEN 'Vencida 61-90d'
    WHEN DiasAtraso <= 180 THEN 'Vencida 91-180d'
    WHEN DiasAtraso <= 365 THEN 'Vencida 181d-1a'
    ELSE                        'Vencida >1 año'
  END
ORDER BY MIN(DiasAtraso)
"@

# --- Top 30 proveedores ---
$topProveedores = Invoke-SQL @"
SELECT TOP 30
  CUIT,
  MAX(NombreProveedor)  AS NombreProveedor,
  COUNT(DISTINCT EmpresaId) AS CantEmpresas,
  COUNT(*)              AS CantFacturas,
  SUM(SaldoPendiente)   AS TotalPendiente
FROM dbo.vw_Compras_FacturasPendientes
WHERE SaldoPendiente > 0
GROUP BY CUIT
ORDER BY TotalPendiente DESC
"@

# --- Por tipo de comprobante ---
$porTipo = Invoke-SQL @"
SELECT
  ISNULL(TipoComprobante, 'Sin clasificar') AS TipoComprobante,
  COUNT(*)              AS CantFacturas,
  SUM(SaldoPendiente)   AS TotalPendiente
FROM dbo.vw_Compras_FacturasPendientes
WHERE SaldoPendiente > 0
GROUP BY TipoComprobante
ORDER BY TotalPendiente DESC
"@

# --- Detalle de facturas (todas, el filtrado es client-side) ---
Write-Host "  Exportando detalle de facturas..." -ForegroundColor Gray
$facturas = Invoke-SQL @"
SELECT
  EmpresaId,
  NombreEmpresa,
  NombreProveedor,
  CUIT,
  ISNULL(TipoComprobante, 'Sin clasificar') AS TipoComprobante,
  NroComprobante,
  CONVERT(varchar(10), FechaFactura,    120) AS FechaFactura,
  CONVERT(varchar(10), FechaVencimiento,120) AS FechaVencimiento,
  SaldoPendiente,
  DiasAtraso,
  Moneda,
  ISNULL(Comentario,'')  AS Comentario
FROM dbo.vw_Compras_FacturasPendientes
WHERE SaldoPendiente > 0
ORDER BY DiasAtraso DESC, SaldoPendiente DESC
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
