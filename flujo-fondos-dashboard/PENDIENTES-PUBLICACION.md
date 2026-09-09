# Publicación del dashboard — Pasos pendientes

Objetivo: exponer `http://localhost:8089` como `https://flujo.ripaconsultora.net` con autenticación por email (Cloudflare Access), accesible desde cualquier dispositivo de gerencia.

---

## ✅ Ya hecho (automatizado)

- Server local `node server.js` corriendo permanente en `127.0.0.1:8089` (Task Scheduler `FlujoFondos-Server` al iniciar sesión).
- Refresh de datos cada 30 min de 8h a 22h (Task Scheduler `FlujoFondos-Refresh`). Corre `scheduled_refresh_flujo.ps1` que ejecuta ingesta Excel + regeneración de JSON.
- Cliente `cloudflared 2026.8.2` instalado en `C:\Program Files (x86)\cloudflared\cloudflared.exe`.

## ⏳ Pendientes tuyos

### 1. Migrar `ripaconsultora.net` a Cloudflare (10-15 min + espera de propagación)

**Por qué**: hoy el dominio está en GoDaddy (nameservers `ns21/22.domaincontrol.com`). Cloudflare Tunnel + Cloudflare Access **solo funcionan si el dominio usa nameservers de Cloudflare**. No rompe la intranet actual (Cloudflare replica automáticamente el A record de Vercel `216.198.79.1`).

**Pasos**:

1. **Crear cuenta / loguear** en https://dash.cloudflare.com/sign-up
2. En el dashboard: **"+ Add a site"** → escribir `ripaconsultora.net` → plan **Free ($0)**.
3. Cloudflare hace auto-scan de los DNS actuales y muestra:
   - `A ripaconsultora.net → 216.198.79.1` (Vercel — dejar como está)
   - `CNAME www → ripaconsultora.net` (dejar como está)
   - Confirmar **"Continue"**.
4. Cloudflare devuelve **2 nameservers propios** tipo:
   ```
   xxx.ns.cloudflare.com
   yyy.ns.cloudflare.com
   ```
   Copiar los dos.
5. Ir a **GoDaddy**: https://account.godaddy.com/products → click en `ripaconsultora.net` → **DNS** → sección **Nameservers** → **Change** → elegir **"I'll use my own nameservers (advanced)"** → pegar los 2 nameservers de Cloudflare → **Save**.
6. Esperar propagación. Cloudflare te manda mail a `codingwaysar@gmail.com` cuando está activo (usualmente 5-60 min, máximo 24h). Podés ver el estado desde Cloudflare → tu dominio → Overview.

### 2. Habilitar Cloudflare Zero Trust (Access)

**Por qué**: es el módulo que hace la auth por email/SSO delante del túnel.

1. En Cloudflare dashboard → menú izquierdo **"Zero Trust"**.
2. Primera vez pide **crear team name** (ej: `ripaconsultora`). Tu URL de Zero Trust queda `https://ripaconsultora.cloudflareaccess.com`.
3. Plan **Free** hasta 50 usuarios.
4. Método de pago: aunque el plan es free, pide una tarjeta para "verificar". No cobra nada.

### 3. Darme la lista de emails autorizados

Necesito los emails de gerencia + tu email para armar la policy de acceso. Formato:
```
tu-email@…
gerente1@…
gerente2@…
…
```

Con eso armo la policy tipo "solo estos emails entran, todo el resto rechazado".

### 4. Avisar cuando ambos pasos estén hechos

Cuando la propagación de NS termine y hayas creado el team de Zero Trust, avisame acá. Yo hago:
- `cloudflared tunnel login` (te va a abrir el browser una vez para autorizar el túnel contra `ripaconsultora.net`)
- Crear el túnel `flujo-fondos`, config, DNS route `flujo.ripaconsultora.net → localhost:8089`
- Registrar cloudflared como **servicio Windows** (arranca solo con la PC)
- Aplicar la policy de Access con los emails que me pases
- Verificar acceso end-to-end
- Sumar el link a la intranet (`/admin/dashboards`) como card visible para gerencia

## Info útil (por si preguntan)

- **URL final del dashboard**: `https://flujo.ripaconsultora.net`
- **Cómo se autentica gerencia**: al entrar por primera vez, Cloudflare Access les pide su email. Reciben un PIN de un solo uso por mail, lo pegan y quedan logueados por 24h (configurable). No hay password, no hay cuenta que crear.
- **Frescura de datos**: se refresca cada 30 min. Sale la hora de "Últ. actualización" arriba a la izquierda de cada página.
- **Si mi PC se apaga**: el dashboard deja de responder. Cuando prendo y logueo, arranca solo.
- **Costo total**: $0 (dominio ya tenías; Cloudflare Tunnel + Access Free).

## Troubleshooting rápido

- **"Propagación no termina" (>24h)**: verificar en GoDaddy que los nameservers guardaron bien. A veces GoDaddy exige quitar los antiguos primero.
- **Cloudflare no encuentra los nameservers**: correr `Resolve-DnsName ripaconsultora.net -Type NS -Server 8.8.8.8` para chequear si ya cambiaron públicamente.
- **Access no deja entrar a alguien**: agregar su email a la policy en Zero Trust → Access → Applications → flujo-fondos → Policies.
