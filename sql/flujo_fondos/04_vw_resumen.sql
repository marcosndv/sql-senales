-- ============================================================
-- vw_FlujoFondos_ResumenSemanal
-- Agrupa el proyectado por semana ISO (solo FUTURO).
-- Los vencidos se ven aparte en el dashboard.
-- ============================================================

CREATE OR ALTER VIEW dbo.vw_FlujoFondos_ResumenSemanal AS
SELECT
    DATEPART(iso_week, FechaOriginal)                  AS SemanaIso,
    YEAR(FechaOriginal)                                AS Anio,
    DATEADD(day, 1 - DATEPART(weekday, FechaOriginal), CAST(FechaOriginal AS DATE)) AS InicioSemana,
    Origen,
    Tipo,
    COUNT(*)                                           AS Movimientos,
    SUM(Importe)                                       AS Importe
FROM dbo.vw_FlujoFondos_Proyectado
WHERE EsVencido = 0
GROUP BY DATEPART(iso_week, FechaOriginal), YEAR(FechaOriginal),
         DATEADD(day, 1 - DATEPART(weekday, FechaOriginal), CAST(FechaOriginal AS DATE)),
         Origen, Tipo;
