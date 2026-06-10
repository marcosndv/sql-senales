-- ============================================================================
-- VISTA: dbo.vw_Sueldos_Puestos_Tipificados
-- ----------------------------------------------------------------------------
-- Clasifica cada puesto (UltimoPuestoCod / UltimoPuestoNombre) en una de tres
-- categorias operativas: COCINA / SERVICIO / OTROS. Match por palabras clave
-- del nombre del puesto. Si el ERP corrige inconsistencias de nombre, la vista
-- se recalcula automaticamente sin tocar codigo.
--
-- Keywords (case-insensitive por collation default):
--   COCINA   = cocina | cocinero | bachero | lavacopas | pastel | panad
--              | comis (cocina) | jefe de cocina | supervisor de cocina
--   SERVICIO = camarer | sommel | cajer | maitre | hostess | mozo | runner
--              | encargado de sector | encargado/a de sector | jefe de servicio
--              | at. cliente | atencion cliente | barra | bartender | coctel
--   OTROS    = todo el resto (administrativo, mantenimiento, deposito,
--              produccion, viña, gerencia, etc.)
-- ============================================================================
CREATE OR ALTER VIEW dbo.vw_Sueldos_Puestos_Tipificados
AS
WITH puestos AS (
    SELECT DISTINCT n.UltimoPuestoNombre AS PuestoNombre
    FROM dbo.vw_Sueldos_Nomina n
    WHERE n.UltimoPuestoNombre IS NOT NULL
)
SELECT
    p.PuestoNombre,
    CASE
        WHEN p.PuestoNombre LIKE '%cocin%'
          OR p.PuestoNombre LIKE '%cocinero%'
          OR p.PuestoNombre LIKE '%bacher%'
          OR p.PuestoNombre LIKE '%lavacop%'
          OR p.PuestoNombre LIKE '%pastel%'
          OR p.PuestoNombre LIKE '%panad%'
            THEN 'COCINA'
        WHEN p.PuestoNombre LIKE '%camarer%'
          OR p.PuestoNombre LIKE '%sommel%'
          OR p.PuestoNombre LIKE '%cajer%'
          OR p.PuestoNombre LIKE '%maitre%'
          OR p.PuestoNombre LIKE '%hostess%'
          OR p.PuestoNombre LIKE '%mozo%'
          OR p.PuestoNombre LIKE '%runner%'
          OR p.PuestoNombre LIKE '%encargado de sector%'
          OR p.PuestoNombre LIKE '%encargado/a de sector%'
          OR p.PuestoNombre LIKE '%jefe de servicio%'
          OR p.PuestoNombre LIKE '%at.%cliente%'
          OR p.PuestoNombre LIKE '%atencion%cliente%'
          OR p.PuestoNombre LIKE '%barra%'
          OR p.PuestoNombre LIKE '%bartender%'
          OR p.PuestoNombre LIKE '%coctel%'
            THEN 'SERVICIO'
        ELSE 'OTROS'
    END AS TipoTrabajo
FROM puestos p;
