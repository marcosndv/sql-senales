-- ============================================================================
-- VISTA: dbo.vw_Sueldos_CostoLaboralDetalle
-- ----------------------------------------------------------------------------
-- Una fila = un empleado en una liquidacion.
-- CC = asignado en el momento (fin del periodo de la liquidacion). Inmune a
--      reasignaciones posteriores — apto para comparaciones historicas / dashboard.
--
-- Logica de CC al momento:
--   1) Para cada (empresa, empleado, periodo) con liquidacion, fecha snapshot
--      = MAX(FECHA) de asignacion CC <= ultimo dia del mes del periodo.
--   2) Recuperamos los CTROCOSTO vigentes en esa fecha-snapshot.
--   3) STRING_AGG por si hay multiples CC simultaneos.
--
-- CONTRIBUCIONES DEL EMPLEADOR (sin cambios respecto a version previa):
--   ContribucionesSICOSS:
--     De DECLARACIONSICOSS, prorrateadas por BrutoRem del empleado / TotalBrutoRem
--     de la empresa en el periodo.
--   ContribucionesSindicales:
--     De COSTOSINDICAL, distribuidas igualitariamente entre empleados del
--     sindicato en el periodo.
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Sueldos_CostoLaboralDetalle AS
WITH

-- ------------------------------------------------------------------
-- 1. CC al momento de la liquidacion (snapshot por periodo)
-- ------------------------------------------------------------------
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
            ON  fs.Empresa  = cc.Empresa
            AND fs.EMPLEADO = cc.EMPLEADO
            AND cc.FECHA    = fs.FechaSnapshot
    ) sel
    INNER JOIN dbo.vw_Sueldos_CentrosCostos cat
        ON  cat.CODIGO  = sel.CTROCOSTO
        AND cat.Empresa = sel.Empresa
    GROUP BY sel.Empresa, sel.EMPLEADO, sel.PERIODO
),

-- ------------------------------------------------------------------
-- 2. Ultimo puesto asignado
-- ------------------------------------------------------------------
UltimoPuesto AS (
    SELECT
        Empresa, EMPLEADO, PUESTO,
        ROW_NUMBER() OVER (
            PARTITION BY Empresa, EMPLEADO
            ORDER BY FECHA DESC
        ) AS rn
    FROM dbo.vw_Sueldos_EmpleadosXPuesto
),

-- ------------------------------------------------------------------
-- 3. Contrato vigente
-- ------------------------------------------------------------------
ContratoActivo AS (
    SELECT
        Empresa, EMPLEADO, CONTRATO,
        ROW_NUMBER() OVER (
            PARTITION BY Empresa, EMPLEADO
            ORDER BY INGRESO DESC
        ) AS rn
    FROM dbo.vw_Sueldos_ContratosXEmpleado
    WHERE EGRESO IS NULL
       OR EGRESO >= CAST(GETDATE() AS DATE)
),

-- ------------------------------------------------------------------
-- 4. Brutos por empleado/liquidacion
-- ------------------------------------------------------------------
TotalesEmpleado AS (
    SELECT
        det.Empresa,
        det.LIQUIDAC,
        det.EMPLEADO,
        liq.PERIODO,
        SUM(CASE
                WHEN con.CLASE1 IN (1, 2) AND det.VALORTOTAL > 0
                THEN det.VALORTOTAL ELSE 0
            END) AS BrutoRemunerativo,
        SUM(CASE
                WHEN con.CLASE1 = 4 AND det.VALORTOTAL > 0
                THEN det.VALORTOTAL ELSE 0
            END) AS BrutoNoRemunerativo
    FROM dbo.vw_Sueldos_LiqDetalladas det
    INNER JOIN dbo.vw_Sueldos_Liquidaciones liq
        ON  liq.CODIGO  = det.LIQUIDAC
        AND liq.Empresa = det.Empresa
    INNER JOIN dbo.vw_Sueldos_Conceptos con
        ON  con.CODIGO  = det.CONCEPTO
        AND con.Empresa = det.Empresa
    GROUP BY det.Empresa, det.LIQUIDAC, det.EMPLEADO, liq.PERIODO
),

