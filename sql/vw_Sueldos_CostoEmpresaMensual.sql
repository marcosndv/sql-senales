-- ============================================================================
-- VISTA: dbo.vw_Sueldos_CostoEmpresaMensual
-- ----------------------------------------------------------------------------
-- Costo Empresa "recurrente" mes a mes. Una fila = (Empresa, Periodo, Empleado,
-- Categoria, IdSucursal, TipoTrabajo) con CostoTotal.
--
-- Componentes que SUMAN al costo empresa:
--   HABER_REMUN           -- sueldos basicos + variables remunerativas
--   SAC                   -- aguinaldo (proporcional + jul/dic)
--   NO_REMUN              -- sumas no remunerativas (paritarias, viaticos, etc.)
--   CONTRIBUCION_PATRONAL -- contribuciones patronales (jub, OS, ART, sind. patronal)
--                            desde dbo.vw_Sueldos_ContribucionesXEmpleado.
--                            NOTA: solo disponible desde 202603 en adelante en
--                            la base actual. Los meses anteriores quedan subestimados.
--
-- NO suman al costo empresa (deliberadamente excluidos):
--   APORTE         -- descuento al empleado (jub 11%, OS, sindical) -- no es costo extra
--   RETENCION      -- ganancias y similares al empleado
--   AJUSTE/ANTICIPO -- ajustes contables internos
--
-- EXCLUSIONES (criterio "recurrente"):
--   1) Categoria = 'LIQUIDACION_FINAL'    -- indemniz, preaviso, integracion,
--                                            VNG, SACs VNG
--   2) NombreNormalizado = 'Acuerdo No Remunerativo' AND el empleado tiene
--      baja inferida con PeriodoBaja <= Periodo del recibo. Heuristica para
--      separar cuotas de acuerdo de despido (excluir) de acuerdos paritarios
--      recurrentes (incluir).
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Sueldos_CostoEmpresaMensual
AS
WITH n_dedup AS (
    SELECT
        n.Empresa, n.IdEmpleado, n.UltimoEstablecimientoCod, n.UltimoPuestoNombre,
        ROW_NUMBER() OVER (PARTITION BY n.Empresa, n.IdEmpleado ORDER BY n.ContratoNro DESC) AS rn
    FROM dbo.vw_Sueldos_Nomina n
),
recibo AS (
    SELECT
        r.Empresa,
        r.PERIODO   AS Periodo,
        r.IdEmpleado,
        r.NombreEmpleado,
        r.CUIL,
        r.CodigosCentroCosto,
        r.NombresCentroCosto,
        r.Categoria,
        r.NombreNormalizado,
        r.VALORTOTAL AS CostoTotal
    FROM dbo.vw_Sueldos_ReciboDetalle_Normalizado r
    WHERE r.Categoria IN ('HABER_REMUN', 'SAC', 'NO_REMUN')
      AND NOT (
          r.NombreNormalizado = 'Acuerdo No Remunerativo'
          AND EXISTS (
              SELECT 1 FROM dbo.Sueldos_Bajas b
              WHERE b.Empresa = r.Empresa
                AND b.IdEmpleado = r.IdEmpleado
                AND b.PeriodoBaja <= r.PERIODO
          )
      )
),
contrib AS (
    -- Las contribuciones se imputan en el PeriodoEconomico de la liquidacion
    -- (parseado del COMENTARIO o heuristica CLASE=5).
    -- Se EXCLUYEN las contribuciones de liquidaciones CLASE=5 (finales) porque
    -- corresponden a indemnizaciones/preaviso/integracion -- no son costo
    -- recurrente. Las contribuciones de la mensual + ajustes + SAC si entran.
    SELECT
        c.Empresa,
        COALESCE(me.PeriodoEconomico, c.PERIODO) AS Periodo,
        c.IdEmpleado,
        CAST(NULL AS NVARCHAR(100))      AS NombreEmpleado,
        CAST(NULL AS NVARCHAR(11))       AS CUIL,
        -- las contribuciones no tienen CC propio -- se asume el CC del recibo
        -- correspondiente (toma el primer CC observado para ese empleado en el
        -- periodo). Si la persona tiene 1 solo CC, exacto.
        (SELECT TOP 1 r2.CodigosCentroCosto
         FROM dbo.vw_Sueldos_ReciboDetalle_Normalizado r2
         WHERE r2.Empresa=c.Empresa AND r2.IdEmpleado=c.IdEmpleado
           AND r2.PERIODO=COALESCE(me.PeriodoEconomico, c.PERIODO)
         ORDER BY r2.CodigosCentroCosto)        AS CodigosCentroCosto,
        (SELECT TOP 1 r2.NombresCentroCosto
         FROM dbo.vw_Sueldos_ReciboDetalle_Normalizado r2
         WHERE r2.Empresa=c.Empresa AND r2.IdEmpleado=c.IdEmpleado
           AND r2.PERIODO=COALESCE(me.PeriodoEconomico, c.PERIODO)
         ORDER BY r2.CodigosCentroCosto)        AS NombresCentroCosto,
        CAST('CONTRIBUCION_PATRONAL' AS VARCHAR(30)) AS Categoria,
        CAST(NULL AS NVARCHAR(100))      AS NombreNormalizado,
        c.MONTOCONTR                     AS CostoTotal
    FROM dbo.vw_Sueldos_ContribucionesXEmpleado c
    LEFT JOIN dbo.vw_Sueldos_Liquidaciones_MesEconomico me
           ON me.Empresa = c.Empresa AND me.IdLiquidacion = c.IdLiquidacion
    WHERE COALESCE(me.CLASE, 3) <> 5     -- excluye contribs de liqs finales
),
todo AS (
    SELECT * FROM recibo
    UNION ALL
    SELECT * FROM contrib
)
SELECT
    t.Empresa,
    t.Periodo,
    t.IdEmpleado,
    t.NombreEmpleado,
    t.CUIL,
    t.CodigosCentroCosto,
    t.NombresCentroCosto,
    t.Categoria,
    t.NombreNormalizado,
    n.UltimoEstablecimientoCod AS IdSucursal,
    e.Establecimiento          AS NombreSucursal,
    e.ACTIVIDAD                AS ActividadSucursal,
    n.UltimoPuestoNombre,
    COALESCE(pt.TipoTrabajo, 'OTROS') AS TipoTrabajo,
    t.CostoTotal
FROM todo t
LEFT JOIN n_dedup n
       ON n.Empresa = t.Empresa AND n.IdEmpleado = t.IdEmpleado AND n.rn = 1
LEFT JOIN dbo.vw_Sueldos_Establecimientos e
       ON e.Empresa = t.Empresa AND e.IdEstablecimiento = n.UltimoEstablecimientoCod
LEFT JOIN dbo.vw_Sueldos_Puestos_Tipificados pt
       ON pt.PuestoNombre = n.UltimoPuestoNombre;
