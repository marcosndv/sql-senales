-- ============================================================
-- Paso B: vw_CtaCte_Proveedores / vw_CtaCte_Clientes leen del snapshot
-- ============================================================
-- Aplicar SOLO después de:
--   1) 10_snapshot_ctacte.sql
--   2) 11_refresh_snap_ctacte.sql corrido al menos una vez
--   3) validar vw_CtaCte_*_Snap = vw_CtaCte_*_Live (0 filas de diferencia)
-- Mismas columnas, orden y tipos que antes: vw_FlujoFondos_Proyectado, vw_DeudaGlobal,
-- flujo-fondos-dashboard y proveedores-dashboard no cambian.
-- El dato queda al momento del último refresh (lo corre export_data.ps1 en cada corrida).
--
-- VOLVER ATRÁS (cálculo en vivo, lento):
--   CREATE OR ALTER VIEW dbo.vw_CtaCte_Proveedores AS SELECT * FROM dbo.vw_CtaCte_Proveedores_Live;
--   CREATE OR ALTER VIEW dbo.vw_CtaCte_Clientes    AS SELECT * FROM dbo.vw_CtaCte_Clientes_Live;
-- ============================================================

CREATE OR ALTER VIEW dbo.vw_CtaCte_Proveedores AS
SELECT Empresa, TipoBase, TipoEntidad, CodigoEntidad, RazonSocial, CUIT, FECHA, FechaVencimiento,
       TipoComprobante, PTOEMISOR, NUMERO, NumeroCompleto, TotalFactura, ImporteCtaCte,
       TotalImputado, SaldoPendiente, DiasVencido, TramoVencimiento, COMENTARIO
FROM dbo.vw_CtaCte_Proveedores_Snap;
GO

CREATE OR ALTER VIEW dbo.vw_CtaCte_Clientes AS
SELECT Empresa, TipoBase, TipoEntidad, CodigoEntidad, RazonSocial, CUIT, FECHA, FechaVencimiento,
       TipoComprobante, PTOEMISOR, NUMERO, NumeroCompleto, TotalFactura, ImporteCtaCte,
       TotalImputado, SaldoPendiente, DiasVencido, TramoVencimiento, COMENTARIO
FROM dbo.vw_CtaCte_Clientes_Snap;
GO
