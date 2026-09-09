# export_data.ps1 - Genera los JSON del dashboard Flujo de Fondos.
# Salida:
#   data-inicio.json          resumen ejecutivo (KPIs, cards, gráficos)
#   data-proveedores.json     facturas pendientes con detalle
#   data-cheques-propios.json cheques por pagar con detalle
#
# Uso:
#   .\export_data.ps1                  refresca los 3
#   .\export_data.ps1 -SkipIngesta     no relee los Excel

[CmdletBinding()]
param([switch]$SkipIngesta)

$ErrorActionPreference = 'Stop'
$root   = Split-Path $PSScriptRoot -Parent
$helper = Join-Path $root 'sql.ps1'

function Invoke-SQL {
    param([string]$Query)
    $raw = & $helper -Format Json $Query 2>&1 | Out-String
    if ($raw -match '^\s*(sql\.ps1|Exception|System\.Data)') { throw "SQL falló:`n$raw" }
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $obj) { return @() }
    if ($obj -isnot [array]) { return @($obj) }
    return $obj
}

if (-not $SkipIngesta) {
    Write-Host "► Corriendo ingesta Excel..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'ingesta_excel.ps1')
}

Write-Host "► Consultando vistas..." -ForegroundColor Cyan

# ================================================================
#  data-inicio.json — resumen liviano
# ================================================================

$posicionTotales = (Invoke-SQL @"
SELECT
    MAX(FechaSaldo)                                   AS FechaSaldo,
    COUNT(*)                                          AS CantCuentas,
    COUNT(DISTINCT Empresa)                           AS CantEmpresas,
    SUM(Saldo)                                        AS Saldo,
    SUM(FCI)                                          AS FCI,
    SUM(MPago)                                        AS MPago,
    SUM(Pix)                                          AS Pix,
    SUM(DescubiertoAutorizado)                        AS DescubiertoAutorizado,
    SUM(Disponible)                                   AS Disponible,
    SUM(CASE WHEN Saldo < 0 THEN Saldo ELSE 0 END)    AS SaldoNegativo,
    SUM(CASE WHEN Saldo > 0 THEN Saldo ELSE 0 END)    AS SaldoPositivo
FROM vw_FlujoFondos_PosicionActual
"@)[0]

$posicionPorEmpresa = Invoke-SQL @"
SELECT Empresa, MAX(NombreEmpresa) AS NombreEmpresa, COUNT(*) AS CantCuentas,
       SUM(Saldo) AS Saldo, SUM(FCI) AS FCI, SUM(MPago) AS MPago, SUM(Pix) AS Pix,
       SUM(DescubiertoAutorizado) AS DescubiertoAutorizado, SUM(Disponible) AS Disponible
FROM vw_FlujoFondos_PosicionActual
GROUP BY Empresa
ORDER BY SUM(Disponible) DESC
"@

$posicionPorBanco = Invoke-SQL @"
SELECT Banco, COUNT(*) AS CantCuentas, SUM(Saldo) AS Saldo, SUM(Disponible) AS Disponible
FROM vw_FlujoFondos_PosicionActual
GROUP BY Banco
ORDER BY SUM(Disponible) DESC
"@

$posicionCuentas = Invoke-SQL @"
SELECT Empresa, NombreEmpresa, RazonSocialExcel, Banco, Cuenta,
       Saldo, FCI, MPago, Pix, DescubiertoAutorizado, Disponible
FROM vw_FlujoFondos_PosicionActual
ORDER BY Empresa, Banco, Cuenta
"@

$proyeccionPorDia = Invoke-SQL @"
SELECT CONVERT(varchar(10), Fecha, 120) AS Fecha, EsVencido, Origen, Tipo,
       SUM(Importe) AS Importe, SUM(ImporteFirmado) AS ImporteFirmado, COUNT(*) AS Movimientos
FROM vw_FlujoFondos_Proyectado
GROUP BY CONVERT(varchar(10), Fecha, 120), EsVencido, Origen, Tipo
"@

# Proyección próximos 30 días
$p30 = (Invoke-SQL @"
SELECT
    SUM(CASE WHEN Tipo='ENTRADA' THEN Importe ELSE 0 END) AS entradas,
    SUM(CASE WHEN Tipo='SALIDA'  THEN Importe ELSE 0 END) AS salidas,
    SUM(CASE WHEN Tipo='ENTRADA' THEN 1 ELSE 0 END)       AS movEnt,
    SUM(CASE WHEN Tipo='SALIDA'  THEN 1 ELSE 0 END)       AS movSal
FROM vw_FlujoFondos_Proyectado
WHERE EsVencido = 0 AND FechaOriginal <= DATEADD(day, 30, CAST(GETDATE() AS DATE))
"@)[0]
$p30 | Add-Member -NotePropertyName neto -NotePropertyValue ((0 + $p30.entradas) - (0 + $p30.salidas)) -Force

$sinEmpresa = Invoke-SQL @"
SELECT RazonSocialExcel, Banco, Cuenta, Saldo, Disponible
FROM vw_FlujoFondos_PosicionActual
WHERE Empresa = 'SIN_EMPRESA'
"@

# Contadores para el sidebar
$counterProveedores = (Invoke-SQL "SELECT COUNT(*) AS N FROM (SELECT CUIT FROM vw_CtaCte_Proveedores WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE()) GROUP BY CUIT HAVING SUM(SaldoPendiente) > 0) x")[0].N
$counterCheques     = (Invoke-SQL "SELECT COUNT(*) AS N FROM vw_ChequesPropios_Pendientes WHERE TipoBase='OFICIAL' AND Importe > 0 AND FechaPagoDiferido >= CAST(GETDATE() AS DATE)")[0].N
$counterPrestamos   = (Invoke-SQL "SELECT COUNT(*) AS N FROM vw_FlujoFondos_Prestamos WHERE Origen NOT LIKE 'Planes%' AND FechaVto >= CAST(GETDATE() AS DATE)")[0].N
$counterPlanes      = (Invoke-SQL "SELECT COUNT(*) AS N FROM vw_FlujoFondos_Prestamos WHERE Origen     LIKE 'Planes%' AND FechaVto >= CAST(GETDATE() AS DATE)")[0].N
$counterIngresos    = (Invoke-SQL "SELECT COUNT(*) AS N FROM vw_FlujoFondos_Proyectado WHERE Tipo='ENTRADA' AND EsVencido=0")[0].N
$counterCobranzas   = (Invoke-SQL "SELECT COUNT(*) AS N FROM (SELECT CUIT FROM vw_CtaCte_Clientes WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE()) GROUP BY CUIT HAVING SUM(SaldoPendiente) > 0) x")[0].N

$sidebarCounters = @{
    proveedores    = $counterProveedores
    chequesPropios = $counterCheques
    prestamos      = $counterPrestamos
    planes         = $counterPlanes
    ingresos       = $counterIngresos
    cobranzas      = $counterCobranzas
}

$dataInicio = [ordered]@{
    lastUpdated        = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    posicionTotales    = $posicionTotales
    posicionPorEmpresa = $posicionPorEmpresa
    posicionPorBanco   = $posicionPorBanco
    posicionCuentas    = $posicionCuentas
    proyeccionPorDia   = $proyeccionPorDia
    proyeccion30d      = $p30
    sinEmpresa         = $sinEmpresa
    counters           = $sidebarCounters
}

# ================================================================
#  data-proveedores.json — detalle de facturas pendientes
# ================================================================

# Nota: SaldoPendiente ya está firmado (positivo = deuda; negativo = saldo a favor por NC).
# Los agregados suman con signo → saldo NETO. El detalle trae todo (incluye NC como filas negativas).
# Filtro EsAntigua: facturas con FECHA > 36 meses se marcan y quedan fuera de los agregados.
# El detalle las trae con el flag para poder mostrarlas con un toggle en la UI.
$provTotales = (Invoke-SQL @"
WITH PorProveedor AS (
    SELECT CUIT, SUM(SaldoPendiente) AS SaldoNeto
    FROM vw_CtaCte_Proveedores
    WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE())
    GROUP BY CUIT
)
SELECT
    SUM(CASE WHEN SaldoNeto > 0 THEN SaldoNeto ELSE 0 END)   AS TotalPendiente,
    SUM(CASE WHEN SaldoNeto < 0 THEN SaldoNeto ELSE 0 END)   AS TotalAFavor,
    COUNT(CASE WHEN SaldoNeto > 0 THEN 1 END)                AS CantProveedoresDeuda,
    COUNT(CASE WHEN SaldoNeto < 0 THEN 1 END)                AS CantProveedoresAFavor,
    (SELECT COUNT(*) FROM vw_CtaCte_Proveedores WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE()) AND SaldoPendiente > 0) AS CantFacturas,
    (SELECT COUNT(DISTINCT Empresa) FROM vw_CtaCte_Proveedores WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE())) AS CantEmpresas,
    (SELECT SUM(SaldoPendiente) FROM vw_CtaCte_Proveedores WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE()) AND DiasVencido > 0 AND SaldoPendiente > 0) AS TotalVencido,
    (SELECT COUNT(*)              FROM vw_CtaCte_Proveedores WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE()) AND DiasVencido > 0 AND SaldoPendiente > 0) AS CantVencidas
