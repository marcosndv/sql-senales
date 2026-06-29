# =============================================================================
# scripts/publish_dashboard.ps1
# Copia el dashboard al repo de publicacion (Cloudflare Pages) y pushea.
#
# Uso tipico:
#   .\scripts\publish_dashboard.ps1 -RepoPath ..\sueldos-dashboard -Refresh
#
# Hace:
#   1. (opcional) Refresca data.json corriendo export_dashboard.ps1.
#   2. Copia dashboard\index.html y dashboard\data.json al repo destino.
#   3. git add + commit + push. Cloudflare Pages detecta el push y deploya.
# =============================================================================
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$RepoPath,

    [switch]$Refresh,

    [string]$CommitMessage = ("Update dashboard data " + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
)

$ErrorActionPreference = 'Stop'

# Validar repo destino
$RepoPath = (Resolve-Path $RepoPath).Path
if (-not (Test-Path (Join-Path $RepoPath '.git'))) {
    throw "El path '$RepoPath' no es un repo git. Cloneá primero el repo del dashboard ahí."
}

# Refresh opcional
if ($Refresh) {
    Write-Host "Refrescando data.json..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'export_dashboard.ps1')
}

# Copiar archivos
$srcDir = Join-Path $PSScriptRoot '..\dashboard'
$files  = @('index.html', 'data.json')
foreach ($f in $files) {
    $src = Join-Path $srcDir $f
    $dst = Join-Path $RepoPath $f
    if (-not (Test-Path $src)) {
        throw "No existe $src"
    }
    Copy-Item $src $dst -Force
    Write-Host "  copiado: $f" -ForegroundColor DarkGray
}

# Git push
Push-Location $RepoPath
try {
    git add index.html data.json
    if ($LASTEXITCODE -ne 0) { throw "git add fallo (codigo $LASTEXITCODE)" }
    $diff = git diff --cached --name-only
    if (-not $diff) {
        Write-Host "Sin cambios para publicar." -ForegroundColor Yellow
        return
    }
    git commit -m $CommitMessage
    if ($LASTEXITCODE -ne 0) { throw "git commit fallo. Configura tu identidad con: git config --global user.email/user.name" }
    git push
    if ($LASTEXITCODE -ne 0) { throw "git push fallo (codigo $LASTEXITCODE)" }
    Write-Host ""
    Write-Host "Publicado. Cloudflare Pages deploya en ~30s." -ForegroundColor Green
} finally {
    Pop-Location
}
