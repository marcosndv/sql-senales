-- ============================================================================
-- sp_DiagnosticoETLSueldos
-- ----------------------------------------------------------------------------
-- Diagnostico del ETL Sueldos. Detecta:
--   1) Errores recientes con columna faltante extraida del mensaje
--   2) Script ALTER TABLE listo para aplicar (tipo deducido o NVARCHAR(80))
--   3) Schema drift: misma tabla en varios esquemas EMPR* con columnas distintas
--   4) Tablas SUELDOS_ vacias en algun esquema (potencial carga fallida silenciosa)
--
-- Uso:
--   EXEC dbo.sp_DiagnosticoETLSueldos;                          -- ultimas 24 hs
--   EXEC dbo.sp_DiagnosticoETLSueldos @Horas = 72;              -- ultimos 3 dias
--   EXEC dbo.sp_DiagnosticoETLSueldos @VerDrift = 0;            -- omitir drift
--   EXEC dbo.sp_DiagnosticoETLSueldos @VerVacias = 0;           -- omitir tablas vacias
-- ============================================================================
CREATE OR ALTER PROCEDURE dbo.sp_DiagnosticoETLSueldos
    @Horas      INT = 24,
    @VerDrift   BIT = 1,
    @VerVacias  BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    -- ── Extraccion robusta de "Invalid column name 'X'" ────────────────────
    ;WITH ErroresRaw AS (
        SELECT
            l.tabla_nombre,
            l.fecha_inicio,
            l.mensaje_error,
            CASE
                WHEN l.mensaje_error LIKE '%Invalid column name%''%'
                THEN SUBSTRING(
                        l.mensaje_error,
                        CHARINDEX('''', l.mensaje_error,
                            CHARINDEX('Invalid column name', l.mensaje_error)) + 1,
                        CHARINDEX('''', l.mensaje_error,
                            CHARINDEX('''', l.mensaje_error,
                                CHARINDEX('Invalid column name', l.mensaje_error)) + 1)
                        - CHARINDEX('''', l.mensaje_error,
                            CHARINDEX('Invalid column name', l.mensaje_error)) - 1
                     )
            END AS ColumnaFaltante
        FROM dbo.ETL_Sueldos_Log l
        WHERE l.estado = 'ERROR'
          AND l.fecha_inicio >= DATEADD(HOUR, -@Horas, GETDATE())
    )
    -- ── 1) Errores recientes agregados ────────────────────────────────────
    SELECT
        '1. ERRORES_RECIENTES' AS Seccion,
        tabla_nombre           AS Tabla,
        ColumnaFaltante,
        COUNT(*)               AS Veces,
        MAX(fecha_inicio)      AS UltimaVez,
        LEFT(MAX(mensaje_error), 250) AS Mensaje
    FROM ErroresRaw
    GROUP BY tabla_nombre, ColumnaFaltante
    ORDER BY UltimaVez DESC;

    -- ── 2) Scripts ALTER TABLE con tipo inferido ──────────────────────────
    ;WITH ErroresCol AS (
        SELECT DISTINCT
            l.tabla_nombre,
            CASE
                WHEN l.mensaje_error LIKE '%Invalid column name%''%'
                THEN SUBSTRING(
                        l.mensaje_error,
                        CHARINDEX('''', l.mensaje_error,
                            CHARINDEX('Invalid column name', l.mensaje_error)) + 1,
                        CHARINDEX('''', l.mensaje_error,
                            CHARINDEX('''', l.mensaje_error,
                                CHARINDEX('Invalid column name', l.mensaje_error)) + 1)
                        - CHARINDEX('''', l.mensaje_error,
                            CHARINDEX('Invalid column name', l.mensaje_error)) - 1
                     )
            END AS ColumnaFaltante
        FROM dbo.ETL_Sueldos_Log l
        WHERE l.estado = 'ERROR'
          AND l.mensaje_error LIKE '%Invalid column name%''%'
          AND l.fecha_inicio >= DATEADD(HOUR, -@Horas, GETDATE())
    ),
    -- Buscar el tipo en otras tablas que ya tengan esa columna
    TipoInferido AS (
        SELECT
            ec.tabla_nombre,
            ec.ColumnaFaltante,
            -- Toma el tipo mas frecuente entre todas las tablas SUELDOS_
            (
                SELECT TOP 1
                    ty.name +
                    CASE
                        WHEN ty.name IN ('nvarchar','nchar')
                            THEN '(' + CAST(c.max_length / 2 AS VARCHAR) + ')'
                        WHEN ty.name IN ('varchar','char','varbinary','binary')
                            THEN '(' + CAST(c.max_length AS VARCHAR) + ')'
                        WHEN ty.name IN ('decimal','numeric')
                            THEN '(' + CAST(c.precision AS VARCHAR) + ',' + CAST(c.scale AS VARCHAR) + ')'
                        ELSE ''
                    END
                FROM sys.columns c
                INNER JOIN sys.types  ty ON ty.user_type_id = c.user_type_id
                INNER JOIN sys.tables t  ON t.object_id  = c.object_id
                INNER JOIN sys.schemas s ON s.schema_id  = t.schema_id
                WHERE s.name LIKE 'EMPR%'
                  AND t.name LIKE 'SUELDOS_%'
                  AND c.name = ec.ColumnaFaltante
                GROUP BY ty.name, c.max_length, c.precision, c.scale
                ORDER BY COUNT(*) DESC
            ) AS TipoSugerido
        FROM ErroresCol ec
        WHERE ec.ColumnaFaltante IS NOT NULL AND ec.ColumnaFaltante <> ''
    )
    SELECT
        '2. SCRIPT_REPARACION' AS Seccion,
        tabla_nombre           AS Tabla,
        ColumnaFaltante,
        ISNULL(TipoSugerido, 'NVARCHAR(80)') AS TipoSugerido,
        CASE WHEN TipoSugerido IS NULL THEN '(tipo default — revisar)' ELSE '(tipo deducido de otra tabla)' END AS Origen,
        'ALTER TABLE [' + PARSENAME(tabla_nombre, 2) + '].['
            + PARSENAME(tabla_nombre, 1) + '] ADD ['
            + ColumnaFaltante + '] ' + ISNULL(TipoSugerido, 'NVARCHAR(80)')
            + ' NULL;' AS Script
    FROM TipoInferido;

    -- ── 3) Schema drift entre esquemas EMPR* ─────────────────────────────
    IF @VerDrift = 1
    BEGIN
        ;WITH Cols AS (
            SELECT
                t.name  AS TableName,
                s.name  AS SchemaName,
                c.name  AS ColumnName
            FROM sys.columns c
            INNER JOIN sys.tables  t ON t.object_id = c.object_id
            INNER JOIN sys.schemas s ON s.schema_id = t.schema_id
            WHERE s.name LIKE 'EMPR%'
              AND t.name LIKE 'SUELDOS_%'
              AND c.name NOT LIKE '\_%' ESCAPE '\'    -- excluir _id, _fecha_carga, _id_carga
        ),
        EsquemasPorTabla AS (
            SELECT TableName, COUNT(DISTINCT SchemaName) AS EsquemasTotal
            FROM Cols GROUP BY TableName
        ),
        ColPresente AS (
            SELECT TableName, ColumnName, COUNT(DISTINCT SchemaName) AS EsquemasConColumna
            FROM Cols GROUP BY TableName, ColumnName
        )
        SELECT
            '3. SCHEMA_DRIFT' AS Seccion,
            cp.TableName      AS Tabla,
            cp.ColumnName     AS Columna,
            cp.EsquemasConColumna,
            ept.EsquemasTotal,
            (ept.EsquemasTotal - cp.EsquemasConColumna) AS EsquemasQueLeFaltan,
            STUFF((
                SELECT ', ' + s.name
                FROM sys.schemas s
                INNER JOIN sys.tables t ON t.schema_id = s.schema_id AND t.name = cp.TableName
                WHERE s.name LIKE 'EMPR%'
                  AND NOT EXISTS (
                        SELECT 1 FROM sys.columns c2
                        WHERE c2.object_id = t.object_id AND c2.name = cp.ColumnName
                  )
                ORDER BY s.name
                FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)'), 1, 2, '') AS EsquemasSinColumna
        FROM ColPresente cp
        INNER JOIN EsquemasPorTabla ept ON ept.TableName = cp.TableName
        WHERE cp.EsquemasConColumna < ept.EsquemasTotal
        ORDER BY (ept.EsquemasTotal - cp.EsquemasConColumna) DESC,
                 cp.TableName, cp.ColumnName;
    END

    -- ── 4) Tablas SUELDOS_ vacias (potencial fallo silencioso) ───────────
    IF @VerVacias = 1
    BEGIN
        DECLARE @sql NVARCHAR(MAX) =
            (SELECT STRING_AGG(
                'SELECT ''4. TABLAS_VACIAS'' AS Seccion, '''
                    + s.name + '.' + t.name + ''' AS Tabla, '
                    + CAST(p.rows AS VARCHAR) + ' AS Filas, '
                    + 'COALESCE(CONVERT(VARCHAR, (SELECT MAX(_fecha_carga) FROM ['
                    + s.name + '].[' + t.name + ']), 120), ''(sin carga)'') AS UltimaCarga',
                ' UNION ALL ')
             FROM sys.tables t
             INNER JOIN sys.schemas s   ON s.schema_id = t.schema_id
             INNER JOIN sys.partitions p ON p.object_id = t.object_id AND p.index_id IN (0,1)
             WHERE s.name LIKE 'EMPR%'
               AND t.name LIKE 'SUELDOS_%'
               AND p.rows = 0
            );

        IF @sql IS NOT NULL AND LEN(@sql) > 0
            EXEC sp_executesql @sql;
        ELSE
            SELECT '4. TABLAS_VACIAS' AS Seccion,
                   '(ninguna tabla SUELDOS_ vacia)' AS Tabla,
                   NULL AS Filas, NULL AS UltimaCarga;
    END
END;
