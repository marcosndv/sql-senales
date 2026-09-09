-- ============================================================
-- 08_impositivo.sql
-- Tabla + vistas para deudas impositivas sueltas (IMPOSITIVO)
-- Fuente: PRESTAMOS, PLANES Y DEUDAS.xlsx hoja IMPOSITIVO
-- Filtro relevante: ESTADO='PENDIENTE' (no PAGO ni PLAN DE PAGO)
-- ============================================================

IF OBJECT_ID('dbo.Manual_Impositivo', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Manual_Impositivo (
        Id                INT IDENTITY(1,1) NOT NULL,
        RazonSocialExcel  NVARCHAR(100) NOT NULL,
        Grupo             NVARCHAR(50)  NULL,        -- F-931, IVA, IIBB, SICORE, etc.
        Concepto          NVARCHAR(100) NULL,
        Subconcepto       NVARCHAR(50)  NULL,
        Periodo           DATE          NULL,
        FechaVencimiento  DATE          NULL,
        Importe           DECIMAL(19,2) NULL,
        Estado            NVARCHAR(30)  NULL,        -- PAGO / PLAN DE PAGO / PENDIENTE
        Condicion         NVARCHAR(30)  NULL,        -- VENCIDO
        DiasMora          INT           NULL,
        Registracion      NVARCHAR(50)  NULL,
        OrdenPago         NVARCHAR(50)  NULL,
        Observacion       NVARCHAR(500) NULL,
        _cargadoEn        DATETIME2     NOT NULL CONSTRAINT DF_Impositivo_Fecha DEFAULT SYSDATETIME(),
        _archivoOrigen    NVARCHAR(260) NULL,
        CONSTRAINT PK_Manual_Impositivo PRIMARY KEY (Id)
    );
    CREATE INDEX IX_Manual_Impositivo_Estado ON dbo.Manual_Impositivo(Estado);
    CREATE INDEX IX_Manual_Impositivo_RS     ON dbo.Manual_Impositivo(RazonSocialExcel);
END;
GO

-- ============================================================
-- vw_FlujoFondos_Impositivo
-- Deudas impositivas sueltas pendientes de pago, con Empresa mapeada.
-- Filtro: ESTADO='PENDIENTE' AND Importe > 0.
-- Los sin FechaVencimiento se acumulan en hoy (misma lógica que proyectado).
-- ============================================================

CREATE OR ALTER VIEW dbo.vw_FlujoFondos_Impositivo AS
SELECT
    i.Id,
    i.RazonSocialExcel                                    AS EmpresaExcel,
    COALESCE(m.Empresa, 'SIN_EMPRESA')                    AS Empresa,
    COALESCE((SELECT NombreEmpresa FROM dbo.Config_Empresas ce WHERE ce.Empresa = m.Empresa), i.RazonSocialExcel) AS NombreEmpresa,
    i.Grupo,
    i.Concepto,
    i.Subconcepto,
    i.Periodo,
    i.FechaVencimiento,
    ISNULL(i.FechaVencimiento, CAST(GETDATE() AS DATE))   AS FechaVto,
    i.Importe,
    i.Estado,
    i.Condicion,
    i.DiasMora,
    i.Observacion
FROM dbo.Manual_Impositivo i
LEFT JOIN dbo.Config_MapeoRazonSocial m ON m.RazonSocialExcel = i.RazonSocialExcel
WHERE i.Estado = 'PENDIENTE' AND ISNULL(i.Importe, 0) > 0;
GO
