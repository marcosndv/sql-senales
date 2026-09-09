-- ============================================================
-- Flujo de Fondos - Préstamos bancarios y Planes ARCA
-- Alimentadas por Excel de "TESORERIA - GV" (Google Drive)
--   PRESTAMOS/PRESTAMOS - GV.xlsx
--   IMPOSITIVO/PRESTAMOS, PLANES Y DEUDAS.xlsx
-- Grano: una fila por cuota.
-- ============================================================

-- ---- Préstamos bancarios (cuotas) ----
IF OBJECT_ID('dbo.Manual_Prestamos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Manual_Prestamos (
        Id                  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        EntidadFinanciera   NVARCHAR(60)   NOT NULL,
        EmpresaExcel        NVARCHAR(100)  NOT NULL,   -- viene tal cual del Excel
        Concepto            NVARCHAR(120)  NULL,       -- p.ej. "HSBC 2503954"
        NumeroPrestamo      NVARCHAR(60)   NULL,       -- ej "670-00000002503954"
        NroCuota            INT            NULL,
        Capital             DECIMAL(19,2)  NULL,
        Iva                 DECIMAL(19,2)  NULL,
        InteresFinanciero   DECIMAL(19,2)  NULL,
        Sellado             DECIMAL(19,2)  NULL,
        InteresResarcitorio DECIMAL(19,2)  NULL,
        ImporteCuota        DECIMAL(19,2)  NULL,
        FechaVto            DATE           NULL,
        Estado              NVARCHAR(20)   NULL,       -- PAGA / PENDIENTE
        Condicion           NVARCHAR(20)   NULL,       -- VENCIDO / POR VENCER
        Op                  NVARCHAR(60)   NULL,
        Observacion         NVARCHAR(200)  NULL,
        _cargadoEn          DATETIME2      NOT NULL CONSTRAINT DF_MPrestamos_Fecha DEFAULT SYSDATETIME(),
        _archivoOrigen      NVARCHAR(260)  NULL
    );
    CREATE INDEX IX_Manual_Prestamos_FechaVto ON dbo.Manual_Prestamos(FechaVto);
    CREATE INDEX IX_Manual_Prestamos_Estado   ON dbo.Manual_Prestamos(Estado, FechaVto);
END;

-- ---- Planes ARCA (cuotas) ----
IF OBJECT_ID('dbo.Manual_PlanesArca', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Manual_PlanesArca (
        Id                  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        EntidadFinanciera   NVARCHAR(60)   NOT NULL,   -- AFIP / ARBA / etc
        EmpresaExcel        NVARCHAR(100)  NOT NULL,
        Concepto            NVARCHAR(120)  NULL,
        EstadoPlan          NVARCHAR(30)   NULL,       -- VIGENTE / PLAN CADUCO
        NumeroPlan          NVARCHAR(60)   NULL,
        NroCuota            INT            NULL,
        Capital             DECIMAL(19,2)  NULL,
        Iva                 DECIMAL(19,2)  NULL,
        InteresFinanciero   DECIMAL(19,2)  NULL,
        Sellado             DECIMAL(19,2)  NULL,
        InteresResarcitorio DECIMAL(19,2)  NULL,
        ImporteCuota        DECIMAL(19,2)  NULL,
        FechaVto            DATE           NULL,
        Estado              NVARCHAR(20)   NULL,       -- PAGA / PENDIENTE (de la cuota)
        Condicion           NVARCHAR(20)   NULL,
        Op                  NVARCHAR(60)   NULL,
        _cargadoEn          DATETIME2      NOT NULL CONSTRAINT DF_MPlanesArca_Fecha DEFAULT SYSDATETIME(),
        _archivoOrigen      NVARCHAR(260)  NULL
    );
    CREATE INDEX IX_Manual_PlanesArca_FechaVto ON dbo.Manual_PlanesArca(FechaVto);
    CREATE INDEX IX_Manual_PlanesArca_Estado   ON dbo.Manual_PlanesArca(EstadoPlan, Estado, FechaVto);
END;

-- ============================================================
-- Vista consolidada de cuotas pendientes
-- Aplica reglas: solo PENDIENTE, planes solo VIGENTE, mapeo a Empresa
-- No filtra por fecha: eso se hace en las queries del export.
-- Se ejecuta con EXEC para poder coexistir con tablas en un solo batch
-- (sql.ps1 no procesa 'GO').
-- ============================================================
EXEC('
CREATE OR ALTER VIEW dbo.vw_FlujoFondos_Prestamos AS
SELECT
    ''Préstamos''                                         AS Origen,
    p.Id,
    p.EntidadFinanciera,
    p.Concepto,
    p.NumeroPrestamo                                      AS NumeroOrigen,
    p.NroCuota,
    p.ImporteCuota,
    p.FechaVto,
    p.EmpresaExcel,
    COALESCE(m.Empresa, ''SIN_EMPRESA'')                  AS Empresa,
    COALESCE(ce.NombreEmpresa, m.Empresa, p.EmpresaExcel) AS NombreEmpresa,
    p.Observacion                                         AS Nota,
    CAST(NULL AS NVARCHAR(30))                            AS EstadoPlan
FROM dbo.Manual_Prestamos p
LEFT JOIN dbo.Config_MapeoRazonSocial m ON m.RazonSocialExcel = p.EmpresaExcel
LEFT JOIN dbo.Config_Empresas ce ON ce.Empresa = COALESCE(m.Empresa, '''')
WHERE p.Estado = ''PENDIENTE'' AND ISNULL(p.ImporteCuota, 0) > 0

UNION ALL

SELECT
    ''Planes ARCA''                                       AS Origen,
    pl.Id,
    pl.EntidadFinanciera,
    pl.Concepto,
    pl.NumeroPlan                                         AS NumeroOrigen,
    pl.NroCuota,
    pl.ImporteCuota,
    pl.FechaVto,
    pl.EmpresaExcel,
    COALESCE(m.Empresa, ''SIN_EMPRESA'')                  AS Empresa,
    COALESCE(ce.NombreEmpresa, m.Empresa, pl.EmpresaExcel) AS NombreEmpresa,
    CAST(NULL AS NVARCHAR(200))                           AS Nota,
    pl.EstadoPlan
FROM dbo.Manual_PlanesArca pl
LEFT JOIN dbo.Config_MapeoRazonSocial m ON m.RazonSocialExcel = pl.EmpresaExcel
LEFT JOIN dbo.Config_Empresas ce ON ce.Empresa = COALESCE(m.Empresa, '''')
WHERE pl.Estado = ''PENDIENTE''
  AND (pl.EstadoPlan IS NULL OR pl.EstadoPlan = '''' OR pl.EstadoPlan NOT LIKE ''PLAN CADUCO%'')
  AND ISNULL(pl.ImporteCuota, 0) > 0;
');

PRINT 'Tablas + vista de Préstamos/Planes ARCA listas.';
