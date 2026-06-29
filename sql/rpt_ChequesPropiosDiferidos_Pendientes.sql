-- Informe: Cheques propios diferidos pendientes al @FechaCorte
-- Fuente: <Empresa>.OFICIAL_<Empresa>-DATOS (mismo formato para EMPR0011, Empr9998 — falta agregar al ETL para EMPR0006).
-- Filtro: orden de pago (OPAGO) + cuenta contable "Pago Diferido" + cheque sin conciliar o conciliado posterior al corte.
-- Replica el reporte "Consulta de Cheques a Cobrar/Pagar" del ERP (sección "Cheques Propios a Pagar").

DECLARE @FechaCorte DATE = '2024-03-01';   -- ajustar
DECLARE @Empresa    SYSNAME = 'EMPR0011';  -- empresa a consultar

DECLARE @sql NVARCHAR(MAX) = N'
SELECT
    CBTE_FECHA      AS FechaOP,
    CHEQUE_FEC      AS FechaCheque,
    CHEQUE_PAG      AS Vencimiento,
    DATEDIFF(DAY, @Corte, CHEQUE_PAG) AS DiasRestantes,
    CHEQUE_NUM      AS NumeroCheque,
    CHEQUE_ORD      AS OrdenCheque,
    NOMBRE          AS Proveedor,
    CUIT,
    CUENTA_COD      AS CuentaCod,
    CUENTA_NOM      AS CuentaNom,
    CBTE_NOMBR      AS TipoCbte,
    CBTE_PTOEM      AS PtoEmisor,
    CBTE_NUMER      AS NumeroCbte,
    IMPORTE,
    CONCILIADO,
    COMENTARIO
FROM ' + QUOTENAME(@Empresa) + '.' + QUOTENAME('OFICIAL_' + @Empresa + '-DATOS') + '
WHERE CBTE_NOMBR = ''OPAGO''
  AND CHEQUE_NUM IS NOT NULL AND CHEQUE_NUM > 0
  AND IMPORTE < 0
  AND CUENTA_NOM LIKE ''%Diferido%''
  AND CHEQUE_PAG > @Corte
  AND (CONCILIADO IS NULL OR CONCILIADO > @Corte)
ORDER BY CHEQUE_PAG, NOMBRE;';

EXEC sp_executesql @sql, N'@Corte DATE', @Corte = @FechaCorte;
