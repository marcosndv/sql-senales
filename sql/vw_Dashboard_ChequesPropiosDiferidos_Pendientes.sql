-- ============================================================================
-- VISTA: dbo.vw_Dashboard_ChequesPropiosDiferidos_Pendientes
-- ----------------------------------------------------------------------------
-- Cartera viva de cheques propios diferidos, 1 fila por (Empresa, NumeroCheque,
-- CuentaCod), enriquecida con DiasParaVencer y TramoVencimiento para dashboard.
--
-- Fuente: <Empresa>.OFICIAL_LIBROFONDOSDETALLADO + OFICIAL_LIBROFONDOS +
--         OFICIAL_ENTIDADES + OFICIAL_PLANDECUENTAS
--
-- Empresas incluidas: todas las que tienen OFICIAL_LIBROFONDOSDETALLADO y al
-- menos una cuenta cuyo NOMBRE contiene "Diferido" y "Pagar" en PLANDECUENTAS.
-- Se auto-descubren al ejecutar este script — re-ejecutar si se agrega empresa.
--
-- Pendiente = HAVING SUM(IMPORTE) < 0
--   El asiento de cancelacion suma IMPORTE > 0 al mismo CHQNUMERO/CUENTA;
--   cuando se cobra el neto llega a 0 y deja de aparecer.
--
-- Para reporte historico al @FechaCorte:
--   WHERE FechaOP     <= @FechaCorte
--     AND Vencimiento >  @FechaCorte
--     AND (Conciliado IS NULL OR Conciliado > @FechaCorte)
-- ============================================================================
SET NOCOUNT ON;

DECLARE @union NVARCHAR(MAX) = N'';

SELECT @union += N'
    SELECT
        ' + QUOTENAME(t.TABLE_SCHEMA, '''') + N' AS Empresa,
        CAST(d.CHQNUMERO AS INT)   AS NumeroCheque,
        d.CUENTA                   AS CuentaCod,
        MIN(pc.NOMBRE)             AS CuentaNom,
        MIN(CASE WHEN CAST(d.IMPORTE AS DECIMAL(18,2)) < 0
                 THEN TRY_CAST(f.FECHA AS DATE) END) AS FechaOP,
        MIN(TRY_CAST(d.CHQFECHA AS DATE))            AS FechaCheque,
        MIN(TRY_CAST(d.CHQVENCE AS DATE))            AS Vencimiento,
        MAX(d.CHQORDEN)            AS Beneficiario,
        MAX(e.NOMBRE)              AS Proveedor,
        MAX(e.CUIT)                AS CuitProveedor,
        SUM(CAST(d.IMPORTE AS DECIMAL(18,2))) AS Importe,
        MAX(TRY_CAST(NULLIF(d.CONCILIADO,'''') AS DATE)) AS Conciliado
    FROM ' + QUOTENAME(t.TABLE_SCHEMA) + N'.OFICIAL_LIBROFONDOSDETALLADO d
    JOIN ' + QUOTENAME(t.TABLE_SCHEMA) + N'.OFICIAL_LIBROFONDOS       f  ON f.CODIGO = d.LBRFONDOS
    JOIN ' + QUOTENAME(t.TABLE_SCHEMA) + N'.OFICIAL_ENTIDADES          e  ON e.CODIGO = f.ENTIDAD
    JOIN ' + QUOTENAME(t.TABLE_SCHEMA) + N'.OFICIAL_PLANDECUENTAS      pc ON pc.CODIGO = d.CUENTA
    WHERE (pc.NOMBRE LIKE ''%Diferido%Pagar%'' OR pc.NOMBRE LIKE ''%Pago Diferido%'')
      AND CAST(d.CHQNUMERO AS INT) > 0
    GROUP BY CAST(d.CHQNUMERO AS INT), d.CUENTA
    HAVING SUM(CAST(d.IMPORTE AS DECIMAL(18,2))) < 0
UNION ALL'
FROM INFORMATION_SCHEMA.TABLES t
WHERE t.TABLE_NAME = 'OFICIAL_LIBROFONDOSDETALLADO'
ORDER BY t.TABLE_SCHEMA;

-- Quita el ultimo UNION ALL
SET @union = LEFT(@union, LEN(@union) - 9);

IF @union = N''
BEGIN
    RAISERROR('No se encontraron empresas con OFICIAL_LIBROFONDOSDETALLADO. Vista no creada.', 16, 1);
    RETURN;
END

DECLARE @ddl NVARCHAR(MAX) = N'
CREATE OR ALTER VIEW dbo.vw_Dashboard_ChequesPropiosDiferidos_Pendientes AS
WITH base AS (' + @union + N'
)
SELECT
    b.Empresa,
    COALESCE(ce.NombreEmpresa, b.Empresa)                             AS NombreEmpresa,
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
        WHEN b.Vencimiento < CAST(GETDATE() AS date)                  THEN ''1. Vencido''
        WHEN b.Vencimiento = CAST(GETDATE() AS date)                  THEN ''2. Vence hoy''
        WHEN DATEDIFF(day, GETDATE(), b.Vencimiento) <=  7            THEN ''3. 1-7 dias''
        WHEN DATEDIFF(day, GETDATE(), b.Vencimiento) <= 15            THEN ''4. 8-15 dias''
        WHEN DATEDIFF(day, GETDATE(), b.Vencimiento) <= 30            THEN ''5. 16-30 dias''
        WHEN DATEDIFF(day, GETDATE(), b.Vencimiento) <= 60            THEN ''6. 31-60 dias''
        WHEN DATEDIFF(day, GETDATE(), b.Vencimiento) <= 90            THEN ''7. 61-90 dias''
        ELSE                                                               ''8. +90 dias''
    END                                                               AS TramoVencimiento
FROM base b
LEFT JOIN dbo.Config_Empresas ce ON ce.Empresa = b.Empresa;';

EXEC sp_executesql @ddl;

PRINT 'Vista dbo.vw_Dashboard_ChequesPropiosDiferidos_Pendientes (re)creada con empresas:';
SELECT t.TABLE_SCHEMA AS EmpresaIncluida
FROM INFORMATION_SCHEMA.TABLES t
WHERE t.TABLE_NAME = 'OFICIAL_LIBROFONDOSDETALLADO'
ORDER BY t.TABLE_SCHEMA;