-- ------------------------------------------------------------------
-- 5. Total BrutoRemunerativo de la empresa por PERIODO
-- ------------------------------------------------------------------
TotalBrutoEmpresaPeriodo AS (
    SELECT
        Empresa,
        PERIODO,
        SUM(BrutoRemunerativo) AS TotalBrutoRemEmpresa
    FROM TotalesEmpleado
    GROUP BY Empresa, PERIODO
),

-- ------------------------------------------------------------------
-- 6. Contribuciones SICOSS del empleador por empresa/periodo
-- ------------------------------------------------------------------
ContribSICOSSEmpresa AS (
    SELECT
        Empresa,
        PERIODO,
        SUM(
            ISNULL(SS_CONTRIB, 0) +
            ISNULL(OS_CONTRIB, 0) +
            ISNULL(RENATRE_CO, 0) +
            ISNULL(LRT_APAGAR, 0) +
            ISNULL(SCVO_APAG,  0)
        ) AS TotalContribSICOSS
    FROM dbo.vw_Sueldos_DeclaracionSICOSS
    GROUP BY Empresa, PERIODO
),

-- ------------------------------------------------------------------
-- 7. Contribucion sindical del empleador por cabeza
-- ------------------------------------------------------------------
ContribSindicalPorEmpleado AS (
    SELECT
        Empresa,
        PERIODO,
        SINDICATO,
        CASE
            WHEN SUM(EMPLEADOS) > 0
            THEN SUM(TOTAL) / SUM(EMPLEADOS)
            ELSE 0
        END AS ContribSindicalPorCabeza
    FROM dbo.vw_Sueldos_CostosIndical
    GROUP BY Empresa, PERIODO, SINDICATO
),

-- ------------------------------------------------------------------
-- 8. Empleados por liquidacion derivado de LIQUIDACIONESDETALLADAS
-- ------------------------------------------------------------------
EmpleadosXLiq AS (
    SELECT DISTINCT Empresa, LIQUIDAC, EMPLEADO
    FROM dbo.vw_Sueldos_LiqDetalladas
),

-- ------------------------------------------------------------------
-- 9. Bajas inferidas por (Empresa, CUIL, PeriodoBaja).
--    Match por CUIL (no por IdEmpleado) y por PeriodoBaja = PERIODO de la
--    liquidacion. Marca tanto la mensual como la liq final del mes de baja.
-- ------------------------------------------------------------------
BajasIndex AS (
    SELECT
        Empresa,
        CUIL,
        PeriodoBaja,
        MotivoBaja,
        FechaCierre              AS FechaBaja,
        TotalLiquidacionFinal
    FROM dbo.Sueldos_Bajas
),

-- ------------------------------------------------------------------
-- 10. Altas inferidas por (Empresa, CUIL, PeriodoAlta).
--     Mismo patron que bajas: TipoAlta = ALTA_NUEVA / REINGRESO,
--     GapMeses = meses sin liquidacion previa (0 = sin gap).
-- ------------------------------------------------------------------
AltasIndex AS (
    SELECT
        Empresa,
        CUIL,
        PeriodoAlta,
        TipoAlta,
        GapMeses,
        PeriodoPrevio
    FROM dbo.Sueldos_Altas
)

