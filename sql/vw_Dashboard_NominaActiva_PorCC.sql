-- ============================================================================
-- VISTA: dbo.vw_Dashboard_NominaActiva_PorCC
-- ----------------------------------------------------------------------------
-- Snapshot de la nomina activa actual desglosada por CC x TipoTrabajo.
-- Una fila por empleado activo, con su CC actual y TipoTrabajo (COCINA /
-- SERVICIO / OTROS).
--
-- PeriodoEvaluado = ultimo periodo donde liquidaron >= 5 empresas (mismo
-- criterio que vw_Sueldos_Nomina_Activa).
--
-- Para agregados:
--   - Por CC:          GROUP BY CodigoCC, NombreCC
--   - Por TipoTrabajo: GROUP BY TipoTrabajo
--   - Matriz CC x TT:  GROUP BY CodigoCC, NombreCC, TipoTrabajo
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Dashboard_NominaActiva_PorCC AS
SELECT
    PeriodoEvaluado,
    Empresa,
    RazonSocial,
    UltimoCtroCostoCod        AS CodigoCC,
    UltimoCtroCostoNombre     AS NombreCC,
    TipoTrabajo,
    NombreSucursal            AS NombreEstablecimiento,
    ActividadSucursal,
    IdEmpleado,
    CUIL,
    NombreEmpleado,
    UltimoPuestoNombre,
    FechaIngreso,
    FchAntiguedad
FROM dbo.vw_Sueldos_Nomina_Activa_Detallada;
