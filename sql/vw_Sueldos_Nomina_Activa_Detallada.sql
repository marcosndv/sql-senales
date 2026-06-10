-- ============================================================================
-- VISTA: dbo.vw_Sueldos_Nomina_Activa_Detallada
-- ----------------------------------------------------------------------------
-- Extiende vw_Sueldos_Nomina_Activa con:
--   - NombreSucursal (nombre del establecimiento)
--   - ActividadSucursal (GASTRONOMICA / ADMINISTRACION / etc.)
--   - TipoTrabajo (COCINA / SERVICIO / OTROS)
--
-- Base para el indicador "Nomina por Sucursal detallada por Servicio y Cocina".
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Sueldos_Nomina_Activa_Detallada
AS
SELECT
    n.*,
    e.Establecimiento     AS NombreSucursal,
    e.ACTIVIDAD           AS ActividadSucursal,
    e.LOCALIDAD,
    COALESCE(pt.TipoTrabajo, 'OTROS') AS TipoTrabajo,
    -- CC informativo: viene del maestro de empleados (no historico).
    -- Para vista historica usar el CC del recibo en vw_Sueldos_ReciboDetalle_Normalizado.
    n.UltimoCtroCostoNombre AS CentroCostoActual
FROM dbo.vw_Sueldos_Nomina_Activa n
LEFT JOIN dbo.vw_Sueldos_Establecimientos e
       ON e.Empresa = n.Empresa
      AND e.IdEstablecimiento = n.UltimoEstablecimientoCod
LEFT JOIN dbo.vw_Sueldos_Puestos_Tipificados pt
       ON pt.PuestoNombre = n.UltimoPuestoNombre;
