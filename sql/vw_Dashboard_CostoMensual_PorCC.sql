-- ============================================================================
-- VISTA: dbo.vw_Dashboard_CostoMensual_PorCC
-- ----------------------------------------------------------------------------
-- Costo Empresa por CC para dashboard, una fila por (Periodo, Empresa,
-- IdEmpleado, CodigoCC, NombreCC, Categoria).
--
-- Fuente: vw_Sueldos_CostoLaboralDetalle (en vivo). Esta vista usa SICOSS
-- prorrateado para contribuciones patronales y tiene cobertura completa de
-- todos los meses (incl. 202601/202602 que ContribucionesXEmpleado no cubre).
--
-- Categorias:
--   BRUTO_REMUNERATIVO     -- incluye sueldo basico, variables remunerativas, SAC
--   BRUTO_NO_REMUNERATIVO  -- sumas no remunerativas (paritarias, viaticos)
--   CONTRIBUCION_PATRONAL  -- SS+OS+RENATRE+ART+SCVO (SICOSS) + sindical (UTHGRA)
--
-- Liquidaciones finales (CLASE=5) van EN LAS MISMAS FILAS de Bruto y Contrib,
-- no se separan. CostoLaboralDetalle no tiene una columna que las distinga
-- por concepto -- si se necesita filtrarlas, hacerlo via IdLiquidacion + CLASE.
--
-- Split de CC: una persona con multiples CC en el mes cuenta con monto/N por
-- cada CC. Hoy en 2026 no hay multi-CC asi que el split es defensivo.
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Dashboard_CostoMensual_PorCC AS
WITH base AS (
    SELECT
        c.Empresa,
        c.PERIODO                AS Periodo,
        c.IdEmpleado,
        c.CUIL,
        c.NombreEmpleado,
        c.IdLiquidacion,
        c.CodigosCentroCosto,
        c.NombresCentroCosto,
        c.TotalBrutoRemunerativo,
        c.TotalBrutoNoRemunerativo,
        c.TotalContribucionesEmpleador,
        (LEN(ISNULL(c.CodigosCentroCosto, 'X')) -
         LEN(REPLACE(ISNULL(c.CodigosCentroCosto, 'X'), '/', '')) + 1) AS CantCC
    FROM dbo.vw_Sueldos_CostoLaboralDetalle c
),
split AS (
    SELECT
        b.Empresa,
        b.Periodo,
        b.IdEmpleado,
        b.CUIL,
        b.NombreEmpleado,
        b.IdLiquidacion,
        LTRIM(RTRIM(cod.value)) AS CodigoCC,
        LTRIM(RTRIM(nom.value)) AS NombreCC,
        b.TotalBrutoRemunerativo       / NULLIF(b.CantCC, 0) AS BrutoRem,
        b.TotalBrutoNoRemunerativo     / NULLIF(b.CantCC, 0) AS BrutoNoRem,
        b.TotalContribucionesEmpleador / NULLIF(b.CantCC, 0) AS Contrib
    FROM base b
    CROSS APPLY STRING_SPLIT(ISNULL(b.CodigosCentroCosto, 'SIN_ASIGNAR'), '/', 1) cod
    CROSS APPLY STRING_SPLIT(ISNULL(b.NombresCentroCosto, 'Sin asignar'),  '/', 1) nom
    WHERE cod.ordinal = nom.ordinal
),
unpiv AS (
    SELECT Empresa, Periodo, IdEmpleado, CUIL, NombreEmpleado, IdLiquidacion,
           CodigoCC, NombreCC,
           CAST('BRUTO_REMUNERATIVO' AS VARCHAR(30))    AS Categoria,
           BrutoRem AS CostoTotal
    FROM split WHERE BrutoRem <> 0
    UNION ALL
    SELECT Empresa, Periodo, IdEmpleado, CUIL, NombreEmpleado, IdLiquidacion,
           CodigoCC, NombreCC,
           CAST('BRUTO_NO_REMUNERATIVO' AS VARCHAR(30)) AS Categoria,
           BrutoNoRem
    FROM split WHERE BrutoNoRem <> 0
    UNION ALL
    SELECT Empresa, Periodo, IdEmpleado, CUIL, NombreEmpleado, IdLiquidacion,
           CodigoCC, NombreCC,
           CAST('CONTRIBUCION_PATRONAL' AS VARCHAR(30)) AS Categoria,
           Contrib
    FROM split WHERE Contrib <> 0
)
SELECT
    u.Periodo,
    u.Empresa,
    u.CodigoCC,
    u.NombreCC,
    u.Categoria,
    COALESCE(pt.TipoTrabajo, 'OTROS') AS TipoTrabajo,
    u.IdEmpleado,
    u.CUIL,
    u.NombreEmpleado,
    est.Establecimiento AS NombreEstablecimiento,
    u.CostoTotal
FROM unpiv u
LEFT JOIN (
    SELECT n.Empresa, n.IdEmpleado, n.UltimoPuestoNombre, n.UltimoEstablecimientoCod,
           ROW_NUMBER() OVER (PARTITION BY n.Empresa, n.IdEmpleado ORDER BY n.ContratoNro DESC) AS rn
    FROM dbo.vw_Sueldos_Nomina n
) nd ON nd.Empresa = u.Empresa AND nd.IdEmpleado = u.IdEmpleado AND nd.rn = 1
LEFT JOIN dbo.vw_Sueldos_Establecimientos est
       ON est.Empresa = u.Empresa AND est.IdEstablecimiento = nd.UltimoEstablecimientoCod
LEFT JOIN dbo.vw_Sueldos_Puestos_Tipificados pt
       ON pt.PuestoNombre = nd.UltimoPuestoNombre;
