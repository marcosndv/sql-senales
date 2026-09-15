-- ============================================================
-- Snapshot de cuentas corrientes (proveedores / clientes)
-- ============================================================
-- Problema: vw_CtaCte_Proveedores (~10 s) y vw_CtaCte_Clientes (~30 s) unen ~45 tablas
-- del ERP cada una y se consultan ~20 veces por corrida de export_data.ps1. Con corridas
-- superpuestas la task FlujoFondos-Refresh tardaba 30+ min y se apilaba.
--
-- Solución:
--   vw_CtaCte_*_Live  copia exacta del cálculo original (lento, siempre al día)
--   Snap_CtaCte_*     resultado guardado, lo llena 11_refresh_snap_ctacte.sql
--   vw_CtaCte_*_Snap  mismas columnas que la vista original, leyendo el snapshot;
--                     DiasVencido y TramoVencimiento se calculan en vivo con GETDATE()
--
-- Este script NO cambia vw_CtaCte_Proveedores / vw_CtaCte_Clientes: eso lo hace
-- 12_switch_vw_ctacte_a_snapshot.sql, después de validar _Snap contra _Live.
-- Ejecutar por lotes (separador GO).
-- ============================================================

CREATE OR ALTER VIEW dbo.vw_CtaCte_Proveedores_Live AS
WITH Imputado AS (
    -- Suma de lo ya pagado/aplicado por factura de compra
    SELECT
        Empresa,
        TipoBase,
        COMPRA         AS CodigoCompra,
        SUM(IMPORTE)   AS TotalImputado
    FROM dbo.vw_RelacionesCtasCtes_Consolidado
    WHERE COMPRA IS NOT NULL AND COMPRA <> ''
    GROUP BY Empresa, TipoBase, COMPRA
)
SELECT
    lc.Empresa,
    lc.TipoBase,
    'Proveedor'                                                     AS TipoEntidad,
    lc.PROVEEDOR                                                    AS CodigoEntidad,
    e.NOMBRE                                                        AS RazonSocial,
    e.CUIT,

    -- Comprobante
    lc.FECHA,
    lc.VENCE                                                        AS FechaVencimiento,
    lc.COMPROB                                                      AS TipoComprobante,
    lc.PTOEMISOR,
    lc.NUMERO,
    CONCAT(lc.PTOEMISOR, '-', FORMAT(lc.NUMERO, '00000000'))        AS NumeroCompleto,

    -- Importes (SaldoPendiente ahora puede ser negativo cuando la NCA supera lo imputado)
    lc.TOTAL                                                        AS TotalFactura,
    lc.CTACTE                                                       AS ImporteCtaCte,
    COALESCE(imp.TotalImputado, 0)                                  AS TotalImputado,
    lc.CTACTE - COALESCE(imp.TotalImputado, 0)                      AS SaldoPendiente,

    -- Vencimiento
    DATEDIFF(DAY, lc.VENCE, GETDATE())                              AS DiasVencido,
    CASE
        WHEN lc.CTACTE < 0                                          THEN 'Nota crédito'
        WHEN lc.CTACTE - COALESCE(imp.TotalImputado, 0) <= 0        THEN 'Cancelado'
        WHEN lc.VENCE IS NULL OR lc.VENCE >= GETDATE()              THEN 'A Vencer'
        WHEN DATEDIFF(DAY, lc.VENCE, GETDATE()) BETWEEN 1  AND 30   THEN '1-30 días'
        WHEN DATEDIFF(DAY, lc.VENCE, GETDATE()) BETWEEN 31 AND 60   THEN '31-60 días'
        WHEN DATEDIFF(DAY, lc.VENCE, GETDATE()) BETWEEN 61 AND 90   THEN '61-90 días'
        WHEN DATEDIFF(DAY, lc.VENCE, GETDATE()) BETWEEN 91 AND 180  THEN '91-180 días'
        ELSE 'Más de 180 días'
    END                                                             AS TramoVencimiento,

    lc.COMENTARIO
FROM dbo.vw_LibroCompras_Consolidado lc
JOIN dbo.vw_Entidades_Consolidado e
    ON  lc.PROVEEDOR = e.CODIGO
    AND lc.Empresa   = e.Empresa
    AND lc.TipoBase  = e.TipoBase
LEFT JOIN Imputado imp
    ON  lc.CODIGO   = imp.CodigoCompra
    AND lc.Empresa  = imp.Empresa
    AND lc.TipoBase = imp.TipoBase
WHERE lc.CTACTE <> 0;
GO

