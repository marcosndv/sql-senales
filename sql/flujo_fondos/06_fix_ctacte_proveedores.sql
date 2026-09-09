-- ============================================================
-- Fix vw_CtaCte_Proveedores: incluir NCA y ajustes negativos
-- Antes: WHERE lc.CTACTE > 0 excluía NCA (COMPROB=3, CTACTE negativo)
--        Resultado: saldo por proveedor inflado (no neteaba créditos a favor)
-- Ahora: WHERE lc.CTACTE <> 0 trae todo lo que va a cuenta corriente,
--        con signo natural. Sumar SaldoPendiente por proveedor = saldo neto real.
-- ============================================================

CREATE OR ALTER VIEW dbo.vw_CtaCte_Proveedores AS
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
