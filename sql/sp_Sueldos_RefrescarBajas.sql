-- =============================================================================
-- sp_Sueldos_RefrescarBajas
--
-- Detecta bajas inferidas en dbo.vw_Sueldos_ReciboDetalle_Normalizado
-- (Categoria='LIQUIDACION_FINAL' con SUM(VALORTOTAL) > 0 por liquidacion)
-- y las inserta en dbo.Sueldos_Bajas si el empleado todavia no figura ahi.
--
-- Idempotente:
--   - NUNCA actualiza una baja ya existente.
--   - NUNCA inserta un duplicado (Empresa, IdEmpleado).
--
-- Criterio (mismo que la carga original):
--   Una baja por (Empresa, IdEmpleado): la liq final mas reciente segun
--   PeriodoEconomico (parseado del COMENTARIO), desempate por IdLiquidacion DESC.
--   Reingresos con dos liq finales en el rango quedan registrados con la baja
--   posterior; la anterior NO se carga.
--
-- MotivoBaja por prioridad:
--   FALLECIMIENTO  -> existe "Indemnizacion Fallecimiento" > 0
--   FUERZA_MAYOR   -> existe Art 248 > 0
--   DESPIDO_SIN_CAUSA -> existe Art 245 o Art 247 > 0
--   RENUNCIA_O_MUTUO  -> caso por defecto
--
-- Parametros:
--   @PeriodoDesde NVARCHAR(6) -- PeriodoEconomico minimo (default: enero año actual)
--   @PeriodoHasta NVARCHAR(6) -- PeriodoEconomico maximo (default: diciembre año actual)
--   @SoloMostrarPreview BIT   -- 1 = no inserta, devuelve preview con Estado (NUEVA/EXISTE)
-- =============================================================================

