-- ============================================================
-- vw_FlujoFondos_Proyectado
-- Movimientos esperados día a día. Horizonte: 120 días desde hoy.
-- Los vencimientos pasados se acumulan en la fecha "hoy" (rojo).
-- ============================================================

CREATE OR ALTER VIEW dbo.vw_FlujoFondos_Proyectado AS
WITH Hoy AS (SELECT CAST(GETDATE() AS DATE) AS D),
Base AS (
    -- Entradas: acreditaciones de tarjetas PENDIENTES desde Datapos.
    -- Reemplaza la ex-fuente dbo.Manual_AcreditacionesTarjetas (Excel manual).
    -- "Pendiente" = fecha de acreditación >= hoy (equivalente al Estado='PENDIENTE'
    -- del Excel; Datapos trae siempre la fecha de acreditación real).
    SELECT
        dl.fecha                                       AS Fecha,
        COALESCE(m.Empresa, 'SIN_EMPRESA')             AS Empresa,
        dl.comercio                                    AS RazonSocial,
        'ENTRADA'                                      AS Tipo,
        'Tarjetas'                                     AS Origen,
        'Acreditación tarjeta pendiente'               AS Concepto,
        CONCAT(dl.marca, ' · ', dl.tarjeta, ' · liq ', dl.liq_nro) AS Detalle,
        dl.t_acreditado                                AS Importe,
        'DATAPOS_LIQUIDACION'                          AS FuenteTabla
    FROM datapos.liquidacion dl
    LEFT JOIN dbo.Config_MapeoEstablecimientoDatapos m
        ON m.Marca = dl.marca
       AND m.Establecimiento = dl.establecimiento
       AND m.Comercio = dl.comercio
    WHERE dl.fecha >= CAST(GETDATE() AS DATE)
      AND dl.t_acreditado > 0

    UNION ALL

    -- Entradas: cheques de terceros en cartera (por fecha de vencimiento)
    SELECT
        CAST(ct.FechaVencimiento AS DATE)              AS Fecha,
        ct.Empresa                                     AS Empresa,
        NULL                                           AS RazonSocial,
        'ENTRADA'                                      AS Tipo,
        'Cheques terceros'                             AS Origen,
        'Cheque tercero a cobrar'                      AS Concepto,
        CONCAT('N° ', ct.NUMERO, ' - ', ct.EMISOR)     AS Detalle,
        ct.IMPORTE                                     AS Importe,
        'vw_ChequesTerceros_EnCartera'                 AS FuenteTabla
    FROM dbo.vw_ChequesTerceros_EnCartera ct
    WHERE ct.TipoBase = 'OFICIAL'
      AND ct.IMPORTE > 0
      AND ct.FechaVencimiento IS NOT NULL

    UNION ALL

    -- Entradas: facturas a cobrar de clientes (por fecha de vencimiento)
    -- Se excluyen las > 36 meses (arrastres pre-2023) y las NC (SaldoPendiente < 0).
    SELECT
        CAST(COALESCE(vc.FechaVencimiento, vc.FECHA) AS DATE) AS Fecha,
        vc.Empresa                                     AS Empresa,
        NULL                                           AS RazonSocial,
        'ENTRADA'                                      AS Tipo,
        'Facturas a cobrar'                            AS Origen,
        'Factura a cobrar'                             AS Concepto,
        CONCAT(vc.RazonSocial, ' - ', vc.NumeroCompleto) AS Detalle,
        vc.SaldoPendiente                              AS Importe,
        'vw_CtaCte_Clientes'                           AS FuenteTabla
    FROM dbo.vw_CtaCte_Clientes vc
    WHERE vc.TipoBase = 'OFICIAL'
      AND vc.SaldoPendiente > 0
      AND vc.FECHA >= DATEADD(month, -36, GETDATE())

    UNION ALL

    -- Salidas: cheques propios diferidos por pagar
    SELECT
        CAST(cp.FechaPagoDiferido AS DATE)             AS Fecha,
        cp.Empresa                                     AS Empresa,
        NULL                                           AS RazonSocial,
        'SALIDA'                                       AS Tipo,
        'Cheques propios'                              AS Origen,
        'Cheque propio diferido'                       AS Concepto,
        CONCAT('N° ', cp.NumeroCheque, ' - ', cp.OrdenPago) AS Detalle,
        cp.Importe                                     AS Importe,
        'vw_ChequesPropios_Pendientes'                 AS FuenteTabla
    FROM dbo.vw_ChequesPropios_Pendientes cp
    WHERE cp.TipoBase = 'OFICIAL'
      AND cp.Importe > 0
      AND cp.FechaPagoDiferido IS NOT NULL

    UNION ALL

    -- Salidas: facturas pendientes de proveedores
    SELECT
        CAST(COALESCE(vp.FechaVencimiento, vp.FECHA) AS DATE) AS Fecha,
        vp.Empresa                                     AS Empresa,
        NULL                                           AS RazonSocial,
        'SALIDA'                                       AS Tipo,
        'Facturas proveedores'                         AS Origen,
        'Factura pendiente'                            AS Concepto,
        CONCAT(vp.RazonSocial, ' - ', vp.NumeroCompleto) AS Detalle,
        vp.SaldoPendiente                              AS Importe,
        'vw_CtaCte_Proveedores'                        AS FuenteTabla
    FROM dbo.vw_CtaCte_Proveedores vp
    WHERE vp.TipoBase = 'OFICIAL'
      AND vp.SaldoPendiente > 0

    UNION ALL

    -- Salidas: cuotas de préstamos bancarios y planes ARCA
    SELECT
        CAST(fp.FechaVto AS DATE)                              AS Fecha,
        fp.Empresa                                             AS Empresa,
        NULL                                                   AS RazonSocial,
        'SALIDA'                                               AS Tipo,
        fp.Origen                                              AS Origen,   -- 'Préstamos' | 'Planes ARCA'
        CONCAT(fp.Origen, ' - cuota ', ISNULL(fp.NroCuota, 0)) AS Concepto,
        CONCAT(fp.EntidadFinanciera, ' - ',
               ISNULL(NULLIF(fp.Concepto,''), fp.NumeroOrigen)) AS Detalle,
        fp.ImporteCuota                                        AS Importe,
        'vw_FlujoFondos_Prestamos'                             AS FuenteTabla
    FROM dbo.vw_FlujoFondos_Prestamos fp
    WHERE fp.FechaVto IS NOT NULL

    UNION ALL

    -- Salidas: deudas impositivas sueltas pendientes (IMPOSITIVO — no PAGO ni PLAN DE PAGO).
    SELECT
        i.FechaVto                                            AS Fecha,
        i.Empresa                                             AS Empresa,
        NULL                                                  AS RazonSocial,
        'SALIDA'                                              AS Tipo,
        'Impositivo'                                          AS Origen,
        CONCAT('Deuda impositiva - ', ISNULL(i.Grupo,'')) AS Concepto,
        CONCAT(i.Grupo, ' ', ISNULL(i.Subconcepto,''),
               CASE WHEN i.Periodo IS NOT NULL
                    THEN ' - ' + FORMAT(i.Periodo, 'yyyy-MM') ELSE '' END) AS Detalle,
        i.Importe                                             AS Importe,
        'vw_FlujoFondos_Impositivo'                           AS FuenteTabla
    FROM dbo.vw_FlujoFondos_Impositivo i
    WHERE i.FechaVto IS NOT NULL
)
SELECT
    -- Los vencidos se acumulan en "hoy" para no perderlos del proyectado
    CASE WHEN b.Fecha < h.D THEN h.D ELSE b.Fecha END          AS Fecha,
    CASE WHEN b.Fecha < h.D THEN 1 ELSE 0 END                  AS EsVencido,
    b.Fecha                                                     AS FechaOriginal,
    b.Empresa,
    COALESCE((SELECT NombreEmpresa FROM dbo.Config_Empresas ce WHERE ce.Empresa = b.Empresa), b.Empresa) AS NombreEmpresa,
    b.RazonSocial,
    b.Tipo,
    b.Origen,
    b.Concepto,
    b.Detalle,
    b.Importe,
    CASE WHEN b.Tipo = 'ENTRADA' THEN b.Importe ELSE -b.Importe END AS ImporteFirmado,
    b.FuenteTabla,
    DATEDIFF(day, h.D, b.Fecha)                                AS DiasAlVencimiento
FROM Base b
CROSS JOIN Hoy h
WHERE b.Fecha IS NOT NULL
  AND b.Fecha <= DATEADD(day, 120, h.D);
