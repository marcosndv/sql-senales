-- ============================================================
-- Flujo de Fondos - Vistas gerenciales
-- ============================================================
-- Depende de: 01_tables.sql, Config_Empresas, vw_ChequesPropios_Pendientes,
--             vw_ChequesTerceros_EnCartera, vw_CtaCte_Proveedores.
-- ============================================================

-- ---- Posición actual: último snapshot de bancos por empresa ----
CREATE OR ALTER VIEW dbo.vw_FlujoFondos_PosicionActual AS
WITH UltimoSnapshot AS (
    SELECT MAX(FechaSaldo) AS FechaSaldo FROM dbo.Manual_SaldosBancos
),
SaldosHoy AS (
    SELECT
        s.FechaSaldo,
        s.RazonSocialExcel,
        COALESCE(m.Empresa, 'SIN_EMPRESA')                          AS Empresa,
        s.Banco,
        s.Cuenta,
        ISNULL(s.Saldo, 0)                                          AS Saldo,
        ISNULL(s.FCI, 0)                                            AS FCI,
        ISNULL(s.MPago, 0)                                          AS MPago,
        ISNULL(s.Pix, 0)                                            AS Pix,
        ISNULL(s.DescubiertoAutorizado, 0)                          AS DescubiertoAutorizado,
        -- Si el Excel trae Disponible, se respeta; si no, se calcula.
        COALESCE(s.Disponible,
                 ISNULL(s.Saldo, 0) + ISNULL(s.FCI, 0) + ISNULL(s.MPago, 0)
                 + ISNULL(s.Pix, 0) + ISNULL(s.DescubiertoAutorizado, 0)) AS Disponible
    FROM dbo.Manual_SaldosBancos s
    INNER JOIN UltimoSnapshot u ON u.FechaSaldo = s.FechaSaldo
    LEFT JOIN dbo.Config_MapeoRazonSocial m
        ON m.RazonSocialExcel = s.RazonSocialExcel
)
SELECT
    FechaSaldo,
    Empresa,
    COALESCE((SELECT NombreEmpresa FROM dbo.Config_Empresas ce WHERE ce.Empresa = SaldosHoy.Empresa), Empresa) AS NombreEmpresa,
    RazonSocialExcel,
    Banco,
    Cuenta,
    Saldo,
    FCI,
    MPago,
    Pix,
    DescubiertoAutorizado,
    Disponible
FROM SaldosHoy;