FROM PorProveedor
"@)[0]

$provResumenAntiguas = (Invoke-SQL @"
SELECT
    COUNT(*)              AS CantFacturas,
    SUM(SaldoPendiente)   AS TotalPendiente
FROM vw_CtaCte_Proveedores
WHERE TipoBase='OFICIAL' AND SaldoPendiente > 0
  AND FECHA < DATEADD(month, -36, GETDATE())
"@)[0]

$provPorEmpresa = Invoke-SQL @"
SELECT v.Empresa AS EmpresaId, ce.NombreEmpresa,
       COUNT(*)                                                             AS CantFacturas,
       SUM(v.SaldoPendiente)                                                AS TotalPendiente,
       SUM(CASE WHEN v.SaldoPendiente < 0 THEN v.SaldoPendiente ELSE 0 END) AS SaldoAFavor,
       SUM(CASE WHEN v.DiasVencido > 0 AND v.SaldoPendiente > 0
                THEN v.SaldoPendiente ELSE 0 END)                           AS TotalVencido
FROM vw_CtaCte_Proveedores v
LEFT JOIN Config_Empresas ce ON ce.Empresa = v.Empresa
WHERE v.TipoBase='OFICIAL' AND v.FECHA >= DATEADD(month, -36, GETDATE())
GROUP BY v.Empresa, ce.NombreEmpresa
HAVING SUM(v.SaldoPendiente) <> 0
ORDER BY TotalPendiente DESC
"@

$provPorAntiguedad = Invoke-SQL @"
SELECT TramoVencimiento AS Tramo, COUNT(*) AS CantFacturas, SUM(SaldoPendiente) AS TotalPendiente
FROM vw_CtaCte_Proveedores
WHERE TipoBase='OFICIAL' AND SaldoPendiente > 0
  AND FECHA >= DATEADD(month, -36, GETDATE())
GROUP BY TramoVencimiento
ORDER BY MIN(DiasVencido)
"@

$provTopProveedores = Invoke-SQL @"
SELECT TOP 50 CUIT, MAX(RazonSocial) AS NombreProveedor,
       COUNT(DISTINCT Empresa)                                         AS CantEmpresas,
       COUNT(*)                                                        AS CantMovs,
       SUM(SaldoPendiente)                                             AS TotalPendiente,
       SUM(CASE WHEN SaldoPendiente < 0 THEN SaldoPendiente ELSE 0 END) AS SaldoAFavor,
       SUM(CASE WHEN DiasVencido > 0 AND SaldoPendiente > 0
                THEN SaldoPendiente ELSE 0 END)                        AS TotalVencido
FROM vw_CtaCte_Proveedores
WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE())
GROUP BY CUIT
HAVING SUM(SaldoPendiente) > 0
ORDER BY TotalPendiente DESC
"@

