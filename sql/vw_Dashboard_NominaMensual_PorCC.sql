-- ============================================================================
-- VISTA: dbo.vw_Dashboard_NominaMensual_PorCC
-- ----------------------------------------------------------------------------
-- Agregado para dashboard: cantidad de personas en nomina estable por
-- (Periodo, CodigoCC, NombreCC, TipoTrabajo).
--
-- Una persona con varios CC en un mes cuenta 1 vez en cada CC (split por
-- STRING_AGG con separador ' / '). El consolidado se obtiene en el front
-- usando COUNT DISTINCT sobre (Empresa, IdEmpleado) -- por eso la vista
-- expone los IDs.
--
-- Para totales rapidos sin distinct, usar el JSON exportado que ya trae
-- el consolidado precalculado.
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Dashboard_NominaMensual_PorCC AS
WITH base AS (
    SELECT
        e.Empresa,
        e.Periodo,
        e.IdEmpleado,
        e.CUIL,
        e.NombreEmpleado,
        e.NombreSucursal      AS NombreEstablecimiento,
        e.CodigosCentroCosto,
        e.NombresCentroCosto,
        e.TipoTrabajo
    FROM dbo.vw_Sueldos_NominaMensual_Estable e
),
split AS (
    SELECT
        b.Empresa,
        b.Periodo,
        b.IdEmpleado,
        b.CUIL,
        b.NombreEmpleado,
        b.NombreEstablecimiento,
        b.TipoTrabajo,
        LTRIM(RTRIM(cod.value)) AS CodigoCC,
        LTRIM(RTRIM(nom.value)) AS NombreCC
    FROM base b
    CROSS APPLY STRING_SPLIT(ISNULL(b.CodigosCentroCosto, 'SIN_ASIGNAR'), '/', 1) cod
    CROSS APPLY STRING_SPLIT(ISNULL(b.NombresCentroCosto, 'Sin asignar'),  '/', 1) nom
    WHERE cod.ordinal = nom.ordinal
)
SELECT
    Periodo,
    Empresa,
    CodigoCC,
    NombreCC,
    TipoTrabajo,
    IdEmpleado,
    CUIL,
    NombreEmpleado,
    NombreEstablecimiento
FROM split;
