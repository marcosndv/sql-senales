-- ============================================================================
-- VISTA: dbo.vw_Sueldos_Liquidaciones_MesEconomico
-- ----------------------------------------------------------------------------
-- Calcula el MES ECONOMICO real de cada liquidacion parseando COMENTARIO.
--
-- Motivacion: el campo PERIODO en SUELDOS_LIQUIDACIONES es el mes ADMINISTRATIVO
-- en que se proceso la liquidacion. Para liquidaciones finales y ajustes, el
-- ERP suele cargarlas en el periodo siguiente al mes economico real. Ejemplo:
-- una liquidacion final de abril se carga con PERIODO=202605 pero el COMENTARIO
-- dice "Liq. finales Abr-2026" -- economicamente es 202604.
--
-- Regla:
--   1) Buscar nombre de mes (largo o corto) + un año 20XX en el COMENTARIO.
--   2) Si se encuentra, ese es el PeriodoEconomico.
--   3) Si no, fallback a PERIODO (el admin).
--
-- NOTAS:
--   - La clase NO es fiable para detectar finales (Empr0002 IdLiq 184 esta
--     como CLASE=3 pero es "Liq. finales Abr-2026"). Por eso parseamos solo
--     el comentario.
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Sueldos_Liquidaciones_MesEconomico
AS
WITH all_liq AS (
    SELECT 'EMPR0001' AS Empresa, CODIGO, PERIODO, CLASE, CIERRE AS FechaCierre, FECHAPAGO AS FechaPago, COMENTARIO FROM EMPR0001.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'Empr0002', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM Empr0002.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR0003', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR0003.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR0004', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR0004.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR0005', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR0005.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR0006', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR0006.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR0007', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR0007.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR0008', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR0008.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR0009', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR0009.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR0010', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR0010.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR0011', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR0011.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR0012', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR0012.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR0013', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR0013.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR0014', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR0014.SUELDOS_LIQUIDACIONES
    UNION ALL SELECT 'EMPR7000', CODIGO, PERIODO, CLASE, CIERRE, FECHAPAGO, COMENTARIO FROM EMPR7000.SUELDOS_LIQUIDACIONES
),
parsed AS (
    SELECT
        l.Empresa,
        l.CODIGO,
        l.PERIODO,
        l.CLASE,
        l.FechaCierre,
        l.FechaPago,
        l.COMENTARIO,

        -- Año: primer "20XX" que aparezca en COMENTARIO
        CASE
            WHEN PATINDEX('%20[0-9][0-9]%', ISNULL(l.COMENTARIO,'')) > 0
                THEN SUBSTRING(l.COMENTARIO, PATINDEX('%20[0-9][0-9]%', l.COMENTARIO), 4)
        END AS AnioParsed,

        -- Mes: ordenado de mes largo (mas especifico) a mes corto. Case-insensitive
        -- por collation default. Primer match gana.
        CASE
            WHEN l.COMENTARIO LIKE '%enero%'      THEN '01'
            WHEN l.COMENTARIO LIKE '%febrero%'    THEN '02'
            WHEN l.COMENTARIO LIKE '%marzo%'      THEN '03'
            WHEN l.COMENTARIO LIKE '%abril%'      THEN '04'
            WHEN l.COMENTARIO LIKE '%mayo%'       THEN '05'
            WHEN l.COMENTARIO LIKE '%junio%'      THEN '06'
            WHEN l.COMENTARIO LIKE '%julio%'      THEN '07'
            WHEN l.COMENTARIO LIKE '%agosto%'     THEN '08'
            WHEN l.COMENTARIO LIKE '%septiembre%' THEN '09'
            WHEN l.COMENTARIO LIKE '%setiembre%'  THEN '09'
            WHEN l.COMENTARIO LIKE '%octubre%'    THEN '10'
            WHEN l.COMENTARIO LIKE '%noviembre%'  THEN '11'
            WHEN l.COMENTARIO LIKE '%diciembre%'  THEN '12'
            -- Formas cortas (3 letras + separador: guion, espacio, punto, fin de string)
            WHEN l.COMENTARIO LIKE '%ene[- .,/0-9]%' OR l.COMENTARIO LIKE '%ene' THEN '01'
            WHEN l.COMENTARIO LIKE '%feb[- .,/0-9]%' OR l.COMENTARIO LIKE '%feb' THEN '02'
            WHEN l.COMENTARIO LIKE '%mar[- .,/0-9]%' OR l.COMENTARIO LIKE '%mar' THEN '03'
            WHEN l.COMENTARIO LIKE '%abr[- .,/0-9]%' OR l.COMENTARIO LIKE '%abr' THEN '04'
            WHEN l.COMENTARIO LIKE '%may[- .,/0-9]%' OR l.COMENTARIO LIKE '%may' THEN '05'
            WHEN l.COMENTARIO LIKE '%jun[- .,/0-9]%' OR l.COMENTARIO LIKE '%jun' THEN '06'
            WHEN l.COMENTARIO LIKE '%jul[- .,/0-9]%' OR l.COMENTARIO LIKE '%jul' THEN '07'
            WHEN l.COMENTARIO LIKE '%ago[- .,/0-9]%' OR l.COMENTARIO LIKE '%ago' THEN '08'
            WHEN l.COMENTARIO LIKE '%sep[- .,/0-9]%' OR l.COMENTARIO LIKE '%sep' THEN '09'
            WHEN l.COMENTARIO LIKE '%set[- .,/0-9]%' OR l.COMENTARIO LIKE '%set' THEN '09'
            WHEN l.COMENTARIO LIKE '%oct[- .,/0-9]%' OR l.COMENTARIO LIKE '%oct' THEN '10'
            WHEN l.COMENTARIO LIKE '%nov[- .,/0-9]%' OR l.COMENTARIO LIKE '%nov' THEN '11'
            WHEN l.COMENTARIO LIKE '%dic[- .,/0-9]%' OR l.COMENTARIO LIKE '%dic' THEN '12'
        END AS MesParsed
    FROM all_liq l
)
SELECT
    Empresa,
    CODIGO        AS IdLiquidacion,
    PERIODO       AS PeriodoAdmin,
    CLASE,
    FechaCierre,
    FechaPago,
    COMENTARIO,
    AnioParsed,
    MesParsed,
    -- PeriodoEconomico:
    --   1) Si el COMENTARIO contiene "final" Y se parseo mes+año -> usar ese
    --      mes parseado (la liq final corresponde al mes mencionado).
    --   2) Si la liquidacion es CLASE=5 (final) pero el COMENTARIO no menciona
    --      mes (ej. "Liquidaciones finales" a secas) -> heuristica de 1 mes
    --      atras del PERIODO admin (las finales se procesan al mes siguiente
    --      del economico).
    --   3) Cualquier otro caso -> PeriodoAdmin (las mensuales y los "ajustes"
    --      se mantienen en el mes de procesamiento).
    CAST(
        CASE
            WHEN COMENTARIO LIKE '%final%'
                 AND AnioParsed IS NOT NULL
                 AND MesParsed IS NOT NULL
                THEN AnioParsed + MesParsed
            WHEN CLASE = 5
                THEN FORMAT(
                    DATEADD(MONTH, -1,
                        DATEFROMPARTS(
                            CAST(LEFT(PERIODO, 4) AS INT),
                            CAST(RIGHT(PERIODO, 2) AS INT),
                            1
                        )
                    ),
                    'yyyyMM'
                )
            ELSE PERIODO
        END AS NVARCHAR(6)
    ) AS PeriodoEconomico,
    CAST(
        CASE
            WHEN COMENTARIO LIKE '%final%'
                 AND AnioParsed IS NOT NULL
                 AND MesParsed IS NOT NULL
                 AND (AnioParsed + MesParsed) <> PERIODO
                THEN 1
            WHEN CLASE = 5
                AND FORMAT(
                    DATEADD(MONTH, -1,
                        DATEFROMPARTS(
                            CAST(LEFT(PERIODO, 4) AS INT),
                            CAST(RIGHT(PERIODO, 2) AS INT),
                            1
                        )
                    ),
                    'yyyyMM'
                ) <> PERIODO
                THEN 1
            ELSE 0
        END AS BIT
    ) AS TieneDesfase
FROM parsed;
