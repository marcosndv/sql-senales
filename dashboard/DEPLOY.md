# Deploy a Cloudflare Pages

Guía de setup inicial (una sola vez, ~20 min) y workflow de actualización (~30 seg cada vez).

## Setup inicial

### 1. Crear repo privado en GitHub

- Nombre sugerido: `sueldos-dashboard`
- **Visibility: Private** (importante — el JSON tiene CUILs y sueldos)
- Sin README, sin .gitignore (lo agregamos después)

### 2. Clonarlo al lado del proyecto

```powershell
cd "C:\Users\marco\OneDrive\Documentos\Desarrollos Claude"
git clone https://github.com/<usuario>/sueldos-dashboard.git
```

Quedará `C:\Users\marco\OneDrive\Documentos\Desarrollos Claude\sueldos-dashboard\`.

### 3. Primera publicación

Desde la carpeta del proyecto Sql Señales:

```powershell
.\scripts\publish_dashboard.ps1 -RepoPath ..\sueldos-dashboard -Refresh
```

Esto refresca `data.json`, lo copia al repo junto con `index.html`, commitea y pushea.

### 4. Conectar Cloudflare Pages al repo

1. Entrá a [dash.cloudflare.com](https://dash.cloudflare.com/) → **Workers & Pages** → **Create application** → **Pages** → **Connect to Git**.
2. Autorizá GitHub y elegí el repo `sueldos-dashboard`.
3. **Build settings**: dejalo todo vacío (no hay build).
   - Framework preset: **None**
   - Build command: (vacío)
   - Build output directory: `/`
4. **Deploy**. En 30 segundos te da una URL `sueldos-dashboard.pages.dev`.

### 5. Proteger con Cloudflare Access

1. En el dashboard de Cloudflare → **Zero Trust** → **Access** → **Applications** → **Add application** → **Self-hosted**.
2. Application domain: `sueldos-dashboard.pages.dev`.
3. **Add policy**:
   - Action: **Allow**
   - Include: **Emails** → agregás los emails autorizados (el del cliente, el tuyo, etc.).
4. **Save**. Listo — al entrar te pide email + magic link.

## Workflow de actualización

Cada vez que querés publicar datos nuevos:

```powershell
.\scripts\publish_dashboard.ps1 -RepoPath ..\sueldos-dashboard -Refresh
```

- `-Refresh` corre el export contra SQL antes de publicar (omitilo si ya está actualizado).
- El script commitea con timestamp y pushea.
- Cloudflare Pages deploya automáticamente en ~30 segundos.

## Notas

- El cliente sigue viendo la URL `sueldos-dashboard.pages.dev` — solo cambia el contenido.
- Si querés revocar un email, lo sacás del policy en Cloudflare Access.
- Si querés un dominio propio (ej. `sueldos.tuempresa.com`), lo agregás en Pages → Custom Domains (gratis, solo requiere apuntar el DNS).
