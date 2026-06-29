# Sql Señales

Análisis de recibos del ERP "Señales" sobre la base `ERP_Senales`.

## Conexión a la base

**El servidor es REMOTO:** `192.168.10.17\SQLEXPRESS`, base `ERP_Senales`, usuario `bi_gateway`. No hay instancia local de SQL Server — no buscarla con `Get-Service` ni `sqlcmd -L`.

Para ejecutar SQL, usar el helper `sql.ps1` de la raíz:

```powershell
& .\sql.ps1 "SELECT TOP 10 * FROM sys.databases"
& .\sql.ps1 -File .\sql\mi_consulta.sql
& .\sql.ps1 -Database master "SELECT @@VERSION"
& .\sql.ps1 -Format Json "SELECT name FROM sys.databases"
& .\sql.ps1 -ShowConnection
```

Formatos: `Table` (default), `List`, `Json`, `Csv`, `Raw`. Config en `.sql-helper\connection.json` + password DPAPI en `.sql-helper\password.dpapi`.

## Arquitectura de datos

`192.168.10.17\SQLEXPRESS / ERP_Senales` es el **destino**, no la fuente. Recibe copias de tablas DBF que provienen del servidor del ERP original. Cuando se dice "arreglaron X en el sistema" se refiere al ERP origen — para que se vea acá hay que volver a copiar las DBF. Antes de cualquier análisis post-actualización, confirmar que el ETL ya corrió (chequear `MAX(_fecha_carga)` en tablas raw, p.ej. `EMPR0001.SUELDOS_EMPLEADOSXCENTROCOSTO._fecha_carga`).

## Vistas y tablas clave

- `dbo.vw_Sueldos_ReciboDetalle_Normalizado` — detalle de recibos con `NombreNormalizado` y `Categoria`.
- `dbo.vw_Sueldos_Nomina_Activa` — nómina deduplicada al último período mensual estable.
- `dbo.vw_Sueldos_NominaMensual_Estable` — dotación mensual excluyendo bajas con < 5 días.
- `dbo.vw_Sueldos_CostoEmpresaMensual` — costo recurrente (HABER_REMUN + SAC + NO_REMUN + CONTRIBUCION_PATRONAL).
- `dbo.Sueldos_Bajas` / `dbo.Sueldos_Altas` — eventos inferidos desde recibos (NO desde la tabla oficial de contratos).

## Reglas de análisis

- **Bajas / despidos / renuncias:** NO usar `vw_Sueldos_ContratosXEmpleado` (datos incompletos). Inferir desde `vw_Sueldos_ReciboDetalle_Normalizado` con `Categoria='LIQUIDACION_FINAL'` y `VALORTOTAL > 0`. Misma lógica para FALLECIMIENTO / FUERZA_MAYOR / DESPIDO_SIN_CAUSA.
- **Nómina deduplicada:** `vw_Sueldos_Nomina` trae una fila por contrato. Usar `vw_Sueldos_Nomina_Activa` o `ROW_NUMBER() OVER (PARTITION BY Empresa, IdEmpleado ORDER BY ContratoNro DESC)` con `rn=1`.
- **Mes económico vs administrativo:** `SUELDOS_LIQUIDACIONES.PERIODO` es el mes de corrida, no siempre el mes real. Para liquidaciones finales, parsear `COMENTARIO` vía `vw_Sueldos_Liquidaciones_MesEconomico` (regla: si dice "final", el `PeriodoEconomico` sale del COMENTARIO).

## Tablas por empresa

Cada empresa (`EMPR0001..EMPR0014`, `EMPR7000`) tiene su esquema con `SUELDOS_EMPLEADOS`, `SUELDOS_LIQUIDACIONES`, `SUELDOS_CONCEPTOS`, etc. Las vistas `dbo.vw_Sueldos_*` consolidan todas.
