param(
  [string]$Output = "build/web-helper-bundle",
  [switch]$SkipFrontendBuild
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$outputPath = if ([System.IO.Path]::IsPathRooted($Output)) {
  $Output
} else {
  Join-Path $root $Output
}
$frontendPath = Join-Path $root "web/client"
$webBuildPath = Join-Path $root "build/web-vue"
$helperPath = Join-Path $root "web/server"
$publicPath = Join-Path $outputPath "public"

function Reset-Directory {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path | Out-Null
    return
  }

  foreach ($entry in Get-ChildItem -LiteralPath $Path -Force) {
    Remove-Item -LiteralPath $entry.FullName -Recurse -Force
  }
}

function Invoke-WebFrontendBuild {
  if (-not (Test-Path -LiteralPath (Join-Path $frontendPath "package.json"))) {
    throw "web/client/package.json not found"
  }

  Write-Host "Building Vue web frontend..."
  Push-Location $frontendPath
  try {
    npm ci --silent
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }

    npm run build
    if ($LASTEXITCODE -ne 0) { throw "npm run build failed" }
  } finally {
    Pop-Location
  }
}

function Copy-WebBuild {
  robocopy $webBuildPath $publicPath /MIR /NFL /NDL /NJH /NJS /NC /NS /NP
  if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed with exit code $LASTEXITCODE"
  }
}

Push-Location $root
try {
  if ($SkipFrontendBuild) {
    Write-Host "Skipping web/client build."
  } else {
    Invoke-WebFrontendBuild
  }

  if (-not (Test-Path -LiteralPath $webBuildPath)) {
    throw "build/web-vue does not exist. Remove -SkipFrontendBuild or build web/client first."
  }

  if (-not (Test-Path -LiteralPath $outputPath)) {
    New-Item -ItemType Directory -Path $outputPath | Out-Null
  }

  Copy-Item -LiteralPath (Join-Path $helperPath "server.js") -Destination $outputPath
  Copy-Item -LiteralPath (Join-Path $helperPath "package.json") -Destination $outputPath
  Copy-Item -LiteralPath (Join-Path $helperPath "Dockerfile") -Destination $outputPath
  Copy-Item -LiteralPath (Join-Path $helperPath "compose.yaml") -Destination $outputPath
  Copy-Item -LiteralPath (Join-Path $helperPath "entrypoint.sh") -Destination $outputPath

  $sidecarSource = Join-Path $helperPath "rust-fetch"
  $sidecarTarget = Join-Path $outputPath "rust-fetch"
  Reset-Directory $sidecarTarget
  Copy-Item -LiteralPath (Join-Path $sidecarSource "Cargo.toml") -Destination $sidecarTarget
  Copy-Item -LiteralPath (Join-Path $sidecarSource "rust-toolchain.toml") -Destination $sidecarTarget
  if (Test-Path -LiteralPath (Join-Path $sidecarSource "Cargo.lock")) {
    Copy-Item -LiteralPath (Join-Path $sidecarSource "Cargo.lock") -Destination $sidecarTarget
  }
  Copy-Item -LiteralPath (Join-Path $sidecarSource "src") -Destination $sidecarTarget -Recurse
  Copy-Item -LiteralPath (Join-Path $sidecarSource ".cargo") -Destination $sidecarTarget -Recurse

  Copy-WebBuild

  $readme = @'
# Venera Web + Web Helper 部署包

这个目录已经把 Vue Web 静态文件和 Web Helper 后端放在一起。
部署后只需要访问同一个地址，例如 `http://<nas-host>:60098/`。
Web 端会使用同源 helper，不需要再单独填写 helper 地址。

## Docker Compose

```powershell
docker compose up -d --build
```

然后打开：

```text
http://<nas-host>:60098/
```

## Node.js

```powershell
npm install --omit=dev
$env:PORT="60098"
$env:VENERA_STATIC_DIR="./public"
$env:VENERA_BROWSER_DATA_DIR="./browser-data"
$env:VENERA_COOKIE_JAR_PATH="./browser-data/helper-cookies.json"
$env:VENERA_SERVER_DATA_DIR="./server-data"
node server.js
```

## 快速重新打包

```powershell
.\tool\build_web/server_bundle.ps1
```

默认会重新构建 `web/client` 并同步到 `public/`。

```powershell
.\tool\build_web/server_bundle.ps1 -SkipFrontendBuild
```

确认 `build/web-vue` 已经可用时，可以跳过前端构建。

## 目录说明

```text
public/       Vue Web 静态文件
server.js     Web Helper 后端，同时托管 public/
compose.yaml  NAS/Docker Compose 部署入口
browser-data/ 运行后自动生成，保存 helper 浏览器数据和 cookie jar
server-data/  运行后自动生成，保存 WebDAV 配置和服务端用户数据库
```
'@
  Set-Content -LiteralPath (Join-Path $outputPath "README.md") -Value $readme -Encoding UTF8

  Write-Host "Bundle created at $outputPath"
} finally {
  Pop-Location
}
