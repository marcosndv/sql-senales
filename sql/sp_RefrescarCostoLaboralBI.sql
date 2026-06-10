-- ============================================================================
-- sp_RefrescarCostoLaboralBI
-- ----------------------------------------------------------------------------
-- Materializa dbo.Sueldos_CostoLaboralBI (tabla destino de Power BI) usando
-- CC al momento de la liquidacion (snapshot por periodo) — NO el CC vigente.
--
-- Cambio respecto a version previa:
--   - Antes: CC_MaxFecha (global por empleado) -> mostraba siempre el CC actual.
--   - Ahora: CC_FechaSnapshot por (empresa, empleado, periodo) usando
--            EOMONTH del periodo como corte temporal.
--   - Conservadas: la division por PctCC para distribuir costos entre CC y
--                  el CROSS APPLY STRING_SPLIT('/') sobre el nombre del CC.
--
-- Uso:
--   EXEC dbo.sp_RefrescarCostoLaboralBI;            -- ventana 24 meses
--   EXEC dbo.sp_RefrescarCostoLaboralBI @Debug = 1; -- solo muestra ventana
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.sp_RefrescarCostoLaboralBI
    @Debug BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PeriodoMin VARCHAR(6) = FORMAT(DATEADD(MONTH, -23,
                                        DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)),
                                        'yyyyMM');
    DECLARE @PeriodoMax VARCHAR(6) = FORMAT(GETDATE(), 'yyyyMM');

    PRINT '================================================';
    PRINT 'sp_RefrescarCostoLaboralBI';
    PRINT '  Ventana: ' + @PeriodoMin + ' — ' + @PeriodoMax;
    PRINT '  CC: snapshot al fin del periodo (historico)';
    PRINT '================================================';

    IF @Debug = 1
    BEGIN
        PRINT 'Modo DEBUG: no se modifican datos.';
        RETURN;
    END

    BEGIN TRANSACTION;
    BEGIN TRY

        DELETE FROM dbo.Sueldos_CostoLaboralBI
        WHERE PERIODO >= @PeriodoMin;

        WITH

        -- Universo de (empresa, empleado, periodo) dentro de la ventana
        EmpleadoXPeriodo AS (
            SELECT DISTINCT
                cxe.Empresa,
                cxe.EMPLEADO,
                cxe.PERIODO
            FROM dbo.Sueldos_ContribucionesXEmpleado cxe
            WHERE cxe.PERIODO >= @PeriodoMin
        ),

        -- Fecha snapshot por periodo = ultimo dia del mes
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

        -- CC vigentes al snapshot + split del nombre + PctCC para distribuir costos
        CC_AlMomento AS (
            SELECT
                sel.Empresa,
                sel.EMPLEADO,
                sel.PERIODO,
                CAST(cat.CODIGO AS NVARCHAR(20))                              AS CodigoCentroCosto,
                TRIM(sc.value)                                                AS NombreCentroCosto,
                1.0 / COUNT(*) OVER (PARTITION BY sel.Empresa, sel.EMPLEADO, sel.PERIODO) AS PctCC
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
            CROSS APPLY STRING_SPLIT(cat.NOMBRE, '/') sc
        ),

        UltimoPuesto AS (
            SELECT
                Empresa, EMPLEADO, PUESTO, ESTABLECIM,
                ROW_NUMBER() OVER (PARTITION BY Empresa, EMPLEADO ORDER BY FECHA DESC) AS rn
            FROM dbo.vw_Sueldos_EmpleadosXPuesto
        ),

        ContratoActivo AS (
            SELECT
                Empresa, EMPLEADO, CONTRATO,
                ROW_NUMBER() OVER (PARTITION BY Empresa, EMPLEADO ORDER BY INGRESO DESC) AS rn
            FROM dbo.vw_Sueldos_ContratosXEmpleado
            WHERE EGRESO IS NULL OR EGRESO >= CAST(GETDATE() AS DATE)
        )

        INSERT INTO dbo.Sueldos_CostoLaboralBI (
            Empresa, [Razón Social], PERIODO, [Año], Mes,
            [Tipo Liquidacion], [Id Liquidacion], [Fecha Pago],
            [Código Establec.], [Nombre Establecimiento],
            [Código Centro de Costo], [Nombre Centro de Costo],
            [Código Puesto de Trabajo], [Nombre Puesto de Trabajo],
            [Código Contrato], [Nombre Contrato],
            [Código Sindicato], [Nombre Sindicato],
            [Código Empleado], [Nombre Empleado], CUIL, [Género],
            [Fecha antigüedad], [Años Antigüedad],
            [SUELDO BÁSICO], [FALTA INJUSTIFICADA], [DÍAS NO TRABAJADOS],
            [COMPLEMENTO DE SERVICIO], [ASISTENCIA PERFECTA 10%],
            [ADICIONAL ALIMENTACIÓN], [DESC. ADICIONAL ALIMENTACIÓN],
            [DÍAS ENFERMEDAD], FERIADOS, ANTIGUEDAD,
            [DÍAS VACACIONES], [SANCION DISCIPLINARIA],
            [SUMA REM NO AL BASICO], [GRAT.EXTRAORD. NO REM],
            [BONO PRODUCTIVIDAD], REDONDEO, [2DO SUELDO ANUAL COMPLEMENTARIO],
            [JUBILACIÓN], INSSJP, [OBRA SOCIAL], UTHGRA, [SEG. DE VIDA Y SEPELIO],
            [Sueldo Bruto], [Total Descuentos], [Retención Ganancias], [Sueldo Neto],
            [Total Bruto Remunerativo], [Total Bruto No Remunerativo],
            [% Participacion Bruto],
            [Contrib. Empleador SS+OS+RENATRE], [Contrib. ART (LRT)],
            [Contrib. Seguro de Vida Oblig.], [Contrib. Sindicales (UTHGRA)],
            [Total Contribuciones Empleador], [Costo Laboral Total],
            _fecha_carga
        )
        SELECT
            emp.Empresa,
            COALESCE(ce.NombreEmpresa, emp.Empresa),
            liq.PERIODO,
            LEFT(liq.PERIODO, 4),
            RIGHT(liq.PERIODO, 2),
            CASE liq.CLASE
                WHEN 1 THEN '1ra Quincena'
                WHEN 2 THEN '2da Quincena'
                WHEN 3 THEN 'Mensual'
                WHEN 4 THEN 'Especial / SAC'
                ELSE        'Clase ' + CAST(liq.CLASE AS VARCHAR)
            END,
            liq.CODIGO,
            liq.FECHAPAGO,
            CAST(xp.ESTABLECIM AS NVARCHAR(20)),
            est.NOMBRE,
            COALESCE(ccv.CodigoCentroCosto, 'Sin asignar'),
            COALESCE(ccv.NombreCentroCosto, 'Sin asignar'),
            CAST(pue.CODIGO AS NVARCHAR(20)),
            pue.NOMBRE,
            ca.CONTRATO,
            COALESCE(tc.NombreContrato, 'Codigo ' + CAST(ISNULL(ca.CONTRATO, 0) AS VARCHAR)),
            emp.SINDICATO,
            COALESCE(sind.NombreSindicato, 'Sindicato ' + CAST(ISNULL(emp.SINDICATO, 0) AS VARCHAR)),
            emp.CODIGO,
            emp.NOMBRE,
            emp.CUIL,
            CASE emp.SEXO WHEN 1 THEN 'Masculino' WHEN 2 THEN 'Femenino' ELSE 'No especificado' END,
            emp.FCHANTIG,
            CASE WHEN emp.FCHANTIG IS NOT NULL
                THEN DATEDIFF(YEAR, emp.FCHANTIG,
                         EOMONTH(DATEFROMPARTS(CAST(LEFT(liq.PERIODO,4) AS INT),
                                               CAST(RIGHT(liq.PERIODO,2) AS INT), 1)))
            END,
            ROUND(ISNULL(cpc.SueldoBasico,              0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.FaltaInjustificada,        0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.DiasNoTrabajados,          0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.ComplementoServicio,       0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.AsistenciaPerfecta,        0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.AdicionalAlimentacion,     0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.DescAdicionalAlimentacion, 0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.DiasEnfermedad,            0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.Feriados,                  0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.Antiguedad,                0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.DiasVacaciones,            0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.SancionDisciplinaria,      0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.SumaRemNoAlBasico,         0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.GratExtraordNoRem,         0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.BonoProductividad,         0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.Redondeo,                  0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.SegundoSAC,                0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.Jubilacion,                0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.INSSJP,                    0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.ObraSocial,                0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.DescUTHGRA,                0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cpc.SeguroVidaSepelio,         0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(lxe.SUELDOBRTO,                0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(lxe.DESCUENTOS,                0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(lxe.RETENGCIAS,                0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(lxe.SUELDONETO,                0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cxe.BrutoRemunerativo,         0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cxe.BrutoNoRemunerativo,       0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cxe.PctParticipacion,          0) * ISNULL(ccv.PctCC, 1.0), 8),
            ROUND(ISNULL(cxe.ContribEmpleadorSS,        0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cxe.ContribART,                0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cxe.ContribSegVida,            0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND(ISNULL(cxe.ContribSindicales,         0) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND((  ISNULL(cxe.ContribEmpleadorSS,  0)
                   + ISNULL(cxe.ContribART,          0)
                   + ISNULL(cxe.ContribSegVida,      0)
                   + ISNULL(cxe.ContribSindicales,   0)) * ISNULL(ccv.PctCC, 1.0), 2),
            ROUND((  ISNULL(lxe.SUELDOBRTO,          0)
                   + ISNULL(cxe.ContribEmpleadorSS,  0)
                   + ISNULL(cxe.ContribART,          0)
                   + ISNULL(cxe.ContribSegVida,      0)
                   + ISNULL(cxe.ContribSindicales,   0)) * ISNULL(ccv.PctCC, 1.0), 2),
            GETDATE()

        FROM dbo.Sueldos_ContribucionesXEmpleado cxe
        INNER JOIN dbo.vw_Sueldos_Empleados emp
            ON  emp.CODIGO  = cxe.EMPLEADO
            AND emp.Empresa = cxe.Empresa
        INNER JOIN dbo.vw_Sueldos_Liquidaciones liq
            ON  liq.CODIGO  = cxe.LIQUIDAC
            AND liq.Empresa = cxe.Empresa
        LEFT JOIN dbo.vw_Sueldos_LiqXEmpleado lxe
            ON  lxe.EMPLEADO = cxe.EMPLEADO
            AND lxe.LIQUIDAC = cxe.LIQUIDAC
            AND lxe.Empresa  = cxe.Empresa
        LEFT JOIN dbo.Sueldos_ConceptosXEmpleado cpc
            ON  cpc.Empresa  = cxe.Empresa
            AND cpc.LIQUIDAC = cxe.LIQUIDAC
            AND cpc.EMPLEADO = cxe.EMPLEADO
        LEFT JOIN CC_AlMomento ccv
            ON  ccv.EMPLEADO = cxe.EMPLEADO
            AND ccv.Empresa  = cxe.Empresa
            AND ccv.PERIODO  = cxe.PERIODO
        LEFT JOIN UltimoPuesto xp
            ON  xp.EMPLEADO = cxe.EMPLEADO
            AND xp.Empresa  = cxe.Empresa
            AND xp.rn       = 1
        LEFT JOIN dbo.vw_Sueldos_Puestos pue
            ON  pue.CODIGO  = xp.PUESTO
            AND pue.Empresa = xp.Empresa
        LEFT JOIN dbo.vw_Sueldos_Establecimientos est
            ON  est.CODIGO  = xp.ESTABLECIM
            AND est.Empresa = xp.Empresa
        LEFT JOIN ContratoActivo ca
            ON  ca.EMPLEADO = cxe.EMPLEADO
            AND ca.Empresa  = cxe.Empresa
            AND ca.rn       = 1
        LEFT JOIN dbo.Config_TiposContrato tc
            ON  tc.CodContrato = ca.CONTRATO
        LEFT JOIN dbo.Config_Sindicatos sind
            ON  sind.Empresa         = cxe.Empresa
            AND sind.CodigoSindicato = emp.SINDICATO
        LEFT JOIN dbo.Config_Empresas_Sueldos ce
            ON  ce.Empresa = cxe.Empresa

        WHERE cxe.PERIODO >= @PeriodoMin;

        DECLARE @filas INT = @@ROWCOUNT;
        COMMIT TRANSACTION;

        PRINT 'OK: ' + CAST(@filas AS VARCHAR) + ' filas insertadas.';
        PRINT 'Tabla lista para Power BI: dbo.Sueldos_CostoLaboralBI';

    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        PRINT 'ERROR: ' + ERROR_MESSAGE();
        THROW;
    END CATCH
END;
