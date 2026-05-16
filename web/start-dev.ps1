param(
  [switch]$Build,
  [int]$Port = 5173
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

# --- Rust server (optional, required for API) ---
$rustServerRunning = $false
try {
  $null = Invoke-WebRequest -Uri "http://127.0.0.1:3000/api/server-db/comic/sources" -TimeoutSec 2 -UseBasicParsing
  $rustServerRunning = $true
  Write-Host "[OK] Rust server already running at :3000" -ForegroundColor Green
} catch {
  Write-Host "[WARN] Rust server not detected at :3000" -ForegroundColor Yellow
  Write-Host "       Start it separately: cd server && VENERA_WEB_BIND=127.0.0.1:3000 VENERA_WEB_DATA_DIR=./data.venera/webpwa VENERA_WEB_STATIC_DIR=./web/client/dist cargo run"
}

# --- Install deps ---
$clientPath = Join-Path $root "web/client"
if (-not (Test-Path (Join-Path $clientPath "node_modules"))) {
  Write-Host "[...] Installing dependencies..."
  Push-Location $clientPath
  npm ci
  Pop-Location
}

# --- Build (production mode) ---
if ($Build) {
  Write-Host "[...] Building Vue frontend..."
  Push-Location $clientPath
  npm run build
  Pop-Location
  Write-Host "[OK] Build complete: web/client/dist/" -ForegroundColor Green
  Write-Host "       Rust server will serve it at http://127.0.0.1:3000"
  exit 0
}

# --- Dev server ---
Push-Location $clientPath
Write-Host "[...] Starting Vite dev server at http://127.0.0.1:$Port" -ForegroundColor Cyan
Write-Host "       API requests proxy to http://127.0.0.1:3000" -ForegroundColor DarkGray
npm run dev -- --port $Port
Pop-Location
