-- dbo.vw_ChequesDiferidos_Pendientes
--
-- Vista consolidada de cheques propios diferidos emitidos por orden de pago,
-- con todos los campos necesarios para replicar el reporte "Consulta de Cheques
-- a Cobrar/Pagar" (sección Propios a Pagar) del ERP.
--
-- Fuente: <Empresa>.OFICIAL_<Empresa>-DATOS  (CBTE_NOMBR='OPAGO' + cuenta "Diferido").
-- Hoy solo EMPR0011 tiene esa tabla en OFICIAL. Cuando el ETL la copie para otras
-- empresas (EMPR0006, etc.), re-ejecutar este script para regenerar la vista
-- con las nuevas empresas incluidas automáticamente.
--
-- Filtro de "pendientes al corte" se hace en la consulta, no en la vista:
--   WHERE Vencimiento > @FechaCorte
--     AND (Conciliado IS NULL OR Conciliado > @FechaCorte)

SET NOCOUNT ON;

DECLARE @union NVARCHAR(MAX) =
    (SELECT STRING_AGG(CAST(
        'SELECT '''+TABLE_SCHEMA+''' AS Empresa,
                CBTE_FECHA  AS FechaOP,
                CHEQUE_FEC  AS FechaCheque,
                CHEQUE_PAG  AS Vencimiento,
                CHEQUE_NUM  AS NumeroCheque,
                CHEQUE_ORD  AS OrdenCheque,
                NOMBRE      AS Proveedor,
                CUIT        AS CuitProveedor,
                CUENTA_COD  AS CuentaCod,
                CUENTA_NOM  AS CuentaNom,
                CBTE_NOMBR  AS TipoCbte,
                CBTE_PTOEM  AS PtoEmisor,
                CBTE_NUMER  AS NumeroCbte,
                IMPORTE,
                CONCILIADO  AS Conciliado,
                COMENTARIO
         FROM '+QUOTENAME(TABLE_SCHEMA)+'.'+QUOTENAME(TABLE_NAME)+'
         WHERE CBTE_NOMBR = ''OPAGO''
           AND CHEQUE_NUM IS NOT NULL AND CHEQUE_NUM > 0
           AND IMPORTE < 0
           AND CUENTA_NOM LIKE ''%Diferido%'''
        AS NVARCHAR(MAX)),
        CHAR(10) + 'UNION ALL' + CHAR(10))
     FROM INFORMATION_SCHEMA.TABLES
     WHERE TABLE_NAME LIKE 'OFICIAL_EMPR%-DATOS');

IF @union IS NULL
BEGIN
    RAISERROR('No se encontraron tablas OFICIAL_<EMPR>-DATOS. Vista no creada.', 16, 1);
    RETURN;
END

DECLARE @ddl NVARCHAR(MAX) = N'CREATE OR ALTER VIEW dbo.vw_ChequesDiferidos_Pendientes AS' + CHAR(10) + @union + ';';
EXEC sp_executesql @ddl;

PRINT 'Vista dbo.vw_ChequesDiferidos_Pendientes (re)creada con las empresas:';
SELECT TABLE_SCHEMA AS EmpresaIncluida
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME LIKE 'OFICIAL_EMPR%-DATOS'
ORDER BY TABLE_SCHEMA;
