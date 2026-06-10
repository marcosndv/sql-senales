-- ============================================================================
-- FUNCION: dbo.fn_Sueldos_Nomina_Activa(@Periodo)
-- ----------------------------------------------------------------------------
-- Devuelve los empleados ACTIVOS al cierre del periodo dado, inferido desde
-- recibos (NO desde el maestro oficial del ERP, que no es confiable).
--
-- Criterio "activo al cierre de @Periodo":
--   - El empleado tiene liquidacion MENSUAL (CLASE=3) en @Periodo, Y
--   - No tiene baja inferida en dbo.Sueldos_Bajas con PeriodoBaja <= @Periodo
--
-- Uso:
--   SELECT * FROM dbo.fn_Sueldos_Nomina_Activa('202605');
-- ============================================================================
CREATE OR ALTER FUNCTION dbo.fn_Sueldos_Nomina_Activa(@Periodo CHAR(6))
RETURNS TABLE
AS
RETURN
    -- vw_Sueldos_Nomina trae una fila por contrato. Deduplicamos quedandonos
    -- con el ContratoNro mas alto (el ultimo / vigente) por Empresa+IdEmpleado.
    WITH n_dedup AS (
        SELECT
            n.*,
            ROW_NUMBER() OVER (
                PARTITION BY n.Empresa, n.IdEmpleado
                ORDER BY n.ContratoNro DESC
            ) AS rn
        FROM dbo.vw_Sueldos_Nomina n
    )
    SELECT
        @Periodo AS PeriodoEvaluado,
        n.Empresa,
        n.RazonSocial,
        n.IdEmpleado,
        n.ContratoNro,
        n.CUIL,
        n.NombreEmpleado,
        n.FchNacimiento,
        n.FchAntiguedad,
        n.FchJubilacion,
        n.SexoCod,
        n.EstadoCivilCod,
        n.SindicatoCod,
        n.SindicatoNombre,
        n.ObraSocialCod,
        n.CondicionCod,
        n.ModalidadCod,
        n.BasicoMaestro,
        n.FechaIngreso,
        n.FechaEgreso,
        n.CausaBajaOficial,
        n.Proporcion,
        n.ProporcionSac,
        n.UltimoPuestoCod,
        n.UltimoPuestoNombre,
        n.UltimoEstablecimientoCod,
        n.UltimoPuestoFecha,
        n.UltimoCtroCostoCod,
        n.UltimoCtroCostoNombre,
        n.UltimoCtroCostoFecha,
        n.EstadoLaboral,
        n.DiasContrato
    FROM n_dedup n
    WHERE n.rn = 1
      AND EXISTS (
        SELECT 1
        FROM dbo.vw_Sueldos_LiqDetalladas d
        JOIN dbo.vw_Sueldos_Liquidaciones l
          ON l.CODIGO = d.LIQUIDAC AND l.Empresa = d.Empresa
        WHERE d.Empresa  = n.Empresa
          AND d.EMPLEADO = n.IdEmpleado
          AND l.PERIODO  = @Periodo
          AND l.CLASE    = 3
      )
      AND NOT EXISTS (
        SELECT 1
        FROM dbo.Sueldos_Bajas b
        WHERE b.Empresa    = n.Empresa
          AND b.IdEmpleado = n.IdEmpleado
          AND b.PeriodoBaja <= @Periodo
      );
