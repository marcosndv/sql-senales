-- ============================================================
-- vw_FlujoFondos_DeudaGlobal
-- Consolida deudas por empresa y origen (proveedores + cheques propios +
-- préstamos bancarios + planes ARCA). Cuando entre IMPOSITIVO se suma acá.
-- ============================================================

CREATE OR ALTER VIEW dbo.vw_FlujoFondos_DeudaGlobal AS
WITH Hoy AS (SELECT CAST(GETDATE() AS DATE) AS D),
Base AS (
    -- Proveedores (aplica filtro > 36m como en el resto del dashboard)
    SELECT
        v.Empresa                                       AS Empresa,
        'Proveedores'                                   AS Origen,
        v.SaldoPendiente                                AS Deuda,
        CAST(v.FechaVencimiento AS DATE)                AS FechaVto
    FROM dbo.vw_CtaCte_Proveedores v
    WHERE v.TipoBase = 'OFICIAL'
      AND v.SaldoPendiente > 0
      AND v.FECHA >= DATEADD(month, -36, GETDATE())

    UNION ALL

    -- Cheques propios diferidos por pagar
    SELECT
        cp.Empresa                                      AS Empresa,
        'Cheques propios'                               AS Origen,
        cp.Importe                                      AS Deuda,
        CAST(cp.FechaPagoDiferido AS DATE)              AS FechaVto
    FROM dbo.vw_ChequesPropios_Pendientes cp
    WHERE cp.TipoBase = 'OFICIAL'
      AND cp.Importe > 0
      AND cp.FechaPagoDiferido IS NOT NULL

    UNION ALL

    -- Préstamos bancarios + Planes ARCA (la vista ya trae Origen)
    SELECT
        fp.Empresa                                      AS Empresa,
        fp.Origen                                       AS Origen,
        fp.ImporteCuota                                 AS Deuda,
        CAST(fp.FechaVto AS DATE)                       AS FechaVto
    FROM dbo.vw_FlujoFondos_Prestamos fp
    WHERE fp.FechaVto IS NOT NULL
      AND ISNULL(fp.ImporteCuota, 0) > 0
)
SELECT
    b.Empresa,
    COALESCE((SELECT NombreEmpresa FROM dbo.Config_Empresas ce WHERE ce.Empresa = b.Empresa), b.Empresa) AS NombreEmpresa,
    b.Origen,
    b.Deuda,
    b.FechaVto,
    CASE WHEN b.FechaVto < h.D THEN 1 ELSE 0 END                       AS EsVencida,
    CASE WHEN b.FechaVto BETWEEN h.D AND DATEADD(day, 30, h.D) THEN 1 ELSE 0 END AS EnProx30,
    DATEDIFF(day, h.D, b.FechaVto)                                     AS DiasAlVto
FROM Base b
CROSS JOIN Hoy h;