$provFacturas = Invoke-SQL @"
SELECT v.Empresa AS EmpresaId, ce.NombreEmpresa,
       v.RazonSocial AS NombreProveedor, v.CUIT,
       CASE v.TipoComprobante
            WHEN 1 THEN 'FCA' WHEN 2 THEN 'NDA' WHEN 3 THEN 'NCA'
            WHEN 6 THEN 'FCB' WHEN 11 THEN 'FCC' WHEN 51 THEN 'FCM'
            WHEN 81 THEN 'TFA' WHEN 1001 THEN 'AJ+' WHEN 1002 THEN 'AJ-'
            ELSE CAST(v.TipoComprobante AS varchar) END AS Tipo,
       v.NumeroCompleto AS Numero,
       CONVERT(varchar(10), v.FECHA, 120) AS FechaFactura,
       CONVERT(varchar(10), v.FechaVencimiento, 120) AS FechaVencimiento,
       v.SaldoPendiente, v.DiasVencido AS DiasAtraso,
       ISNULL(v.COMENTARIO, '') AS Comentario,
       CASE WHEN v.FECHA < DATEADD(month, -36, GETDATE()) THEN 1 ELSE 0 END AS EsAntigua
FROM vw_CtaCte_Proveedores v
LEFT JOIN Config_Empresas ce ON ce.Empresa = v.Empresa
WHERE v.TipoBase='OFICIAL' AND v.SaldoPendiente <> 0
ORDER BY v.DiasVencido DESC, v.SaldoPendiente DESC
"@

$dataProveedores = [ordered]@{
    lastUpdated       = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    totales           = $provTotales
    resumenAntiguas   = $provResumenAntiguas
    porEmpresa        = $provPorEmpresa
    porAntiguedad     = $provPorAntiguedad
    topProveedores    = $provTopProveedores
    facturas          = $provFacturas
    counters          = $sidebarCounters
}

# ================================================================
#  data-cheques-propios.json — cheques por pagar
# ================================================================