CREATE OR ALTER VIEW dbo.vw_CtaCte_Clientes_Live AS
WITH Imputado AS (
    -- Suma de lo ya cobrado/aplicado por factura de venta
    SELECT
        Empresa,
        TipoBase,
        VENTA          AS CodigoVenta,
        SUM(IMPORTE)   AS TotalImputado
    FROM dbo.vw_RelacionesCtasCtes_Consolidado
    WHERE VENTA IS NOT NULL AND VENTA <> ''
    GROUP BY Empresa, TipoBase, VENTA
)
SELECT
    lv.Empresa,
    lv.TipoBase,
    'Cliente'                                                       AS TipoEntidad,
    lv.CLIENTE                                                      AS CodigoEntidad,
    e.NOMBRE                                                        AS RazonSocial,
    e.CUIT,

    -- Comprobante
    lv.FECHA,
    lv.VENCE                                                        AS FechaVencimiento,
    lv.COMPROB                                                      AS TipoComprobante,
    lv.PTOEMISOR,
    lv.NUMERO,
    CONCAT(lv.PTOEMISOR, '-', FORMAT(lv.NUMERO, '00000000'))        AS NumeroCompleto,

    -- Importes
    lv.TOTAL                                                        AS TotalFactura,
    lv.CTACTE                                                       AS ImporteCtaCte,   -- parte que va a cta cte
    COALESCE(imp.TotalImputado, 0)                                  AS TotalImputado,   -- ya cobrado/aplicado
    lv.CTACTE - COALESCE(imp.TotalImputado, 0)                     AS SaldoPendiente,  -- lo que falta cobrar

    -- Vencimiento
    DATEDIFF(DAY, lv.VENCE, GETDATE())                              AS DiasVencido,
    CASE
        WHEN lv.CTACTE - COALESCE(imp.TotalImputado, 0) <= 0       THEN 'Cancelado'
        WHEN lv.VENCE IS NULL OR lv.VENCE >= GETDATE()             THEN 'A Vencer'
        WHEN DATEDIFF(DAY, lv.VENCE, GETDATE()) BETWEEN 1  AND 30  THEN '1-30 días'
        WHEN DATEDIFF(DAY, lv.VENCE, GETDATE()) BETWEEN 31 AND 60  THEN '31-60 días'
        WHEN DATEDIFF(DAY, lv.VENCE, GETDATE()) BETWEEN 61 AND 90  THEN '61-90 días'
        WHEN DATEDIFF(DAY, lv.VENCE, GETDATE()) BETWEEN 91 AND 180 THEN '91-180 días'
        ELSE 'Más de 180 días'
    END                                                             AS TramoVencimiento,

    lv.COMENTARIO
FROM dbo.vw_LibroVentas_Consolidado lv

JOIN dbo.vw_Entidades_Consolidado e
    ON  lv.CLIENTE  = e.CODIGO
    AND lv.Empresa  = e.Empresa
    AND lv.TipoBase = e.TipoBase

LEFT JOIN Imputado imp
    ON  lv.CODIGO   = imp.CodigoVenta
    AND lv.Empresa  = imp.Empresa
    AND lv.TipoBase = imp.TipoBase

WHERE lv.CTACTE > 0;   -- solo facturas que fueron a cuenta corriente
GO