CREATE OR ALTER PROCEDURE dbo.sp_Sueldos_RefrescarBajas
    @PeriodoDesde NVARCHAR(6) = NULL,
    @PeriodoHasta NVARCHAR(6) = NULL,
    @SoloMostrarPreview BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @anioActual NVARCHAR(4) = CAST(YEAR(SYSDATETIME()) AS NVARCHAR(4));
    IF @PeriodoDesde IS NULL SET @PeriodoDesde = @anioActual + '01';
    IF @PeriodoHasta IS NULL SET @PeriodoHasta = @anioActual + '12';

    ;WITH liq_finales AS (
        SELECT
            n.Empresa,
            n.IdEmpleado,
            n.IdLiquidacion,
            m.PeriodoEconomico,
            m.PeriodoAdmin
        FROM dbo.vw_Sueldos_ReciboDetalle_Normalizado n
        JOIN dbo.vw_Sueldos_Liquidaciones_MesEconomico m
            ON n.Empresa = m.Empresa AND n.IdLiquidacion = m.IdLiquidacion
        WHERE n.Categoria = 'LIQUIDACION_FINAL'
          AND m.PeriodoEconomico BETWEEN @PeriodoDesde AND @PeriodoHasta
        GROUP BY n.Empresa, n.IdEmpleado, n.IdLiquidacion, m.PeriodoEconomico, m.PeriodoAdmin
        HAVING SUM(n.VALORTOTAL) > 0
    ),
    ranked AS (
        SELECT
            lf.*,
            ROW_NUMBER() OVER (
                PARTITION BY lf.Empresa, lf.IdEmpleado
                ORDER BY lf.PeriodoEconomico DESC, lf.IdLiquidacion DESC
            ) AS rn
        FROM liq_finales lf
    ),
    elegidas AS (
        SELECT Empresa, IdEmpleado, IdLiquidacion, PeriodoEconomico, PeriodoAdmin
        FROM ranked
        WHERE rn = 1
    ),
    agg AS (
        SELECT
            n.Empresa,
            n.IdEmpleado,
            n.IdLiquidacion,
            MAX(n.NombreEmpleado) AS NombreEmpleado,
            MAX(n.CUIL) AS CUIL,
            MAX(n.TipoLiquidacion) AS TipoLiquidacion,
            MAX(CAST(n.FechaCierre AS DATE)) AS FechaCierre,
            MAX(CAST(n.FechaPago AS DATE)) AS FechaPago,
            SUM(CASE WHEN n.NombreNormalizado = 'Indemnizacion Art 245 LCT'          THEN n.VALORTOTAL ELSE 0 END) AS MontoArt245,
            SUM(CASE WHEN n.NombreNormalizado = 'Indemnizacion Art 247'              THEN n.VALORTOTAL ELSE 0 END) AS MontoArt247,
            SUM(CASE WHEN n.NombreNormalizado LIKE 'Indemnizacion Art 248%'          THEN n.VALORTOTAL ELSE 0 END) AS MontoArt248,
            SUM(CASE WHEN n.NombreNormalizado = 'Indemnizacion Sustitutiva Preaviso' THEN n.VALORTOTAL ELSE 0 END) AS MontoPreaviso,
            SUM(CASE WHEN n.NombreNormalizado = 'Integracion Mes Despido'            THEN n.VALORTOTAL ELSE 0 END) AS MontoIntegMes,
            SUM(CASE WHEN n.NombreNormalizado = 'Vacaciones No Gozadas'              THEN n.VALORTOTAL ELSE 0 END) AS MontoVNG,
            SUM(CASE WHEN n.NombreNormalizado = 'SAC sobre Vacaciones No Gozadas'    THEN n.VALORTOTAL ELSE 0 END) AS MontoSACsVNG,
            SUM(CASE WHEN n.NombreNormalizado = 'Indemnizacion Fallecimiento'        THEN n.VALORTOTAL ELSE 0 END) AS MontoFallecimiento,
            SUM(CASE WHEN n.Categoria        = 'LIQUIDACION_FINAL'                   THEN n.VALORTOTAL ELSE 0 END) AS TotalLiquidacionFinal
        FROM dbo.vw_Sueldos_ReciboDetalle_Normalizado n
        JOIN elegidas e
            ON n.Empresa = e.Empresa
           AND n.IdEmpleado = e.IdEmpleado
           AND n.IdLiquidacion = e.IdLiquidacion
        GROUP BY n.Empresa, n.IdEmpleado, n.IdLiquidacion
    ),
    final_data AS (
        SELECT
            e.Empresa,
            e.IdEmpleado,
            a.NombreEmpleado,
            a.CUIL,
            LEFT(e.PeriodoEconomico, 4) AS Anio,
            e.PeriodoEconomico AS PeriodoBaja,
            e.PeriodoAdmin AS PeriodoAdminBaja,
            a.FechaCierre,
            a.FechaPago,
            a.TipoLiquidacion,
            CASE
                WHEN a.MontoFallecimiento > 0 THEN 'FALLECIMIENTO'
                WHEN a.MontoArt248        > 0 THEN 'FUERZA_MAYOR'
                WHEN a.MontoArt245 > 0 OR a.MontoArt247 > 0 THEN 'DESPIDO_SIN_CAUSA'
                ELSE 'RENUNCIA_O_MUTUO'
            END AS MotivoBaja,
            CAST(CASE WHEN a.MontoArt245    > 0 THEN 1 ELSE 0 END AS BIT) AS TieneArt245,
            CAST(CASE WHEN a.MontoArt247    > 0 THEN 1 ELSE 0 END AS BIT) AS TieneArt247,
            CAST(CASE WHEN a.MontoArt248    > 0 THEN 1 ELSE 0 END AS BIT) AS TieneArt248,
            CAST(CASE WHEN a.MontoPreaviso  > 0 THEN 1 ELSE 0 END AS BIT) AS TienePreaviso,
            CAST(CASE WHEN a.MontoIntegMes  > 0 THEN 1 ELSE 0 END AS BIT) AS TieneIntegracionMes,
            CAST(CASE WHEN a.MontoVNG       > 0 THEN 1 ELSE 0 END AS BIT) AS TieneVNG,
            CAST(CASE WHEN a.MontoSACsVNG   > 0 THEN 1 ELSE 0 END AS BIT) AS TieneSACsVNG,
            a.MontoArt245,
            a.MontoArt247,
            a.MontoArt248,
            a.MontoPreaviso,
            a.MontoIntegMes,
            a.MontoVNG,
            a.MontoSACsVNG,
            (a.MontoArt245 + a.MontoArt247 + a.MontoArt248 + a.MontoPreaviso + a.MontoIntegMes) AS TotalIndemnizatorio,
            a.TotalLiquidacionFinal,
            e.IdLiquidacion
        FROM elegidas e
        JOIN agg a
            ON a.Empresa = e.Empresa
           AND a.IdEmpleado = e.IdEmpleado
           AND a.IdLiquidacion = e.IdLiquidacion
    )
    SELECT
        fd.*,
        CASE WHEN b.IdEmpleado IS NULL THEN 'NUEVA' ELSE 'EXISTE' END AS Estado
    INTO #candidatas
    FROM final_data fd
    LEFT JOIN dbo.Sueldos_Bajas b
        ON b.Empresa = fd.Empresa AND b.IdEmpleado = fd.IdEmpleado;

    IF @SoloMostrarPreview = 1
    BEGIN
        SELECT *
        FROM #candidatas
        ORDER BY Estado, Empresa, IdEmpleado;
        RETURN;
    END;

    INSERT INTO dbo.Sueldos_Bajas (
        Empresa, IdEmpleado, NombreEmpleado, CUIL, Anio, PeriodoBaja,
        FechaCierre, FechaPago, TipoLiquidacion, MotivoBaja,
        TieneArt245, TieneArt247, TieneArt248, TienePreaviso,
        TieneIntegracionMes, TieneVNG, TieneSACsVNG,
        MontoArt245, MontoArt247, MontoArt248, MontoPreaviso,
        MontoIntegMes, MontoVNG, MontoSACsVNG,
        TotalIndemnizatorio, TotalLiquidacionFinal,
        FechaCarga, IdLiquidacion, PeriodoAdminBaja
    )
    SELECT
        Empresa, IdEmpleado, NombreEmpleado, CUIL, Anio, PeriodoBaja,
        FechaCierre, FechaPago, TipoLiquidacion, MotivoBaja,
        TieneArt245, TieneArt247, TieneArt248, TienePreaviso,
        TieneIntegracionMes, TieneVNG, TieneSACsVNG,
        MontoArt245, MontoArt247, MontoArt248, MontoPreaviso,
        MontoIntegMes, MontoVNG, MontoSACsVNG,
        TotalIndemnizatorio, TotalLiquidacionFinal,
        SYSDATETIME(), IdLiquidacion, PeriodoAdminBaja
    FROM #candidatas
    WHERE Estado = 'NUEVA';

    DECLARE @ins INT = @@ROWCOUNT;

    SELECT
        @ins AS BajasInsertadas,
        (SELECT COUNT(*) FROM #candidatas WHERE Estado = 'EXISTE') AS YaExistian,
        (SELECT COUNT(*) FROM #candidatas) AS CandidatasEvaluadas,
        @PeriodoDesde AS PeriodoDesde,
        @PeriodoHasta AS PeriodoHasta;

    DROP TABLE #candidatas;
END
GO