# Regla: mostrar solo cheques con FechaPagoDiferido >= hoy.
# Los vencidos son arrastre del ERP (cheques ya pagados no marcados) y distorsionan la lectura.
$chTotales = (Invoke-SQL @"
SELECT COUNT(*) AS CantCheques,
       SUM(Importe) AS TotalImporte,
       COUNT(DISTINCT Empresa) AS CantEmpresas,
       SUM(CASE WHEN FechaPagoDiferido BETWEEN CAST(GETDATE() AS DATE) AND DATEADD(day, 30, CAST(GETDATE() AS DATE))
                THEN Importe ELSE 0 END) AS Importe30d,
       SUM(CASE WHEN FechaPagoDiferido BETWEEN CAST(GETDATE() AS DATE) AND DATEADD(day, 30, CAST(GETDATE() AS DATE))
                THEN 1 ELSE 0 END)       AS Cant30d
FROM vw_ChequesPropios_Pendientes
WHERE TipoBase='OFICIAL' AND Importe > 0
  AND FechaPagoDiferido >= CAST(GETDATE() AS DATE)
"@)[0]

$chPorEmpresa = Invoke-SQL @"
SELECT c.Empresa AS EmpresaId, ce.NombreEmpresa,
       COUNT(*) AS CantCheques, SUM(c.Importe) AS TotalImporte
FROM vw_ChequesPropios_Pendientes c
LEFT JOIN Config_Empresas ce ON ce.Empresa = c.Empresa
WHERE c.TipoBase='OFICIAL' AND c.Importe > 0
  AND c.FechaPagoDiferido >= CAST(GETDATE() AS DATE)
GROUP BY c.Empresa, ce.NombreEmpresa
ORDER BY TotalImporte DESC
"@

$chPorBanco = Invoke-SQL @"
SELECT LibroFondo, CuentaBancaria, COUNT(*) AS CantCheques, SUM(Importe) AS TotalImporte
FROM vw_ChequesPropios_Pendientes
WHERE TipoBase='OFICIAL' AND Importe > 0
  AND FechaPagoDiferido >= CAST(GETDATE() AS DATE)
GROUP BY LibroFondo, CuentaBancaria
ORDER BY TotalImporte DESC
"@

$chTopBenef = Invoke-SQL @"
SELECT TOP 50 OrdenPago AS Beneficiario, COUNT(*) AS CantCheques, SUM(Importe) AS TotalImporte
FROM vw_ChequesPropios_Pendientes
WHERE TipoBase='OFICIAL' AND Importe > 0 AND OrdenPago IS NOT NULL AND OrdenPago <> ''
  AND FechaPagoDiferido >= CAST(GETDATE() AS DATE)
GROUP BY OrdenPago
ORDER BY TotalImporte DESC
"@

$chCheques = Invoke-SQL @"
SELECT c.Empresa AS EmpresaId, ce.NombreEmpresa,
       c.LibroFondo, c.CuentaBancaria, c.NumeroCheque,
       CONVERT(varchar(10), c.FechaEmision, 120) AS FechaEmision,
       CONVERT(varchar(10), c.FechaPagoDiferido, 120) AS FechaPagoDiferido,
       DATEDIFF(day, CAST(GETDATE() AS DATE), c.FechaPagoDiferido) AS DiasAlPago,
       ISNULL(c.OrdenPago, '') AS Beneficiario,
       c.Importe
FROM vw_ChequesPropios_Pendientes c
LEFT JOIN Config_Empresas ce ON ce.Empresa = c.Empresa
WHERE c.TipoBase='OFICIAL' AND c.Importe > 0
  AND c.FechaPagoDiferido >= CAST(GETDATE() AS DATE)
ORDER BY c.FechaPagoDiferido, c.Importe DESC
"@

$dataCheques = [ordered]@{
    lastUpdated  = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    totales      = $chTotales
    porEmpresa   = $chPorEmpresa
    porBanco     = $chPorBanco
    topBenefic   = $chTopBenef
    cheques      = $chCheques
    counters     = $sidebarCounters
}

# ================================================================
#  Helper: bloques por origen (Préstamos vs Planes ARCA)
#  Regla común: FechaVto >= hoy
# ================================================================

function Get-BloqueCuotas {
    param([string]$FiltroOrigen)  # ej. "Origen NOT LIKE 'Planes%'" o "Origen LIKE 'Planes%'"
    $t = (Invoke-SQL @"
SELECT
    SUM(ImporteCuota)                 AS TotalImporte,
    COUNT(*)                          AS CantCuotas,
    COUNT(DISTINCT Empresa)           AS CantEmpresas,
    COUNT(DISTINCT EntidadFinanciera) AS CantEntidades,
    SUM(CASE WHEN FechaVto BETWEEN CAST(GETDATE() AS DATE) AND DATEADD(day, 30, CAST(GETDATE() AS DATE))
             THEN ImporteCuota ELSE 0 END) AS Importe30d,
    SUM(CASE WHEN FechaVto BETWEEN CAST(GETDATE() AS DATE) AND DATEADD(day, 30, CAST(GETDATE() AS DATE))
             THEN 1 ELSE 0 END)            AS Cant30d,
    SUM(CASE WHEN EstadoPlan LIKE '%IMPAGA%' THEN 1 ELSE 0 END)             AS CantEnAlerta,
    SUM(CASE WHEN EstadoPlan LIKE '%IMPAGA%' THEN ImporteCuota ELSE 0 END)  AS ImporteEnAlerta
FROM vw_FlujoFondos_Prestamos
WHERE FechaVto >= CAST(GETDATE() AS DATE) AND $FiltroOrigen
"@)[0]

    $porEntidad = Invoke-SQL @"
SELECT EntidadFinanciera, COUNT(*) AS CantCuotas, SUM(ImporteCuota) AS TotalImporte,
       COUNT(DISTINCT Empresa) AS CantEmpresas
FROM vw_FlujoFondos_Prestamos
WHERE FechaVto >= CAST(GETDATE() AS DATE) AND $FiltroOrigen
GROUP BY EntidadFinanciera ORDER BY TotalImporte DESC
"@

    $porEmpresa = Invoke-SQL @"
SELECT Empresa AS EmpresaId, MAX(NombreEmpresa) AS NombreEmpresa,
       COUNT(*) AS CantCuotas, SUM(ImporteCuota) AS TotalImporte,
       SUM(CASE WHEN EstadoPlan LIKE '%IMPAGA%' THEN ImporteCuota ELSE 0 END) AS ImporteEnAlerta
FROM vw_FlujoFondos_Prestamos
WHERE FechaVto >= CAST(GETDATE() AS DATE) AND $FiltroOrigen
GROUP BY Empresa ORDER BY TotalImporte DESC
"@

    $cuotas = Invoke-SQL @"
SELECT EntidadFinanciera, Empresa AS EmpresaId, NombreEmpresa,
       Concepto, NumeroOrigen, NroCuota,
       CONVERT(varchar(10), FechaVto, 120) AS FechaVto,
       DATEDIFF(day, CAST(GETDATE() AS DATE), FechaVto) AS DiasAlPago,
       ImporteCuota, EstadoPlan, Nota
FROM vw_FlujoFondos_Prestamos
WHERE FechaVto >= CAST(GETDATE() AS DATE) AND $FiltroOrigen
ORDER BY FechaVto, ImporteCuota DESC
"@
    return [ordered]@{
        lastUpdated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
        totales     = $t
        porEntidad  = $porEntidad
        porEmpresa  = $porEmpresa
        cuotas      = $cuotas
        counters    = $sidebarCounters
    }
}

$dataPrestamos = Get-BloqueCuotas -FiltroOrigen "Origen NOT LIKE 'Planes%'"
$dataPlanes    = Get-BloqueCuotas -FiltroOrigen "Origen LIKE 'Planes%'"

# ================================================================
#  data-ingresos.json — entradas proyectadas (tarjetas + cheques terceros)
#  Regla: EsVencido = 0 (solo futuros, mismo criterio que salidas)
# ================================================================

$inTotales = (Invoke-SQL @"
SELECT
    SUM(Importe)             AS TotalImporte,
    COUNT(*)                 AS CantMovs,
    COUNT(DISTINCT Empresa)  AS CantEmpresas,
    COUNT(DISTINCT Origen)   AS CantOrigenes,
    SUM(CASE WHEN Fecha BETWEEN CAST(GETDATE() AS DATE) AND DATEADD(day, 30, CAST(GETDATE() AS DATE))
             THEN Importe ELSE 0 END) AS Importe30d,
    SUM(CASE WHEN Fecha BETWEEN CAST(GETDATE() AS DATE) AND DATEADD(day, 30, CAST(GETDATE() AS DATE))
             THEN 1 ELSE 0 END)       AS Cant30d,
    SUM(CASE WHEN Fecha BETWEEN CAST(GETDATE() AS DATE) AND DATEADD(day, 7, CAST(GETDATE() AS DATE))
             THEN Importe ELSE 0 END) AS Importe7d
FROM vw_FlujoFondos_Proyectado
WHERE Tipo='ENTRADA' AND EsVencido=0
"@)[0]

$inPorOrigen = Invoke-SQL @"
SELECT Origen, COUNT(*) AS CantMovs, SUM(Importe) AS TotalImporte,
       COUNT(DISTINCT Empresa) AS CantEmpresas
FROM vw_FlujoFondos_Proyectado
WHERE Tipo='ENTRADA' AND EsVencido=0
GROUP BY Origen ORDER BY TotalImporte DESC
"@

$inPorEmpresa = Invoke-SQL @"
SELECT Empresa AS EmpresaId, MAX(NombreEmpresa) AS NombreEmpresa,
       COUNT(*) AS CantMovs, SUM(Importe) AS TotalImporte,
       SUM(CASE WHEN Origen='Tarjetas'         THEN Importe ELSE 0 END) AS ImporteTarjetas,
       SUM(CASE WHEN Origen='Cheques terceros' THEN Importe ELSE 0 END) AS ImporteCheques
FROM vw_FlujoFondos_Proyectado
WHERE Tipo='ENTRADA' AND EsVencido=0
GROUP BY Empresa ORDER BY TotalImporte DESC
"@

$inMovs = Invoke-SQL @"
SELECT Origen, Empresa AS EmpresaId, NombreEmpresa,
       CONVERT(varchar(10), Fecha, 120) AS Fecha,
       DiasAlVencimiento AS DiasACobrar,
       Concepto, Detalle, Importe
FROM vw_FlujoFondos_Proyectado
WHERE Tipo='ENTRADA' AND EsVencido=0
ORDER BY Fecha, Importe DESC
"@

$dataIngresos = [ordered]@{
    lastUpdated = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    totales     = $inTotales
    porOrigen   = $inPorOrigen
    porEmpresa  = $inPorEmpresa
    movs        = $inMovs
    counters    = $sidebarCounters
}

# ================================================================
#  data-cobranzas.json — facturas a cobrar (misma estética que proveedores)
# ================================================================

# Nota: SaldoPendiente ya está firmado (positivo = a cobrar; negativo = NC / saldo a favor cliente).
# Filtro EsAntigua: facturas con FECHA > 36 meses se marcan y quedan fuera de los agregados.
$cobTotales = (Invoke-SQL @"
WITH PorCliente AS (
    SELECT CUIT, SUM(SaldoPendiente) AS SaldoNeto
    FROM vw_CtaCte_Clientes
    WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE())
    GROUP BY CUIT
)
SELECT
    SUM(CASE WHEN SaldoNeto > 0 THEN SaldoNeto ELSE 0 END)   AS TotalACobrar,
    SUM(CASE WHEN SaldoNeto < 0 THEN SaldoNeto ELSE 0 END)   AS TotalAFavorCliente,
    COUNT(CASE WHEN SaldoNeto > 0 THEN 1 END)                AS CantClientesDeuda,
    COUNT(CASE WHEN SaldoNeto < 0 THEN 1 END)                AS CantClientesAFavor,
    (SELECT COUNT(*) FROM vw_CtaCte_Clientes WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE()) AND SaldoPendiente > 0) AS CantFacturas,
    (SELECT COUNT(DISTINCT Empresa) FROM vw_CtaCte_Clientes WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE())) AS CantEmpresas,
    (SELECT SUM(SaldoPendiente) FROM vw_CtaCte_Clientes WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE()) AND DiasVencido > 0 AND SaldoPendiente > 0) AS TotalVencido,
    (SELECT COUNT(*)              FROM vw_CtaCte_Clientes WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE()) AND DiasVencido > 0 AND SaldoPendiente > 0) AS CantVencidas
