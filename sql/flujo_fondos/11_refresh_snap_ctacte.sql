-- ============================================================
-- Refresh de Snap_CtaCte_Proveedores / Snap_CtaCte_Clientes
-- ============================================================
-- Lo corre export_data.ps1 al inicio de cada refresh del dashboard (un solo lote, sin GO).
-- El cálculo lento va a #temp FUERA de la transacción; el reemplazo (TRUNCATE + INSERT)
-- es corto, así que quien lea vw_CtaCte_* nunca ve las tablas vacías ni espera ~40 s.
-- Requiere 10_snapshot_ctacte.sql aplicado.
-- ============================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @inicio datetime2(0) = SYSDATETIME();
DECLARE @t0 datetime2(3) = SYSDATETIME();

SELECT Empresa, TipoBase, TipoEntidad, CodigoEntidad, RazonSocial, CUIT, FECHA, FechaVencimiento,
       TipoComprobante, PTOEMISOR, NUMERO, NumeroCompleto, TotalFactura, ImporteCtaCte,
       TotalImputado, SaldoPendiente, COMENTARIO
INTO #prov
FROM dbo.vw_CtaCte_Proveedores_Live;

DECLARE @t1 datetime2(3) = SYSDATETIME();

SELECT Empresa, TipoBase, TipoEntidad, CodigoEntidad, RazonSocial, CUIT, FECHA, FechaVencimiento,
       TipoComprobante, PTOEMISOR, NUMERO, NumeroCompleto, TotalFactura, ImporteCtaCte,
       TotalImputado, SaldoPendiente, COMENTARIO
INTO #cli
FROM dbo.vw_CtaCte_Clientes_Live;

DECLARE @t2 datetime2(3) = SYSDATETIME();

BEGIN TRANSACTION;

TRUNCATE TABLE dbo.Snap_CtaCte_Proveedores;
INSERT INTO dbo.Snap_CtaCte_Proveedores
    (Empresa, TipoBase, TipoEntidad, CodigoEntidad, RazonSocial, CUIT, FECHA, FechaVencimiento,
     TipoComprobante, PTOEMISOR, NUMERO, NumeroCompleto, TotalFactura, ImporteCtaCte,
     TotalImputado, SaldoPendiente, COMENTARIO, _fecha_snapshot)
SELECT Empresa, TipoBase, TipoEntidad, CodigoEntidad, RazonSocial, CUIT, FECHA, FechaVencimiento,
       TipoComprobante, PTOEMISOR, NUMERO, NumeroCompleto, TotalFactura, ImporteCtaCte,
       TotalImputado, SaldoPendiente, COMENTARIO, @inicio
FROM #prov;

TRUNCATE TABLE dbo.Snap_CtaCte_Clientes;
INSERT INTO dbo.Snap_CtaCte_Clientes
    (Empresa, TipoBase, TipoEntidad, CodigoEntidad, RazonSocial, CUIT, FECHA, FechaVencimiento,
     TipoComprobante, PTOEMISOR, NUMERO, NumeroCompleto, TotalFactura, ImporteCtaCte,
     TotalImputado, SaldoPendiente, COMENTARIO, _fecha_snapshot)
SELECT Empresa, TipoBase, TipoEntidad, CodigoEntidad, RazonSocial, CUIT, FECHA, FechaVencimiento,
       TipoComprobante, PTOEMISOR, NUMERO, NumeroCompleto, TotalFactura, ImporteCtaCte,
       TotalImputado, SaldoPendiente, COMENTARIO, @inicio
FROM #cli;

COMMIT TRANSACTION;

SELECT (SELECT COUNT(*) FROM dbo.Snap_CtaCte_Proveedores)   AS FilasProveedores,
       (SELECT COUNT(*) FROM dbo.Snap_CtaCte_Clientes)      AS FilasClientes,
       DATEDIFF(millisecond, @t0, @t1) / 1000.0             AS SegProveedores,
       DATEDIFF(millisecond, @t1, @t2) / 1000.0             AS SegClientes,
       DATEDIFF(millisecond, @t2, SYSDATETIME()) / 1000.0   AS SegReemplazo,
       @inicio                                              AS FechaSnapshot;