-- ------------------------------------------------------------------
-- Query principal
-- ------------------------------------------------------------------
SELECT
    -- === EMPRESA ===
    emp.Empresa,
    COALESCE(ce.NombreEmpresa, emp.Empresa)             AS RazonSocial,

    -- === PERIODO ===
    liq.PERIODO,
    LEFT(liq.PERIODO, 4)                                AS Anio,
    RIGHT(liq.PERIODO, 2)                               AS Mes,
    CASE liq.CLASE
        WHEN 1 THEN '1ra Quincena'
        WHEN 2 THEN '2da Quincena'
        WHEN 3 THEN 'Mensual'
        WHEN 4 THEN 'Especial / SAC'
        ELSE        'Clase ' + CAST(liq.CLASE AS VARCHAR)
    END                                                 AS TipoLiquidacion,
    liq.CIERRE                                          AS FechaCierre,
    liq.CODIGO                                          AS IdLiquidacion,

    -- === CENTRO DE COSTO (al momento de la liquidacion) ===
    COALESCE(ccv.CodigosCentroCosto, 'Sin asignar')     AS CodigosCentroCosto,
    COALESCE(ccv.NombresCentroCosto, 'Sin asignar')     AS NombresCentroCosto,

    -- === PUESTO ===
    CAST(pue.CODIGO AS NVARCHAR(20))                    AS CodigoPuesto,
    pue.NOMBRE                                          AS NombrePuesto,

    -- === EMPLEADO ===
    emp.CUIL,
    CASE emp.SEXO
        WHEN 1 THEN 'Masculino'
        WHEN 2 THEN 'Femenino'
        ELSE        'No especificado'
    END                                                 AS Genero,
    emp.NOMBRE                                          AS NombreEmpleado,

    -- === CONTRATO ===
    ca.CONTRATO                                         AS CodContrato,
    COALESCE(
        tc.NombreContrato,
        'Codigo ' + CAST(ISNULL(ca.CONTRATO, 0) AS VARCHAR)
    )                                                   AS NombreContrato,

    -- === SINDICATO ===
    emp.SINDICATO                                       AS CodigoSindicato,
    COALESCE(
        sind.NombreSindicato,
        'Sindicato ' + CAST(ISNULL(emp.SINDICATO, 0) AS VARCHAR)
    )                                                   AS NombreSindicato,

    -- === FECHA ANTIGUEDAD ===
    emp.FCHANTIG                                        AS FechaInicioLaboral,

    -- === BRUTOS ===
    ISNULL(te.BrutoRemunerativo,   0)                   AS TotalBrutoRemunerativo,
    ISNULL(te.BrutoNoRemunerativo, 0)                   AS TotalBrutoNoRemunerativo,

    -- === CONTRIBUCIONES DEL EMPLEADOR ===

    -- SICOSS: prorrateo proporcional por BrutoRemunerativo del empleado
    ROUND(
        CASE
            WHEN ISNULL(tbe.TotalBrutoRemEmpresa, 0) > 0
            THEN ISNULL(te.BrutoRemunerativo, 0)
                 / tbe.TotalBrutoRemEmpresa
                 * ISNULL(css.TotalContribSICOSS, 0)
            ELSE 0
        END, 2
    )                                                   AS ContribucionesSICOSS,

    -- Sindicales: distribucion igualitaria
    ROUND(ISNULL(csind.ContribSindicalPorCabeza, 0), 2) AS ContribucionesSindicales,

    -- Total contribuciones empleador
    ROUND(
        CASE
            WHEN ISNULL(tbe.TotalBrutoRemEmpresa, 0) > 0
            THEN ISNULL(te.BrutoRemunerativo, 0)
                 / tbe.TotalBrutoRemEmpresa
                 * ISNULL(css.TotalContribSICOSS, 0)
            ELSE 0
        END
        + ISNULL(csind.ContribSindicalPorCabeza, 0), 2
    )                                                   AS TotalContribucionesEmpleador,

    -- === COSTO LABORAL TOTAL ===
    ROUND(
        ISNULL(te.BrutoRemunerativo,   0)
        + ISNULL(te.BrutoNoRemunerativo, 0)
        + CASE
            WHEN ISNULL(tbe.TotalBrutoRemEmpresa, 0) > 0
            THEN ISNULL(te.BrutoRemunerativo, 0)
                 / tbe.TotalBrutoRemEmpresa
                 * ISNULL(css.TotalContribSICOSS, 0)
            ELSE 0
          END
        + ISNULL(csind.ContribSindicalPorCabeza, 0), 2
    )                                                   AS TotalCostoLaboral,

    -- === BAJA DEL PERIODO ===
    CAST(CASE WHEN bx.CUIL IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS EsBaja,
    bx.MotivoBaja                                       AS MotivoBaja,
    bx.FechaBaja                                        AS FechaBaja,
    bx.TotalLiquidacionFinal                            AS TotalLiquidacionFinal,

    -- === ALTA DEL PERIODO ===
    CAST(CASE WHEN ax.CUIL IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS EsAlta,
    ax.TipoAlta                                         AS TipoAlta,
    ax.GapMeses                                         AS GapMeses,
    ax.PeriodoPrevio                                    AS PeriodoPrevio,

    -- === IDs ===
    emp.CODIGO                                          AS IdEmpleado

FROM EmpleadosXLiq exl
INNER JOIN dbo.vw_Sueldos_Empleados emp
    ON  emp.CODIGO  = exl.EMPLEADO
    AND emp.Empresa = exl.Empresa
INNER JOIN dbo.vw_Sueldos_Liquidaciones liq
    ON  liq.CODIGO  = exl.LIQUIDAC
    AND liq.Empresa = exl.Empresa

-- Brutos del empleado en esta liquidacion
LEFT JOIN TotalesEmpleado te
    ON  te.EMPLEADO = emp.CODIGO
    AND te.LIQUIDAC = exl.LIQUIDAC
    AND te.Empresa  = emp.Empresa

-- Total bruto empresa/periodo (base prorrateo)
LEFT JOIN TotalBrutoEmpresaPeriodo tbe
    ON  tbe.Empresa = emp.Empresa
    AND tbe.PERIODO = liq.PERIODO

-- Contribuciones SICOSS empresa/periodo
LEFT JOIN ContribSICOSSEmpresa css
    ON  css.Empresa = emp.Empresa
    AND css.PERIODO = liq.PERIODO

-- Contribucion sindical por cabeza
LEFT JOIN ContribSindicalPorEmpleado csind
    ON  csind.Empresa   = emp.Empresa
    AND csind.PERIODO   = liq.PERIODO
    AND csind.SINDICATO = emp.SINDICATO

-- Centros de costo al momento (snapshot por periodo)
LEFT JOIN CC_AlMomento ccv
    ON  ccv.Empresa  = emp.Empresa
    AND ccv.EMPLEADO = emp.CODIGO
    AND ccv.PERIODO  = liq.PERIODO

-- Puesto actual
LEFT JOIN UltimoPuesto xp
    ON  xp.EMPLEADO = emp.CODIGO
    AND xp.Empresa  = emp.Empresa
    AND xp.rn       = 1
LEFT JOIN dbo.vw_Sueldos_Puestos pue
    ON  pue.CODIGO  = xp.PUESTO
    AND pue.Empresa = xp.Empresa

-- Contrato vigente
LEFT JOIN ContratoActivo ca
    ON  ca.EMPLEADO = emp.CODIGO
    AND ca.Empresa  = emp.Empresa
    AND ca.rn       = 1
LEFT JOIN dbo.Config_TiposContrato tc
    ON  tc.CodContrato = ca.CONTRATO

-- Sindicato
LEFT JOIN dbo.Config_Sindicatos sind
    ON  sind.Empresa         = emp.Empresa
    AND sind.CodigoSindicato = emp.SINDICATO

-- Razon social
LEFT JOIN dbo.Config_Empresas_Sueldos ce
    ON  ce.Empresa = emp.Empresa

-- Baja del periodo (match por Empresa + CUIL + PeriodoBaja = PERIODO)
LEFT JOIN BajasIndex bx
    ON  bx.Empresa     = emp.Empresa
    AND bx.CUIL        = emp.CUIL
    AND bx.PeriodoBaja = liq.PERIODO

-- Alta del periodo (match por Empresa + CUIL + PeriodoAlta = PERIODO)
LEFT JOIN AltasIndex ax
    ON  ax.Empresa     = emp.Empresa
    AND ax.CUIL        = emp.CUIL
    AND ax.PeriodoAlta = liq.PERIODO;
