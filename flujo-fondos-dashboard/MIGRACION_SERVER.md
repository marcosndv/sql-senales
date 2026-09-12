# Migración Flujo de Fondos → Server VPN

Documento para retomar la migración del dashboard `flujo-fondos-dashboard` desde la PC local de Marco al server de VIGIL donde termina la VPN.

## Motivación

Hoy todo el stack corre en la PC local de Marco:

- `FlujoFondos-Server` (Node en `:8089`) — Task Scheduler `at logon`, user `marco`, `LogonType: Interactive`.
- `FlujoFondos-Tunnel` (`cloudflared`) — igual, `at logon` interactivo.
- `FlujoFondos-Refresh` (ingesta Excel + export JSON) — diario 08:00, cada 30min por 14h, requiere VPN VIGIL para llegar a `192.168.10.17\SQLEXPRESS`.

**Problemas:**

1. Depende de que la PC de Marco esté prendida y con sesión iniciada.
2. Si la VPN se cae, el refresh falla con error 26 SQL.
3. Verificado 2026-09-09: server + túnel caídos (exit `3221225786` = Ctrl+C / cierre forzado), `flujo.ripaconsultora.net` sin backend.

Mover el stack al server que ya está en la LAN de VIGIL elimina las 3 dependencias.

## Precondiciones (confirmadas 2026-09-09)

- El server destino corre Windows Server.
- Marco tiene acceso administrativo.
- Google Drive se puede montar (o mover la fuente Excel a una carpeta SMB).

## Datos pendientes para arrancar

- [ ] Hostname / IP del server destino (¿es el mismo `192.168.10.17` que hostea SQL, u otro?).
- [ ] Método de acceso: RDP con qué usuario, desde VPN o LAN directa.

## Plan por fases

### Fase 1 — Preparar el server destino

1. Instalar en el server:
   - Node LTS (mismo mayor que la PC local; hoy `node -v` en la PC dice cuál).
   - Git for Windows.
   - `cloudflared` (`winget install --id Cloudflare.cloudflared` o MSI oficial).
   - PowerShell 7 si no viene con el SO.
2. Montar/mapear Google Drive del team, o mover la fuente Excel a un share SMB accesible.
   - Ruta actual: `G:\.shortcut-targets-by-id\1TNAQJXrS9QVbXV1KoIy__J7pqdp4QsxG\Reportes Consultora Final\07 - GRUPO VIGIL\TESORERIA - GV\`
3. Verificar conectividad SQL sin VPN:
   ```powershell
   & .\sql.ps1 -ShowConnection
   & .\sql.ps1 "SELECT @@VERSION"
   ```
   Si el server está en la misma LAN que `192.168.10.17`, debería resolver sin VPN.

### Fase 2 — Deploy del código

4. `git clone` (o copia) del repo `Sql Señales` al server. Path sugerido: `C:\Apps\SqlSenales`.
5. Regenerar credenciales SQL (DPAPI está atado al par usuario/máquina):
   - Recrear `.sql-helper\connection.json` con los mismos valores.
   - Regenerar `.sql-helper\password.dpapi` desde el server, logueado con el user que va a correr las tareas.
6. Ajustar rutas en `flujo-fondos-dashboard\ingesta_excel.ps1` si Drive quedó con otra letra/UNC.
7. Instalar deps del server Node:
   ```powershell
   cd C:\Apps\SqlSenales\flujo-fondos-dashboard
   npm install
   ```
8. Smoke test manual: correr `ingesta_excel.ps1 -SoloBancos` → validar que llegue a SQL y a Drive.

### Fase 3 — Servicios permanentes

9. **Túnel Cloudflare como Windows Service:**
   ```powershell
   cloudflared service install <token-del-tunel-actual>
   ```
   El token es el mismo que usa la task `FlujoFondos-Tunnel` hoy. Ubicarlo en el config actual o regenerarlo desde el dashboard de Cloudflare (cuenta `m.diaz@vorticespd.com.ar`, sitio `ripaconsultora.net`).
   Una vez activo en el server, el túnel de la PC local queda redundante — apagarlo recién en Fase 4.

10. **Node server como servicio.** Opciones:
    - [nssm](https://nssm.cc/) apuntando a `node.exe server.js` en `flujo-fondos-dashboard/`.
    - `node-windows` (paquete npm).
    Arranque automático, sin dependencia de login.

11. **Refresh como Scheduled Task:**
    - `LogonType: S4U` (corre sin sesión abierta) o cuenta de servicio dedicada.
    - Mismo trigger diario 08:00, cada 30min por 14h, `RestartCount: 2`.
    - Log rotativo — reusar `scripts\scheduled_refresh_flujo.ps1`.

### Fase 4 — Corte controlado

12. Correr en paralelo 2-3 días: server nuevo tomando datos, PC local como fallback.
13. Verificar desde otro dispositivo: `https://flujo.ripaconsultora.net/` responde vía server nuevo.
14. Dar de baja las 3 tareas en la PC local:
    ```powershell
    Unregister-ScheduledTask -TaskName 'FlujoFondos-Server' -Confirm:$false
    Unregister-ScheduledTask -TaskName 'FlujoFondos-Tunnel' -Confirm:$false
    Unregister-ScheduledTask -TaskName 'FlujoFondos-Refresh' -Confirm:$false
    ```
15. Dejar el repo local intacto para desarrollo, pero sin servicios activos.

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|---|---|
| DPAPI password no se puede migrar tal cual | Regenerar en el server con el mismo user que corre las tasks. |
| Excel COM en `ingesta_excel.ps1` requiere Excel instalado | Verificar Office en el server o reemplazar por `ImportExcel` (módulo PowerShell puro). |
| Google Drive Desktop no siempre corre en Server SKUs | Alternativa: mover Excels a un share SMB o usar rclone. |
| Túnel corriendo en 2 lados a la vez rompe routing | Cloudflare balancea entre réplicas, pero es más limpio apagar el viejo en Fase 4. |
| Cuenta de servicio sin permisos a Drive/SMB | Correr con user de dominio con acceso, no LocalSystem. |

## Referencias

- Memoria: `project-flujo-fondos`, `project-flujo-fondos-pendientes`, `reference-cloudflare-account`.
- Código actual: `flujo-fondos-dashboard\` (server, ingesta, export), `scripts\scheduled_refresh_flujo.ps1`.
- Cuenta Cloudflare: `m.diaz@vorticespd.com.ar`.
- Sitio: `flujo.ripaconsultora.net`.

## Checklist de arranque en próxima sesión

- [ ] Confirmar hostname/IP y credenciales RDP del server destino.
- [ ] Ejecutar Fase 1 (instalar prerequisitos).
- [ ] Ejecutar Fase 2 (deploy + smoke test).
- [ ] Ejecutar Fase 3 (servicios).
- [ ] Ejecutar Fase 4 (corte).
