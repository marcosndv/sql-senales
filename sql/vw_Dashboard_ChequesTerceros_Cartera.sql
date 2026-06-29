-- ============================================================================
-- VISTA: dbo.vw_Dashboard_ChequesTerceros_Cartera
-- ----------------------------------------------------------------------------
-- Cartera viva de cheques de terceros, 1 fila por cheque, enriquecida con:
--   - RazonSocial de la empresa (desde Config_Empresas)
--   - DiasParaVencer / DiasEnCartera / DiasPlazo
--   - TramoVencimiento clasificado (Vencido, Vence hoy, 1-7d, 8-15d, ...)
--   - PeriodoVencimiento (YYYYMM) para agrupar mes a mes
--
-- Fuente: dbo.vw_ChequesTerceros_Consolidado (UNION de [EMPRxxxx].OFICIAL_CHEQUESTERCEROS).
--
-- Nota: el campo CODIGO de la fuente es un ID secuencial por empresa, NO un
-- estado. La vista vieja `vw_ChequesTerceros_EnCartera` filtra `CODIGO > 1`
-- creyendo que era estado y descarta cheques validos; este reporte NO
-- aplica ese filtro.
--
-- Se excluyen filas con IMPORTE = 0 (2 registros basura en EMPR0009/EMPR0021).
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Dashboard_ChequesTerceros_Cartera AS
WITH base AS (
    SELECT
        ct.Empresa,
        ce.NombreEmpresa,
        ct.CODIGO       AS ChequeId,
        LTRIM(RTRIM(ct.EMISOR)) AS Emisor,
        ct.BANCO        AS BancoCodigo,
        ct.SUCURSAL     AS Sucursal,
        ct.NUMERO       AS NumeroCheque,
        ct.IMPORTE      AS Importe,
        ct.FECHA        AS FechaEmision,
        ct.VENCIM       AS FechaVencimiento,
        ct._fecha_carga AS FechaCarga
    FROM dbo.vw_ChequesTerceros_Consolidado ct
    LEFT JOIN dbo.Config_Empresas ce ON ce.Empresa = ct.Empresa
    WHERE ct.IMPORTE > 0
)
SELECT
    Empresa,
    COALESCE(NombreEmpresa, Empresa) AS NombreEmpresa,
    ChequeId,
    CASE WHEN Emisor = '' THEN '(SIN EMISOR)' ELSE Emisor END AS Emisor,
    BancoCodigo,
    Sucursal,
    NumeroCheque,
    Importe,
    FechaEmision,
    FechaVencimiento,
    CONVERT(CHAR(6), FechaVencimiento, 112) AS PeriodoVencimiento,
    DATEDIFF(day, CAST(GETDATE() AS date), FechaVencimiento) AS DiasParaVencer,
    DATEDIFF(day, FechaEmision, CAST(GETDATE() AS date))     AS DiasEnCartera,
    DATEDIFF(day, FechaEmision, FechaVencimiento)            AS DiasPlazo,
    CASE
        WHEN FechaVencimiento < CAST(GETDATE() AS date) THEN '1. Vencido'
        WHEN FechaVencimiento = CAST(GETDATE() AS date) THEN '2. Vence hoy'
        WHEN DATEDIFF(day, GETDATE(), FechaVencimiento) <= 7  THEN '3. 1-7 dias'
        WHEN DATEDIFF(day, GETDATE(), FechaVencimiento) <= 15 THEN '4. 8-15 dias'
        WHEN DATEDIFF(day, GETDATE(), FechaVencimiento) <= 30 THEN '5. 16-30 dias'
        WHEN DATEDIFF(day, GETDATE(), FechaVencimiento) <= 60 THEN '6. 31-60 dias'
        WHEN DATEDIFF(day, GETDATE(), FechaVencimiento) <= 90 THEN '7. 61-90 dias'
        ELSE '8. +90 dias'
    END AS TramoVencimiento,
    FechaCarga
FROM base;
