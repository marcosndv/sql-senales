-- ============================================================================
-- VISTA: dbo.vw_Sueldos_ResumenCCXPeriodo
-- ----------------------------------------------------------------------------
-- Resumen por (empresa, periodo, centro de costo) basado en la tabla
-- materializada dbo.Sueldos_CostoLaboralBI (que ya tiene el CC historico).
--
-- Una fila por (Empresa, PERIODO, CC) con:
--   - cantidad de empleados distintos
--   - masa salarial bruta (rem + no rem)
--   - costo laboral total
--   - contribuciones del empleador
--   - costo promedio por empleado
--
-- Uso:
--   SELECT * FROM dbo.vw_Sueldos_ResumenCCXPeriodo
--   WHERE LEFT(PERIODO, 4) = '2026' ORDER BY PERIODO, CodCC;
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Sueldos_ResumenCCXPeriodo AS
SELECT
    Empresa,
    RazonSocial                     = MAX([Razón Social]),
    PERIODO,
    Anio                            = LEFT(PERIODO, 4),
    Mes                             = RIGHT(PERIODO, 2),
    CodCC                           = [Código Centro de Costo],
    NombreCC                        = [Nombre Centro de Costo],
    Empleados                       = COUNT(DISTINCT [Código Empleado]),
    BrutoRemunerativo               = SUM([Total Bruto Remunerativo]),
    BrutoNoRemunerativo             = SUM([Total Bruto No Remunerativo]),
    MasaBruta                       = SUM([Total Bruto Remunerativo] + [Total Bruto No Remunerativo]),
    SueldoNeto                      = SUM([Sueldo Neto]),
    TotalDescuentos                 = SUM([Total Descuentos]),
    ContribSICOSS                   = SUM([Contrib. Empleador SS+OS+RENATRE]),
    ContribART                      = SUM([Contrib. ART (LRT)]),
    ContribSegVida                  = SUM([Contrib. Seguro de Vida Oblig.]),
    ContribSindicales               = SUM([Contrib. Sindicales (UTHGRA)]),
    TotalContribucionesEmpleador    = SUM([Total Contribuciones Empleador]),
    CostoLaboralTotal               = SUM([Costo Laboral Total]),
    CostoLaboralPromedioPorEmpleado = CASE
                                          WHEN COUNT(DISTINCT [Código Empleado]) > 0
                                          THEN SUM([Costo Laboral Total]) / COUNT(DISTINCT [Código Empleado])
                                          ELSE 0
                                      END
FROM dbo.Sueldos_CostoLaboralBI
GROUP BY
    Empresa,
    PERIODO,
    [Código Centro de Costo],
    [Nombre Centro de Costo];
