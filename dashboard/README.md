# Dashboard Sueldos · Señales

Dashboard estático con filtros que lee `data.json` exportado desde SQL.

## Uso

```powershell
# Refrescar datos + servir
.\scripts\serve_dashboard.ps1 -Refresh

# Solo servir (sin refrescar)
.\scripts\serve_dashboard.ps1

# Solo refrescar (sin servir)
.\scripts\export_dashboard.ps1
```

El navegador se abre solo en `http://localhost:8080/`.

## Estructura

- `index.html` — UI (Chart.js via CDN, filtros, KPIs, 6 gráficos + tabla)
- `data.json` — snapshot exportado de las vistas `vw_Dashboard_*` y tablas `Sueldos_Altas` / `Sueldos_Bajas`. Se regenera con `export_dashboard.ps1`.

## Vistas SQL fuente

- `dbo.vw_Dashboard_NominaMensual_PorCC` — nómina mensual estable desnormalizada por CC
- `dbo.vw_Dashboard_CostoMensual_PorCC` — costo empresa recurrente desnormalizado por CC (prorrateado si hay multi-CC)
- `dbo.vw_Dashboard_NominaActiva_PorCC` — snapshot de activos al último período cerrado

## Filtros

- Período desde/hasta
- Centro de Costo (todos = consolidado)
- Empresa
- Tipo de Trabajo (Cocina / Servicio / Otros)

Los filtros afectan todos los gráficos. KPIs se recalculan en cliente.

## Notas

- "Sucursal" = Centro de Costo (no establecimiento). Las vistas también traen `NombreEstablecimiento` por si se quiere agrupar de otra forma.
- Nómina estable excluye altas y bajas a prueba (<5 días en el mes).
- Costo empresa excluye liquidaciones finales y cuotas de acuerdos por despido.
- Contribuciones patronales: solo disponibles desde 202603, ene/feb 2026 quedan subestimados.
