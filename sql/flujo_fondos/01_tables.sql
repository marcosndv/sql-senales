-- ============================================================
-- Flujo de Fondos - Tablas manuales alimentadas por Excel
-- ============================================================
-- Idempotente. Corre con .\sql.ps1 -File .\sql\flujo_fondos\01_tables.sql
-- ============================================================

-- ---- Mapeo RazonSocial (Excel) -> Empresa (ERP) ----
IF OBJECT_ID('dbo.Config_MapeoRazonSocial', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Config_MapeoRazonSocial (
        RazonSocialExcel NVARCHAR(100) NOT NULL PRIMARY KEY,
        Empresa          NVARCHAR(20)  NULL,          -- NULL = todavía sin mapear (visible como SIN_EMPRESA)
        Notas            NVARCHAR(200) NULL,
        _cargadoEn       DATETIME2     NOT NULL CONSTRAINT DF_MapeoRS_Fecha DEFAULT SYSDATETIME()
    );
END;

-- Seed / upsert de mapeos conocidos (alias detectados en los Excel de Flujo de Fondos)
MERGE dbo.Config_MapeoRazonSocial AS t
USING (VALUES
    ('LOS VALIENTES',    'EMPR0006'),
    ('CHACHINGO',        'Empr0002'),
    ('ORIGINAL',         'EMPR0001'),
    ('BUR 22',           'EMPR0005'),
    ('BINGO',            'EMPR0012'),
    ('LOSANCE',          'EMPR0011'),
    ('CHIPIRONE',        'EMPR0018'),
    ('MZA4EXPERT',       'EMPR0013'),
    ('DESINFORMADOS',    'EMPR0015'),
    ('NSL',              'EMPR0017'),
    ('55 VALIENTES',     'EMPR0020'),
    ('ALEGORIAS',        'EMPR0009'),
    ('CHAMAN',           'EMPR0004'),
    ('OLD TREE',         'EMPR0010'),
    ('PULTUN',           'EMPR0022'),
    ('PUERTO ESTANCIA',  'EMPR0024'),
    ('FIDEICOMISO ALMA', 'EMPR0023'),
    ('FUNDACION',        'EMPR0021'),
    -- Sin mapear: aparecen en el Excel pero no están en Config_Empresas
    ('VERSACRUM',        NULL),
    ('CVS CARGO',        NULL)
) AS src (RazonSocialExcel, Empresa)
ON t.RazonSocialExcel = src.RazonSocialExcel
WHEN NOT MATCHED THEN
    INSERT (RazonSocialExcel, Empresa) VALUES (src.RazonSocialExcel, src.Empresa);

-- ---- Snapshot diario de saldos bancarios (append por FechaSaldo) ----
IF OBJECT_ID('dbo.Manual_SaldosBancos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Manual_SaldosBancos (
        FechaSaldo             DATE           NOT NULL,
        RazonSocialExcel       NVARCHAR(100)  NOT NULL,
        Banco                  NVARCHAR(50)   NOT NULL,
        Cuenta                 NVARCHAR(50)   NOT NULL,   -- '' cuando el Excel no la trae
        Saldo                  DECIMAL(19,2)  NULL,
        FCI                    DECIMAL(19,2)  NULL,
        MPago                  DECIMAL(19,2)  NULL,
        Pix                    DECIMAL(19,2)  NULL,
        DescubiertoAutorizado  DECIMAL(19,2)  NULL,
        Disponible             DECIMAL(19,2)  NULL,
        _cargadoEn             DATETIME2      NOT NULL CONSTRAINT DF_SaldosBcos_Fecha DEFAULT SYSDATETIME(),
        _archivoOrigen         NVARCHAR(260)  NULL,
        CONSTRAINT PK_Manual_SaldosBancos PRIMARY KEY (FechaSaldo, RazonSocialExcel, Banco, Cuenta)
    );
    CREATE INDEX IX_Manual_SaldosBancos_Fecha ON dbo.Manual_SaldosBancos(FechaSaldo);
END;

-- ---- Acreditaciones de tarjetas por día/razón social (histórico + pendiente) ----
IF OBJECT_ID('dbo.Manual_AcreditacionesTarjetas', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Manual_AcreditacionesTarjetas (
        FechaAcreditacion  DATE           NOT NULL,
        RazonSocialExcel   NVARCHAR(100)  NOT NULL,
        Vendido            DECIMAL(19,2)  NULL,
        Acreditado         DECIMAL(19,2)  NULL,
        Estado             NVARCHAR(20)   NULL,          -- ACREDITADO / PENDIENTE
        _cargadoEn         DATETIME2      NOT NULL CONSTRAINT DF_AcredTj_Fecha DEFAULT SYSDATETIME(),
        _archivoOrigen     NVARCHAR(260)  NULL,
        CONSTRAINT PK_Manual_AcreditacionesTarjetas PRIMARY KEY (FechaAcreditacion, RazonSocialExcel)
    );
    CREATE INDEX IX_Manual_AcredTj_Estado_Fecha ON dbo.Manual_AcreditacionesTarjetas(Estado, FechaAcreditacion);
END;

PRINT 'Tablas de Flujo de Fondos listas.';
