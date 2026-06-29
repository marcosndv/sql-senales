# =============================================================================
# scripts/serve_dashboard.ps1
# Sirve dashboard/ en http://localhost:8080 usando HttpListener (sin deps).
# Refresca data.json antes de servir si se pasa -Refresh.
# Ctrl+C para parar.
# =============================================================================
[CmdletBinding()]
param(
    [int]$Port = 8080,
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\dashboard')).Path

if ($Refresh) {
    Write-Host "Refrescando data.json ..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'export_dashboard.ps1')
}

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.svg'  = 'image/svg+xml'
    '.png'  = 'image/png'
    '.ico'  = 'image/x-icon'
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()

Write-Host ""
Write-Host "Dashboard listo en http://localhost:$Port/" -ForegroundColor Green
Write-Host "Sirviendo $root"
Write-Host "Ctrl+C para parar."
Write-Host ""

try {
    Start-Process "http://localhost:$Port/"
} catch {
    # ignorar si no se puede abrir el browser
}

try {
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        $req = $ctx.Request
        $res = $ctx.Response

        $relPath = $req.Url.LocalPath.TrimStart('/')
        if ([string]::IsNullOrEmpty($relPath)) { $relPath = 'index.html' }
        $fullPath = Join-Path $root $relPath

        # Bloquear path traversal
        if (-not $fullPath.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            $res.StatusCode = 403
            $res.Close()
            continue
        }

        if (Test-Path $fullPath -PathType Leaf) {
            $ext = [System.IO.Path]::GetExtension($fullPath).ToLower()
            $res.ContentType = $mime[$ext]
            if (-not $res.ContentType) { $res.ContentType = 'application/octet-stream' }
            $bytes = [System.IO.File]::ReadAllBytes($fullPath)
            $res.ContentLength64 = $bytes.Length
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            Write-Host "200  $relPath" -ForegroundColor DarkGray
        } else {
            $res.StatusCode = 404
            $msg = [System.Text.Encoding]::UTF8.GetBytes("404 - $relPath")
            $res.OutputStream.Write($msg, 0, $msg.Length)
            Write-Host "404  $relPath" -ForegroundColor Yellow
        }
        $res.Close()
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