FROM PorCliente
"@)[0]

$cobResumenAntiguas = (Invoke-SQL @"
SELECT
    COUNT(*)              AS CantFacturas,
    SUM(SaldoPendiente)   AS TotalACobrar
FROM vw_CtaCte_Clientes
WHERE TipoBase='OFICIAL' AND SaldoPendiente > 0
  AND FECHA < DATEADD(month, -36, GETDATE())
"@)[0]

$cobPorEmpresa = Invoke-SQL @"
SELECT v.Empresa AS EmpresaId, ce.NombreEmpresa,
       COUNT(*)                                                             AS CantFacturas,
       SUM(v.SaldoPendiente)                                                AS TotalACobrar,
       SUM(CASE WHEN v.SaldoPendiente < 0 THEN v.SaldoPendiente ELSE 0 END) AS SaldoAFavor,
       SUM(CASE WHEN v.DiasVencido > 0 AND v.SaldoPendiente > 0
                THEN v.SaldoPendiente ELSE 0 END)                           AS TotalVencido
FROM vw_CtaCte_Clientes v
LEFT JOIN Config_Empresas ce ON ce.Empresa = v.Empresa
WHERE v.TipoBase='OFICIAL' AND v.FECHA >= DATEADD(month, -36, GETDATE())
GROUP BY v.Empresa, ce.NombreEmpresa
HAVING SUM(v.SaldoPendiente) <> 0
ORDER BY TotalACobrar DESC
"@

$cobPorAntiguedad = Invoke-SQL @"
SELECT TramoVencimiento AS Tramo, COUNT(*) AS CantFacturas, SUM(SaldoPendiente) AS TotalACobrar
FROM vw_CtaCte_Clientes
WHERE TipoBase='OFICIAL' AND SaldoPendiente > 0
  AND FECHA >= DATEADD(month, -36, GETDATE())
GROUP BY TramoVencimiento
ORDER BY MIN(DiasVencido)
"@

$cobTopClientes = Invoke-SQL @"
SELECT TOP 50 CUIT, MAX(RazonSocial) AS NombreCliente,
       COUNT(DISTINCT Empresa)                                         AS CantEmpresas,
       COUNT(*)                                                        AS CantMovs,
       SUM(SaldoPendiente)                                             AS TotalACobrar,
       SUM(CASE WHEN SaldoPendiente < 0 THEN SaldoPendiente ELSE 0 END) AS SaldoAFavor,
       SUM(CASE WHEN DiasVencido > 0 AND SaldoPendiente > 0
                THEN SaldoPendiente ELSE 0 END)                        AS TotalVencido
FROM vw_CtaCte_Clientes
WHERE TipoBase='OFICIAL' AND FECHA >= DATEADD(month, -36, GETDATE())
GROUP BY CUIT
HAVING SUM(SaldoPendiente) > 0
ORDER BY TotalACobrar DESC
"@

# Detalle: solo facturas activas <= 36m con saldo positivo (mismo criterio que agregados).
# Volumen: sin este filtro son ~35k filas → JSON de 12MB, page load lento.
# Los NC (SaldoPendiente < 0) siguen contando en los agregados TotalAFavorCliente / CantClientesAFavor.
$cobFacturas = Invoke-SQL @"
SELECT v.Empresa AS EmpresaId, ce.NombreEmpresa,
       v.RazonSocial AS NombreCliente, v.CUIT,
       v.TipoComprobante AS Tipo,
       v.NumeroCompleto AS Numero,
       CONVERT(varchar(10), v.FECHA, 120) AS FechaFactura,
       CONVERT(varchar(10), v.FechaVencimiento, 120) AS FechaVencimiento,
       v.SaldoPendiente, v.DiasVencido AS DiasAtraso,
       ISNULL(v.COMENTARIO, '') AS Comentario
FROM vw_CtaCte_Clientes v
LEFT JOIN Config_Empresas ce ON ce.Empresa = v.Empresa
WHERE v.TipoBase='OFICIAL'
  AND v.SaldoPendiente > 0
  AND v.FECHA >= DATEADD(month, -36, GETDATE())
ORDER BY v.DiasVencido DESC, v.SaldoPendiente DESC
"@

$dataCobranzas = [ordered]@{
    lastUpdated       = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    totales           = $cobTotales
    resumenAntiguas   = $cobResumenAntiguas
    porEmpresa        = $cobPorEmpresa
    porAntiguedad     = $cobPorAntiguedad
    topClientes       = $cobTopClientes
    facturas          = $cobFacturas
    counters          = $sidebarCounters
}

# ================================================================
#  data-deuda-global.json — consolidado deuda por empresa y origen
# ================================================================

$dgTotales = (Invoke-SQL @"
SELECT
    SUM(Deuda)                                           AS TotalDeuda,
    SUM(CASE WHEN EsVencida=1 THEN Deuda ELSE 0 END)     AS TotalVencido,
    SUM(CASE WHEN EnProx30=1 THEN Deuda ELSE 0 END)      AS TotalProx30,
    COUNT(*)                                             AS CantItems,
    COUNT(DISTINCT Empresa)                              AS CantEmpresas
FROM vw_FlujoFondos_DeudaGlobal
"@)[0]

$dgPorOrigen = Invoke-SQL @"
SELECT Origen,
       COUNT(*)                                          AS Cant,
       SUM(Deuda)                                        AS Total,
       SUM(CASE WHEN EsVencida=1 THEN Deuda ELSE 0 END)  AS Vencido,
       SUM(CASE WHEN EnProx30=1 THEN Deuda ELSE 0 END)   AS Prox30
FROM vw_FlujoFondos_DeudaGlobal
GROUP BY Origen
ORDER BY Total DESC
"@

$dgPorEmpresa = Invoke-SQL @"
SELECT Empresa AS EmpresaId, MAX(NombreEmpresa) AS NombreEmpresa,
       SUM(Deuda)                                                                            AS TotalDeuda,
       SUM(CASE WHEN Origen='Proveedores'      THEN Deuda ELSE 0 END)                        AS Proveedores,
       SUM(CASE WHEN Origen='Cheques propios'  THEN Deuda ELSE 0 END)                        AS ChequesPropios,
       SUM(CASE WHEN Origen='Préstamos'        THEN Deuda ELSE 0 END)                        AS Prestamos,
       SUM(CASE WHEN Origen='Planes ARCA'      THEN Deuda ELSE 0 END)                        AS PlanesArca,
       SUM(CASE WHEN EsVencida=1 THEN Deuda ELSE 0 END)                                      AS Vencido,
       SUM(CASE WHEN EnProx30=1 THEN Deuda ELSE 0 END)                                       AS Prox30,
       COUNT(*)                                                                              AS CantItems
FROM vw_FlujoFondos_DeudaGlobal
GROUP BY Empresa
ORDER BY TotalDeuda DESC
"@

# Deuda por mes de vencimiento (próximos 12 meses + una fila "vencido")
$dgPorMes = Invoke-SQL @"
SELECT
    CASE WHEN EsVencida=1 THEN 'Vencido'
         ELSE FORMAT(FechaVto, 'yyyy-MM') END AS Periodo,
    Origen,
    SUM(Deuda) AS Total
FROM vw_FlujoFondos_DeudaGlobal
WHERE EsVencida=1
   OR FechaVto <= DATEADD(month, 12, CAST(GETDATE() AS DATE))
GROUP BY CASE WHEN EsVencida=1 THEN 'Vencido' ELSE FORMAT(FechaVto, 'yyyy-MM') END, Origen
ORDER BY Periodo, Origen
"@

$dataDeudaGlobal = [ordered]@{
    lastUpdated  = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    totales      = $dgTotales
    porOrigen    = $dgPorOrigen
    porEmpresa   = $dgPorEmpresa
    porMes       = $dgPorMes
    counters     = $sidebarCounters
}

# ================================================================
#  data-consolidado.json — ingresos vs egresos histórico + proyectado
# ================================================================

# Histórico: últimos 24 meses (hasta el mes actual). Ingresos: vw_CobrosPorPeriodo. Egresos: vw_PagosPorPeriodo.
$conMensualHist = Invoke-SQL @"
WITH Ing AS (
    SELECT Periodo, SUM(TotalCobrado) AS Ingresos
    FROM vw_CobrosPorPeriodo
    WHERE TipoBase='OFICIAL' AND Anio*12+Mes >= (YEAR(GETDATE())*12+MONTH(GETDATE())-23)
    GROUP BY Periodo
),
Egr AS (
    SELECT Periodo, SUM(TotalPagado) AS Egresos
    FROM vw_PagosPorPeriodo
    WHERE TipoBase='OFICIAL' AND Anio*12+Mes >= (YEAR(GETDATE())*12+MONTH(GETDATE())-23)
    GROUP BY Periodo
)
SELECT COALESCE(i.Periodo, e.Periodo) AS Periodo,
       ISNULL(i.Ingresos, 0) AS Ingresos,
       ISNULL(e.Egresos, 0)  AS Egresos,
       ISNULL(i.Ingresos, 0) - ISNULL(e.Egresos, 0) AS Neto,
       0 AS EsProyectado
FROM Ing i FULL OUTER JOIN Egr e ON e.Periodo = i.Periodo
ORDER BY Periodo
"@

# Proyectado: próximos 6 meses del vw_FlujoFondos_Proyectado agrupado por mes.
# Los "vencidos" del proyectado se acumulan en "hoy" por lógica de la vista — quedan en el mes actual.
$conMensualProy = Invoke-SQL @"
SELECT FORMAT(Fecha, 'yyyy-MM') AS Periodo,
       SUM(CASE WHEN Tipo='ENTRADA' THEN Importe ELSE 0 END) AS Ingresos,
       SUM(CASE WHEN Tipo='SALIDA'  THEN Importe ELSE 0 END) AS Egresos,
       SUM(CASE WHEN Tipo='ENTRADA' THEN Importe ELSE 0 END)
       - SUM(CASE WHEN Tipo='SALIDA' THEN Importe ELSE 0 END) AS Neto,
       1 AS EsProyectado
FROM vw_FlujoFondos_Proyectado
WHERE Fecha > EOMONTH(GETDATE())
  AND Fecha <= EOMONTH(GETDATE(), 6)
GROUP BY FORMAT(Fecha, 'yyyy-MM')
ORDER BY Periodo
"@

# Combinar (el mes actual sale del histórico, no del proyectado, para evitar double-count)
$conMensual = @()
if ($conMensualHist) { $conMensual += $conMensualHist }
if ($conMensualProy) { $conMensual += $conMensualProy }

# Año en curso: por empresa (top ingresos y top egresos)
$conAnoPorEmpresa = Invoke-SQL @"
WITH Ing AS (
    SELECT Empresa, SUM(TotalCobrado) AS Ingresos
    FROM vw_CobrosPorPeriodo
    WHERE TipoBase='OFICIAL' AND Anio = YEAR(GETDATE())
    GROUP BY Empresa
),
Egr AS (
    SELECT Empresa, SUM(TotalPagado) AS Egresos
    FROM vw_PagosPorPeriodo
    WHERE TipoBase='OFICIAL' AND Anio = YEAR(GETDATE())
    GROUP BY Empresa
)
SELECT COALESCE(i.Empresa, e.Empresa) AS EmpresaId,
       COALESCE((SELECT NombreEmpresa FROM Config_Empresas ce WHERE ce.Empresa = COALESCE(i.Empresa, e.Empresa)), COALESCE(i.Empresa, e.Empresa)) AS NombreEmpresa,
       ISNULL(i.Ingresos, 0) AS Ingresos,
       ISNULL(e.Egresos, 0)  AS Egresos,
       ISNULL(i.Ingresos, 0) - ISNULL(e.Egresos, 0) AS Neto
FROM Ing i FULL OUTER JOIN Egr e ON e.Empresa = i.Empresa
ORDER BY (ISNULL(i.Ingresos, 0) + ISNULL(e.Egresos, 0)) DESC
"@

$conTotalesAno = (Invoke-SQL @"
SELECT
    (SELECT SUM(TotalCobrado) FROM vw_CobrosPorPeriodo WHERE TipoBase='OFICIAL' AND Anio=YEAR(GETDATE())) AS IngresosAno,
    (SELECT SUM(TotalPagado)  FROM vw_PagosPorPeriodo  WHERE TipoBase='OFICIAL' AND Anio=YEAR(GETDATE())) AS EgresosAno,
    (SELECT SUM(TotalCobrado) FROM vw_CobrosPorPeriodo WHERE TipoBase='OFICIAL' AND Anio=YEAR(GETDATE()) AND Mes=MONTH(GETDATE())) AS IngresosMes,
    (SELECT SUM(TotalPagado)  FROM vw_PagosPorPeriodo  WHERE TipoBase='OFICIAL' AND Anio=YEAR(GETDATE()) AND Mes=MONTH(GETDATE())) AS EgresosMes
"@)[0]

$dataConsolidado = [ordered]@{
    lastUpdated  = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    totalesAno   = $conTotalesAno
    mensual      = $conMensual
    porEmpresa   = $conAnoPorEmpresa
    counters     = $sidebarCounters
}

# ================================================================
#  Escribir los 8 JSON
# ================================================================
$outInicio       = Join-Path $PSScriptRoot 'data-inicio.json'
$outProv         = Join-Path $PSScriptRoot 'data-proveedores.json'
$outCheques      = Join-Path $PSScriptRoot 'data-cheques-propios.json'
$outPrestamos    = Join-Path $PSScriptRoot 'data-prestamos.json'
$outPlanes       = Join-Path $PSScriptRoot 'data-planes.json'
$outIngresos     = Join-Path $PSScriptRoot 'data-ingresos.json'
$outCobranzas    = Join-Path $PSScriptRoot 'data-cobranzas.json'
$outDeudaGlobal  = Join-Path $PSScriptRoot 'data-deuda-global.json'
$outConsolidado  = Join-Path $PSScriptRoot 'data-consolidado.json'

$dataInicio      | ConvertTo-Json -Depth 6 -Compress | Set-Content $outInicio -Encoding UTF8
$dataProveedores | ConvertTo-Json -Depth 6 -Compress | Set-Content $outProv -Encoding UTF8
$dataCheques     | ConvertTo-Json -Depth 6 -Compress | Set-Content $outCheques -Encoding UTF8
$dataPrestamos   | ConvertTo-Json -Depth 6 -Compress | Set-Content $outPrestamos -Encoding UTF8
$dataPlanes      | ConvertTo-Json -Depth 6 -Compress | Set-Content $outPlanes -Encoding UTF8
$dataIngresos    | ConvertTo-Json -Depth 6 -Compress | Set-Content $outIngresos -Encoding UTF8
$dataCobranzas   | ConvertTo-Json -Depth 6 -Compress | Set-Content $outCobranzas -Encoding UTF8
$dataDeudaGlobal | ConvertTo-Json -Depth 6 -Compress | Set-Content $outDeudaGlobal -Encoding UTF8
$dataConsolidado | ConvertTo-Json -Depth 6 -Compress | Set-Content $outConsolidado -Encoding UTF8

# Legacy: mantenemos data.json apuntando al inicio por compatibilidad con corridas viejas
Copy-Item $outInicio (Join-Path $PSScriptRoot 'data.json') -Force

function KB($p) { [math]::Round((Get-Item $p).Length/1KB, 0) }
Write-Host ("OK → data-inicio.json          ({0} KB)" -f (KB $outInicio))    -ForegroundColor Green
Write-Host ("OK → data-proveedores.json     ({0} KB)" -f (KB $outProv))      -ForegroundColor Green
Write-Host ("OK → data-cheques-propios.json ({0} KB)" -f (KB $outCheques))   -ForegroundColor Green
Write-Host ("OK → data-prestamos.json       ({0} KB)" -f (KB $outPrestamos)) -ForegroundColor Green
Write-Host ("OK → data-planes.json          ({0} KB)" -f (KB $outPlanes))    -ForegroundColor Green
Write-Host ("OK → data-ingresos.json        ({0} KB)" -f (KB $outIngresos))  -ForegroundColor Green
Write-Host ("OK → data-cobranzas.json       ({0} KB)" -f (KB $outCobranzas)) -ForegroundColor Green
Write-Host ("OK → data-deuda-global.json    ({0} KB)" -f (KB $outDeudaGlobal)) -ForegroundColor Green
Write-Host ("OK → data-consolidado.json     ({0} KB)" -f (KB $outConsolidado)) -ForegroundColor Green
