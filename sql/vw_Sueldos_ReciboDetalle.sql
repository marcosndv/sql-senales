-- ============================================================================
-- VISTA: dbo.vw_Sueldos_ReciboDetalle
-- ----------------------------------------------------------------------------
-- Cada fila = un concepto de un empleado en una liquidacion.
-- CC = asignado en el momento (fin del periodo de la liquidacion). Inmune a
--      reasignaciones posteriores — apto para comparaciones historicas.
--
-- Logica de CC al momento:
--   1) Para cada (empresa, empleado, periodo) que aparece en alguna liquidacion,
--      buscamos la fecha de asignacion MAX que sea <= fin del periodo (EOMONTH).
--   2) Recuperamos los CTROCOSTO vigentes en esa fecha-snapshot.
--   3) STRING_AGG por si hay multiples CC simultaneos.
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Sueldos_ReciboDetalle AS
WITH

-- (Empresa, EMPLEADO, PERIODO) que realmente tienen liquidacion (filtra el universo)
EmpleadoXPeriodo AS (
    SELECT DISTINCT
        liq.Empresa,
        det.EMPLEADO,
        liq.PERIODO
    FROM dbo.vw_Sueldos_LiqDetalladas det
    INNER JOIN dbo.vw_Sueldos_Liquidaciones liq
        ON  liq.CODIGO  = det.LIQUIDAC
        AND liq.Empresa = det.Empresa
),

-- Fecha snapshot por periodo = ultimo dia del mes (independiente de cuando se cerro la liq)
CC_FechaSnapshot AS (
    SELECT
        elp.Empresa,
        elp.EMPLEADO,
        elp.PERIODO,
        MAX(cc.FECHA) AS FechaSnapshot
    FROM EmpleadoXPeriodo elp
    INNER JOIN dbo.vw_Sueldos_EmpleadosXCentroCosto cc
        ON  cc.Empresa  = elp.Empresa
        AND cc.EMPLEADO = elp.EMPLEADO
        AND cc.FECHA   <= EOMONTH(DATEFROMPARTS(
                            CAST(LEFT(elp.PERIODO, 4) AS INT),
                            CAST(RIGHT(elp.PERIODO, 2) AS INT),
                            1))
    GROUP BY elp.Empresa, elp.EMPLEADO, elp.PERIODO
),

-- CC vigentes en la fecha-snapshot (deduplica + join al catalogo + STRING_AGG)
CC_AlMomento AS (
    SELECT
        sel.Empresa,
        sel.EMPLEADO,
        sel.PERIODO,
        STRING_AGG(CAST(cat.CODIGO AS NVARCHAR(20)), ' / ')
            WITHIN GROUP (ORDER BY cat.CODIGO) AS CodigosCentroCosto,
        STRING_AGG(cat.NOMBRE, ' / ')
            WITHIN GROUP (ORDER BY cat.CODIGO) AS NombresCentroCosto
    FROM (
        SELECT DISTINCT
            cc.Empresa,
            cc.EMPLEADO,
            fs.PERIODO,
            cc.CTROCOSTO
        FROM dbo.vw_Sueldos_EmpleadosXCentroCosto cc
        INNER JOIN CC_FechaSnapshot fs
            ON  fs.Empresa       = cc.Empresa
            AND fs.EMPLEADO      = cc.EMPLEADO
            AND cc.FECHA         = fs.FechaSnapshot
    ) sel
    INNER JOIN dbo.vw_Sueldos_CentrosCostos cat
        ON  cat.CODIGO  = sel.CTROCOSTO
        AND cat.Empresa = sel.Empresa
    GROUP BY sel.Empresa, sel.EMPLEADO, sel.PERIODO
)

SELECT
    -- Identificacion
    liq.Empresa,
    COALESCE(ce.NombreEmpresa, liq.Empresa) AS RazonSocial,
    liq.PERIODO,
    LEFT(liq.PERIODO, 4)            AS Anio,
    RIGHT(liq.PERIODO, 2)           AS Mes,
    CASE liq.CLASE
        WHEN 1 THEN '1ra Quincena'
        WHEN 2 THEN '2da Quincena'
        WHEN 3 THEN 'Mensual'
        WHEN 4 THEN 'Especial/SAC'
        ELSE 'Clase ' + CAST(liq.CLASE AS VARCHAR)
    END                             AS TipoLiquidacion,
    liq.CLASE                       AS ClaseLiquidacion,
    liq.CODIGO                      AS IdLiquidacion,
    liq.CIERRE                      AS FechaCierre,
    liq.FECHAPAGO                   AS FechaPago,
    liq.CERRADA,

    -- Empleado
    emp.CODIGO                      AS IdEmpleado,
    emp.NOMBRE                      AS NombreEmpleado,
    emp.CUIL,
    emp.CONDICION,
    emp.SINDICATO,
    emp.OBRASOCIAL,

    -- Centro de costo (al momento de la liquidacion)
    COALESCE(cc.CodigosCentroCosto, 'Sin asignar') AS CodigosCentroCosto,
    COALESCE(cc.NombresCentroCosto, 'Sin asignar') AS NombresCentroCosto,

    -- Concepto
    con.CODIGO                      AS IdConcepto,
    con.NOMBRE                      AS NombreConcepto,
    con.CLASE1                      AS ClaseConcepto,
    con.CLASE2,
    con.CLASE3,
    con.CODIGOAFIP,
    con.REMUNERA1                   AS EsRemunerativo,

    -- Valores del concepto
    det.CANTIDAD,
    det.VUNITARIO,
    det.VALORTOTAL

FROM dbo.vw_Sueldos_LiqDetalladas det
INNER JOIN dbo.vw_Sueldos_Liquidaciones liq
    ON  det.LIQUIDAC = liq.CODIGO
    AND det.Empresa  = liq.Empresa
INNER JOIN dbo.vw_Sueldos_Empleados emp
    ON  det.EMPLEADO = emp.CODIGO
    AND det.Empresa  = emp.Empresa
INNER JOIN dbo.vw_Sueldos_Conceptos con
    ON  det.CONCEPTO = con.CODIGO
    AND det.Empresa  = con.Empresa
LEFT JOIN dbo.Config_Empresas_Sueldos ce
    ON  ce.Empresa = liq.Empresa
LEFT JOIN CC_AlMomento cc
    ON  cc.Empresa  = emp.Empresa
    AND cc.EMPLEADO = emp.CODIGO
    AND cc.PERIODO  = liq.PERIODO;