IF OBJECT_ID('dbo.Snap_CtaCte_Proveedores', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Snap_CtaCte_Proveedores (
        Empresa           varchar(8)      NOT NULL,
        TipoBase          varchar(11)     NOT NULL,
        TipoEntidad       varchar(9)      NOT NULL,
        CodigoEntidad     nvarchar(255)   NULL,
        RazonSocial       nvarchar(50)    NULL,
        CUIT              nvarchar(11)    NULL,
        FECHA             date            NULL,
        FechaVencimiento  date            NULL,
        TipoComprobante   nvarchar(255)   NULL,
        PTOEMISOR         bigint          NULL,
        NUMERO            bigint          NULL,
        NumeroCompleto    nvarchar(4000)  NOT NULL,
        TotalFactura      decimal(15,2)   NULL,
        ImporteCtaCte     decimal(15,2)   NULL,
        TotalImputado     decimal(38,2)   NULL,
        SaldoPendiente    decimal(38,2)   NULL,
        COMENTARIO        nvarchar(80)    NULL,
        _fecha_snapshot   datetime2(0)    NOT NULL
    );
    CREATE CLUSTERED INDEX CX_Snap_CtaCte_Proveedores ON dbo.Snap_CtaCte_Proveedores (TipoBase, Empresa);
END
GO

IF OBJECT_ID('dbo.Snap_CtaCte_Clientes', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Snap_CtaCte_Clientes (
        Empresa           varchar(8)      NOT NULL,
        TipoBase          varchar(11)     NOT NULL,
        TipoEntidad       varchar(7)      NOT NULL,
        CodigoEntidad     nvarchar(255)   NULL,
        RazonSocial       nvarchar(50)    NULL,
        CUIT              nvarchar(11)    NULL,
        FECHA             date            NULL,
        FechaVencimiento  date            NULL,
        TipoComprobante   nvarchar(255)   NULL,
        PTOEMISOR         int             NULL,
        NUMERO            int             NULL,
        NumeroCompleto    nvarchar(4000)  NOT NULL,
        TotalFactura      decimal(15,2)   NULL,
        ImporteCtaCte     decimal(15,2)   NULL,
        TotalImputado     decimal(38,2)   NULL,
        SaldoPendiente    decimal(38,2)   NULL,
        COMENTARIO        nvarchar(80)    NULL,
        _fecha_snapshot   datetime2(0)    NOT NULL
    );
    CREATE CLUSTERED INDEX CX_Snap_CtaCte_Clientes ON dbo.Snap_CtaCte_Clientes (TipoBase, Empresa);
END
GO

CREATE OR ALTER VIEW dbo.vw_CtaCte_Proveedores_Snap AS
SELECT
    s.Empresa,
    s.TipoBase,
    s.TipoEntidad,
    s.CodigoEntidad,
    s.RazonSocial,
    s.CUIT,
    s.FECHA,
    s.FechaVencimiento,
    s.TipoComprobante,
    s.PTOEMISOR,
    s.NUMERO,
    s.NumeroCompleto,
    s.TotalFactura,
    s.ImporteCtaCte,
    s.TotalImputado,
    s.SaldoPendiente,
    DATEDIFF(DAY, s.FechaVencimiento, GETDATE())                            AS DiasVencido,
    CASE
        WHEN s.ImporteCtaCte < 0                                            THEN 'Nota crédito'
        WHEN s.SaldoPendiente <= 0                                          THEN 'Cancelado'
        WHEN s.FechaVencimiento IS NULL OR s.FechaVencimiento >= GETDATE()  THEN 'A Vencer'
        WHEN DATEDIFF(DAY, s.FechaVencimiento, GETDATE()) BETWEEN 1  AND 30 THEN '1-30 días'
        WHEN DATEDIFF(DAY, s.FechaVencimiento, GETDATE()) BETWEEN 31 AND 60 THEN '31-60 días'
        WHEN DATEDIFF(DAY, s.FechaVencimiento, GETDATE()) BETWEEN 61 AND 90 THEN '61-90 días'
        WHEN DATEDIFF(DAY, s.FechaVencimiento, GETDATE()) BETWEEN 91 AND 180 THEN '91-180 días'
        ELSE 'Más de 180 días'
    END                                                                     AS TramoVencimiento,
    s.COMENTARIO
FROM dbo.Snap_CtaCte_Proveedores s;
GO

CREATE OR ALTER VIEW dbo.vw_CtaCte_Clientes_Snap AS
SELECT
    s.Empresa,
    s.TipoBase,
    s.TipoEntidad,
    s.CodigoEntidad,
    s.RazonSocial,
    s.CUIT,
    s.FECHA,
    s.FechaVencimiento,
    s.TipoComprobante,
    s.PTOEMISOR,
    s.NUMERO,
    s.NumeroCompleto,
    s.TotalFactura,
    s.ImporteCtaCte,
    s.TotalImputado,
    s.SaldoPendiente,
    DATEDIFF(DAY, s.FechaVencimiento, GETDATE())                            AS DiasVencido,
    CASE
        WHEN s.SaldoPendiente <= 0                                          THEN 'Cancelado'
        WHEN s.FechaVencimiento IS NULL OR s.FechaVencimiento >= GETDATE()  THEN 'A Vencer'
        WHEN DATEDIFF(DAY, s.FechaVencimiento, GETDATE()) BETWEEN 1  AND 30 THEN '1-30 días'
        WHEN DATEDIFF(DAY, s.FechaVencimiento, GETDATE()) BETWEEN 31 AND 60 THEN '31-60 días'
        WHEN DATEDIFF(DAY, s.FechaVencimiento, GETDATE()) BETWEEN 61 AND 90 THEN '61-90 días'
        WHEN DATEDIFF(DAY, s.FechaVencimiento, GETDATE()) BETWEEN 91 AND 180 THEN '91-180 días'
        ELSE 'Más de 180 días'
    END                                                                     AS TramoVencimiento,
    s.COMENTARIO
FROM dbo.Snap_CtaCte_Clientes s;
GO
