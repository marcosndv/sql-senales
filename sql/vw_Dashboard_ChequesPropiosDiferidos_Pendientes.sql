-- ============================================================================
-- VISTA: dbo.vw_Dashboard_ChequesPropiosDiferidos_Pendientes
-- ----------------------------------------------------------------------------
-- Cartera viva de cheques propios diferidos emitidos por orden de pago,
-- 1 fila por (Empresa, NumeroCheque, CuentaCod), con campos para dashboard:
--   - DiasParaVencer / TramoVencimiento
--   - Proveedor + CuitProveedor desde OFICIAL_ENTIDADES
--   - CuentaNom desde OFICIAL_PLANDECUENTAS
--
-- Fuente: <Empresa>.OFICIAL_LIBROFONDOSDETALLADO + OFICIAL_LIBROFONDOS
--         Cuentas "Cheques de Pago Diferido a Pagar" por empresa:
--           EMPR0006: 211300
--           EMPR0010: 211030
--           EMPR0011: 211030
--           EMPR0012: 211030 (BBVA), 211043 (Santander), 211044 (Macro), 211045 (Supervielle)
--
-- Pendientes = HAVING SUM(IMPORTE) < 0
--   (el asiento de cancelacion anula la emision: suma llega a 0 cuando se cobra)
--
-- Para reporte historico al @FechaCorte:
--   WHERE Vencimiento > @FechaCorte
--     AND FechaOP <= @FechaCorte
--     AND (Conciliado IS NULL OR Conciliado > @FechaCorte)
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Dashboard_ChequesPropiosDiferidos_Pendientes AS
WITH base AS (

    -- ---- EMPR0006 (cuenta 211300) ------------------------------------------
    SELECT
        'EMPR0006' AS Empresa,
        CAST(d.CHQNUMERO AS INT) AS NumeroCheque,
        d.CUENTA AS CuentaCod,
        MIN(pc.NOMBRE) AS CuentaNom,
        MIN(CASE WHEN CAST(d.IMPORTE AS DECIMAL(18,2)) < 0
                 THEN TRY_CAST(f.FECHA AS DATE) END) AS FechaOP,
        MIN(TRY_CAST(d.CHQFECHA AS DATE))  AS FechaCheque,
        MIN(TRY_CAST(d.CHQVENCE AS DATE))  AS Vencimiento,
        MAX(d.CHQORDEN)                    AS Beneficiario,
        MAX(e.NOMBRE)                      AS Proveedor,
        MAX(e.CUIT)                        AS CuitProveedor,
        SUM(CAST(d.IMPORTE AS DECIMAL(18,2))) AS Importe,
        MAX(TRY_CAST(NULLIF(d.CONCILIADO,'') AS DATE)) AS Conciliado
    FROM EMPR0006.OFICIAL_LIBROFONDOSDETALLADO d
    JOIN EMPR0006.OFICIAL_LIBROFONDOS   f  ON f.CODIGO  = d.LBRFONDOS
    JOIN EMPR0006.OFICIAL_ENTIDADES     e  ON e.CODIGO  = f.ENTIDAD
    LEFT JOIN EMPR0006.OFICIAL_PLANDECUENTAS pc ON pc.CODIGO = d.CUENTA
    WHERE d.CUENTA = '211300'
      AND CAST(d.CHQNUMERO AS INT) > 0
    GROUP BY CAST(d.CHQNUMERO AS INT), d.CUENTA
    HAVING SUM(CAST(d.IMPORTE AS DECIMAL(18,2))) < 0

    UNION ALL

    -- ---- EMPR0010 (cuenta 211030) ------------------------------------------
    SELECT
        'EMPR0010',
        CAST(d.CHQNUMERO AS INT),
        d.CUENTA,
        MIN(pc.NOMBRE),
        MIN(CASE WHEN CAST(d.IMPORTE AS DECIMAL(18,2)) < 0
                 THEN TRY_CAST(f.FECHA AS DATE) END),
        MIN(TRY_CAST(d.CHQFECHA AS DATE)),
        MIN(TRY_CAST(d.CHQVENCE AS DATE)),
        MAX(d.CHQORDEN),
        MAX(e.NOMBRE),
        MAX(e.CUIT),
        SUM(CAST(d.IMPORTE AS DECIMAL(18,2))),
        MAX(TRY_CAST(NULLIF(d.CONCILIADO,'') AS DATE))
    FROM EMPR0010.OFICIAL_LIBROFONDOSDETALLADO d
    JOIN EMPR0010.OFICIAL_LIBROFONDOS   f  ON f.CODIGO  = d.LBRFONDOS
    JOIN EMPR0010.OFICIAL_ENTIDADES     e  ON e.CODIGO  = f.ENTIDAD
    LEFT JOIN EMPR0010.OFICIAL_PLANDECUENTAS pc ON pc.CODIGO = d.CUENTA
    WHERE d.CUENTA = '211030'
      AND CAST(d.CHQNUMERO AS INT) > 0
    GROUP BY CAST(d.CHQNUMERO AS INT), d.CUENTA
    HAVING SUM(CAST(d.IMPORTE AS DECIMAL(18,2))) < 0

    UNION ALL

    -- ---- EMPR0011 (cuenta 211030) ------------------------------------------
    SELECT
        'EMPR0011',
        CAST(d.CHQNUMERO AS INT),
        d.CUENTA,
        MIN(pc.NOMBRE),
        MIN(CASE WHEN CAST(d.IMPORTE AS DECIMAL(18,2)) < 0
                 THEN TRY_CAST(f.FECHA AS DATE) END),
        MIN(TRY_CAST(d.CHQFECHA AS DATE)),
        MIN(TRY_CAST(d.CHQVENCE AS DATE)),
        MAX(d.CHQORDEN),
        MAX(e.NOMBRE),
        MAX(e.CUIT),
        SUM(CAST(d.IMPORTE AS DECIMAL(18,2))),
        MAX(TRY_CAST(NULLIF(d.CONCILIADO,'') AS DATE))
    FROM EMPR0011.OFICIAL_LIBROFONDOSDETALLADO d
    JOIN EMPR0011.OFICIAL_LIBROFONDOS   f  ON f.CODIGO  = d.LBRFONDOS
    JOIN EMPR0011.OFICIAL_ENTIDADES     e  ON e.CODIGO  = f.ENTIDAD
    LEFT JOIN EMPR0011.OFICIAL_PLANDECUENTAS pc ON pc.CODIGO = d.CUENTA
    WHERE d.CUENTA = '211030'
      AND CAST(d.CHQNUMERO AS INT) > 0
    GROUP BY CAST(d.CHQNUMERO AS INT), d.CUENTA
    HAVING SUM(CAST(d.IMPORTE AS DECIMAL(18,2))) < 0

    UNION ALL

    -- ---- EMPR0012 (cuentas 211030/043/044/045 = BBVA/Santander/Macro/Supervielle)
    SELECT
        'EMPR0012',
        CAST(d.CHQNUMERO AS INT),
        d.CUENTA,
        MIN(pc.NOMBRE),
        MIN(CASE WHEN CAST(d.IMPORTE AS DECIMAL(18,2)) < 0
                 THEN TRY_CAST(f.FECHA AS DATE) END),
        MIN(TRY_CAST(d.CHQFECHA AS DATE)),
        MIN(TRY_CAST(d.CHQVENCE AS DATE)),
        MAX(d.CHQORDEN),
        MAX(e.NOMBRE),
        MAX(e.CUIT),
        SUM(CAST(d.IMPORTE AS DECIMAL(18,2))),
        MAX(TRY_CAST(NULLIF(d.CONCILIADO,'') AS DATE))
    FROM EMPR0012.OFICIAL_LIBROFONDOSDETALLADO d
    JOIN EMPR0012.OFICIAL_LIBROFONDOS   f  ON f.CODIGO  = d.LBRFONDOS
    JOIN EMPR0012.OFICIAL_ENTIDADES     e  ON e.CODIGO  = f.ENTIDAD
    LEFT JOIN EMPR0012.OFICIAL_PLANDECUENTAS pc ON pc.CODIGO = d.CUENTA
    WHERE d.CUENTA IN ('211030','211043','211044','211045')
      AND CAST(d.CHQNUMERO AS INT) > 0
    GROUP BY CAST(d.CHQNUMERO AS INT), d.CUENTA
    HAVING SUM(CAST(d.IMPORTE AS DECIMAL(18,2))) < 0

)
SELECT
    b.Empresa,
    COALESCE(ce.NombreEmpresa, b.Empresa) AS NombreEmpresa,
    b.NumeroCheque,
    b.CuentaCod,
    b.CuentaNom,
    b.FechaOP,
    b.FechaCheque,
    b.Vencimiento,
    CONVERT(CHAR(6), b.Vencimiento, 112)                              AS PeriodoVencimiento,
    b.Beneficiario,
    b.Proveedor,
    b.CuitProveedor,
    b.Importe,
    b.Conciliado,
    DATEDIFF(day, CAST(GETDATE() AS date), b.Vencimiento)             AS DiasParaVencer,
    CASE
        WHEN b.Vencimiento < CAST(GETDATE() AS date)                  THEN '1. Vencido'
        WHEN b.Vencimiento = CAST(GETDATE() AS date)                  THEN '2. Vence hoy'
        WHEN DATEDIFF(day, GETDATE(), b.Vencimiento) <=  7            THEN '3. 1-7 dias'
        WHEN DATEDIFF(day, GETDATE(), b.Vencimiento) <= 15            THEN '4. 8-15 dias'
        WHEN DATEDIFF(day, GETDATE(), b.Vencimiento) <= 30            THEN '5. 16-30 dias'
        WHEN DATEDIFF(day, GETDATE(), b.Vencimiento) <= 60            THEN '6. 31-60 dias'
        WHEN DATEDIFF(day, GETDATE(), b.Vencimiento) <= 90            THEN '7. 61-90 dias'
        ELSE                                                               '8. +90 dias'
    END                                                               AS TramoVencimiento
FROM base b
LEFT JOIN dbo.Config_Empresas ce ON ce.Empresa = b.Empresa;
