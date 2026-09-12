-- ============================================================
-- Mapeo (marca, establecimiento, comercio) de Datapos → Empresa.
--
-- Reemplaza la fuente Excel "ACREDITACIONES TARJETAS" del cashflow
-- por la ingesta automatizada de Datapos (datapos.liquidacion).
--
-- Poblado inicial en base al mapeo actual (Config_MapeoRazonSocial)
-- por substring del comercio. Los casos sin match automático
-- (CASA VIGIL, MIL SUELOS) quedan con Empresa = NULL hasta que se
-- confirme la asignación; caen a 'SIN_EMPRESA' en el cashflow.
-- ============================================================

IF OBJECT_ID('dbo.Config_MapeoEstablecimientoDatapos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Config_MapeoEstablecimientoDatapos (
        Marca            nvarchar(60)   NOT NULL,
        Establecimiento  bigint         NOT NULL,
        Comercio         nvarchar(200)  NOT NULL,
        Empresa          nvarchar(20)   NULL,
        _cargadoEn       datetime2      NOT NULL CONSTRAINT DF_MapeoEstDatapos_Fecha DEFAULT SYSDATETIME(),
        CONSTRAINT PK_MapeoEstDatapos PRIMARY KEY (Marca, Establecimiento, Comercio)
    );
END;

-- MERGE idempotente. Actualiza Empresa si cambió; no toca filas que
-- alguien haya editado a mano en el server (solo si difieren, hace UPDATE).
;WITH src(Marca, Establecimiento, Comercio, Empresa) AS (
    SELECT * FROM (VALUES
        ('CABAL',     66241570001, 'CASA EL ENEMIGO',           'EMPR0001'),
        ('FIRSTDATA',    19994968, 'CASA EL ENEMIGO',           'EMPR0001'),
        ('FIRSTDATA',    23246537, 'CHACHINGO CRAFT BEER',      'EMPR0002'),
        ('FIRSTDATA',    25970093, 'CASA VIGIL',                 NULL),
        ('FIRSTDATA',    25970093, 'ORIGINAL WINERY SA EZEIZA', 'EMPR0001'),
        ('FIRSTDATA',    28549053, 'BUR 22',                    'EMPR0005'),
        ('FIRSTDATA',    30647011, 'MIL SUELOS',                 NULL),
        ('FIRSTDATA',    31254433, 'CHIPIRONES',                'EMPR0018'),
        ('FIRSTDATA',    31321559, 'PULTUN',                    'EMPR0022'),
        ('FIRSTDATA',    31321559, 'PULTUN SAS',                'EMPR0022'),
        ('FIRSTDATA',    31414462, 'PUERTO ESTANCIA SAS',       'EMPR0024'),
        ('FIRSTDATA',    31480434, 'ORIGINAL WINERY',           'EMPR0001'),
        ('FIRSTDATA',    31491540, 'BUR 22',                    'EMPR0005'),
        ('FIRSTDATA',    31491776, 'CHACHINGO CRAFT BEER',      'EMPR0002'),
        ('FIRSTDATA',    31495053, 'LOS VALIENTES',             'EMPR0006'),
        ('FIRSTDATA',    32176661, 'ORIGINAL WINERY',           'EMPR0001'),
        ('FIRSTDATA',    32382191, 'CHACHINGO CRAFT BEER',      'EMPR0002'),
        ('GETNET',         131008, 'LOS VALIENTES',             'EMPR0006'),
        ('GETNET',         131065, 'LOS VALIENTES',             'EMPR0006'),
        ('GETNET',         131092, 'LOS VALIENTES',             'EMPR0006'),
        ('GETNET',         131132, 'LOS VALIENTES',             'EMPR0006'),
        ('GETNET',         132780, 'BUR 22',                    'EMPR0005'),
        ('GETNET',         132844, 'CHIPIRONES',                'EMPR0018'),
        ('GETNET',         147800, 'BDP BINGO FUEL WINES',      'EMPR0012'),
        ('GETNET',         198233, 'CHIPIRONES',                'EMPR0018'),
        ('GETNET',         199401, 'CHACHINGO CRAFT BEER',      'EMPR0002'),
        ('GETNET',         220099, 'CHACHINGO CRAFT BEER',      'EMPR0002'),
        ('PRISMA',       72660921, 'LOS VALIENTES',             'EMPR0006'),
        ('PRISMA',       72660954, 'LOS VALIENTES',             'EMPR0006'),
        ('PRISMA',       81667461, 'LOS VALIENTES',             'EMPR0006')
    ) v(Marca, Establecimiento, Comercio, Empresa)
)
MERGE dbo.Config_MapeoEstablecimientoDatapos AS t
USING src AS s
   ON t.Marca = s.Marca
  AND t.Establecimiento = s.Establecimiento
  AND t.Comercio = s.Comercio
WHEN MATCHED AND ISNULL(t.Empresa, '') <> ISNULL(s.Empresa, '')
    THEN UPDATE SET Empresa = s.Empresa
WHEN NOT MATCHED BY TARGET
    THEN INSERT (Marca, Establecimiento, Comercio, Empresa)
         VALUES (s.Marca, s.Establecimiento, s.Comercio, s.Empresa);

PRINT 'Config_MapeoEstablecimientoDatapos lista.';
