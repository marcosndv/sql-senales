-- ============================================================================
-- VISTA: dbo.vw_Sueldos_Nomina_Activa
-- ----------------------------------------------------------------------------
-- Atajo a fn_Sueldos_Nomina_Activa apuntando al ultimo periodo "completo":
-- el ultimo PERIODO con liquidacion MENSUAL (CLASE=3) en >= 5 empresas. Esto
-- evita que una empresa chica que ya cerro el mes (ej. EMPR0011 con 1
-- empleado) arrastre la vista a un mes que el resto todavia no liquido.
--
-- Uso:
--   SELECT * FROM dbo.vw_Sueldos_Nomina_Activa;
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Sueldos_Nomina_Activa
AS
WITH ult AS (
    SELECT TOP 1 PERIODO
    FROM dbo.vw_Sueldos_Liquidaciones
    WHERE CLASE = 3
    GROUP BY PERIODO
    HAVING COUNT(DISTINCT Empresa) >= 5
    ORDER BY PERIODO DESC
)
SELECT n.*
FROM ult
CROSS APPLY dbo.fn_Sueldos_Nomina_Activa(ult.PERIODO) n;
