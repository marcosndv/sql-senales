-- ============================================================================
-- VISTA: dbo.vw_Sueldos_NominaMensual_Estable
-- ----------------------------------------------------------------------------
-- Dotacion mensual "estable" para el indicador de evolucion de nomina.
-- Una fila = (Empresa, Periodo, IdEmpleado).
--
-- Criterio de inclusion:
--   1) El empleado tiene al menos una liquidacion MENSUAL (CLASE=3) en el periodo.
--   2) NO es alta/baja a prueba de menos de 5 dias en el periodo: se excluye si
--      existe baja inferida en el mismo PeriodoBaja Y la diferencia entre la
--      FechaIngreso oficial del empleado y la FechaCierre de la baja es < 5 dias.
--
-- Para agregados:
--   - Consolidado: COUNT(*) GROUP BY Periodo.
--   - Por sucursal: GROUP BY Periodo, NombreSucursal (toma el establecimiento
--     vigente segun el ultimo dato del maestro -- aproximacion historica).
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Sueldos_NominaMensual_Estable
AS
WITH liq_mes AS (
    -- Toma tambien el CC del recibo (consolidado por STRING_AGG en la vista
    -- de detalle). Si el empleado tiene varios CC en el mes, viene concatenado.
    SELECT
        r.Empresa,
        r.IdEmpleado,
        r.PERIODO AS Periodo,
        MAX(r.CodigosCentroCosto) AS CodigosCentroCosto,
        MAX(r.NombresCentroCosto) AS NombresCentroCosto
    FROM dbo.vw_Sueldos_ReciboDetalle_Normalizado r
    JOIN dbo.vw_Sueldos_Liquidaciones l
      ON l.CODIGO = r.IdLiquidacion AND l.Empresa = r.Empresa
    WHERE l.CLASE = 3
    GROUP BY r.Empresa, r.IdEmpleado, r.PERIODO
),
n_dedup AS (
    -- deduplicar nomina por (Empresa, IdEmpleado) -- usa el ultimo contrato
    SELECT
        n.Empresa, n.IdEmpleado, n.CUIL, n.NombreEmpleado,
        n.FechaIngreso, n.UltimoEstablecimientoCod, n.UltimoPuestoNombre,
        ROW_NUMBER() OVER (PARTITION BY n.Empresa, n.IdEmpleado ORDER BY n.ContratoNro DESC) AS rn
    FROM dbo.vw_Sueldos_Nomina n
),
prueba_corta AS (
    -- bajas donde el empleado estuvo menos de 5 dias en planta
    SELECT
        b.Empresa,
        b.IdEmpleado,
        b.PeriodoBaja
    FROM dbo.Sueldos_Bajas b
    JOIN n_dedup n
      ON n.Empresa = b.Empresa AND n.IdEmpleado = b.IdEmpleado AND n.rn = 1
    WHERE n.FechaIngreso IS NOT NULL
      AND DATEDIFF(DAY, n.FechaIngreso, b.FechaCierre) < 5
)
SELECT
    lm.Empresa,
    lm.Periodo,
    lm.IdEmpleado,
    n.CUIL,
    n.NombreEmpleado,
    n.UltimoEstablecimientoCod AS IdSucursal,
    e.Establecimiento          AS NombreSucursal,
    e.ACTIVIDAD                AS ActividadSucursal,
    lm.CodigosCentroCosto,
    lm.NombresCentroCosto,
    n.UltimoPuestoNombre,
    COALESCE(pt.TipoTrabajo, 'OTROS') AS TipoTrabajo
FROM liq_mes lm
LEFT JOIN n_dedup n
       ON n.Empresa = lm.Empresa AND n.IdEmpleado = lm.IdEmpleado AND n.rn = 1
LEFT JOIN dbo.vw_Sueldos_Establecimientos e
       ON e.Empresa = lm.Empresa AND e.IdEstablecimiento = n.UltimoEstablecimientoCod
LEFT JOIN dbo.vw_Sueldos_Puestos_Tipificados pt
       ON pt.PuestoNombre = n.UltimoPuestoNombre
WHERE NOT EXISTS (
    SELECT 1
    FROM prueba_corta pc
    WHERE pc.Empresa = lm.Empresa
      AND pc.IdEmpleado = lm.IdEmpleado
      AND pc.PeriodoBaja = lm.Periodo
);
