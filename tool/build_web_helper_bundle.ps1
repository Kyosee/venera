param(
  [string]$Output = "build/web-helper-bundle",
  [string]$BaseHref = "/",
  [switch]$SkipFlutterBuild
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$outputPath = if ([System.IO.Path]::IsPathRooted($Output)) {
  $Output
} else {
  Join-Path $root $Output
}
$webBuildPath = Join-Path $root "build/web"
$helperPath = Join-Path $root "web_helper"
$publicPath = Join-Path $outputPath "public"

Push-Location $root
try {
  if (-not $SkipFlutterBuild) {
    flutter build web --target lib/main_web.dart --release --base-href $BaseHref --no-wasm-dry-run --no-tree-shake-icons
    if ($LASTEXITCODE -ne 0) {
      throw "flutter build web failed with exit code $LASTEXITCODE"
    }
  } elseif (-not (Test-Path $webBuildPath)) {
    throw "build/web does not exist. Remove -SkipFlutterBuild or build Flutter Web first."
  }

  if (Test-Path $outputPath) {
    Remove-Item -LiteralPath $outputPath -Recurse -Force
  }
  New-Item -ItemType Directory -Path $outputPath | Out-Null
  New-Item -ItemType Directory -Path $publicPath | Out-Null

  Copy-Item -LiteralPath (Join-Path $helperPath "server.js") -Destination $outputPath
  Copy-Item -LiteralPath (Join-Path $helperPath "package.json") -Destination $outputPath
  Copy-Item -LiteralPath (Join-Path $helperPath "Dockerfile") -Destination $outputPath
  Copy-Item -LiteralPath (Join-Path $helperPath "compose.yaml") -Destination $outputPath
  Copy-Item -LiteralPath (Join-Path $helperPath "entrypoint.sh") -Destination $outputPath

  # Include the Rust fetch sidecar source (Dockerfile builds it from this dir).
  $sidecarSource = Join-Path $helperPath "rust-fetch"
  $sidecarTarget = Join-Path $outputPath "rust-fetch"
  New-Item -ItemType Directory -Path $sidecarTarget | Out-Null
  Copy-Item -Path (Join-Path $sidecarSource "Cargo.toml") -Destination $sidecarTarget
  Copy-Item -Path (Join-Path $sidecarSource "rust-toolchain.toml") -Destination $sidecarTarget
  if (Test-Path (Join-Path $sidecarSource "Cargo.lock")) {
    Copy-Item -Path (Join-Path $sidecarSource "Cargo.lock") -Destination $sidecarTarget
  }
  Copy-Item -Path (Join-Path $sidecarSource "src") -Destination $sidecarTarget -Recurse
  Copy-Item -Path (Join-Path $sidecarSource ".cargo") -Destination $sidecarTarget -Recurse

  Copy-Item -Path (Join-Path $webBuildPath "*") -Destination $publicPath -Recurse

  $readme = @'
# Venera Web + Web Helper 部署包

这个目录已经把 Flutter Web 静态文件和 Web Helper 后端放在一起。
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
node server.js
```

## 目录说明

```text
public/       Flutter Web 静态文件
server.js     Web Helper 后端，同时托管 public/
compose.yaml  NAS/Docker Compose 部署入口
browser-data/ 运行后自动生成，保存 helper 浏览器数据和 cookie jar
```
'@
  Set-Content -LiteralPath (Join-Path $outputPath "README.md") -Value $readme -Encoding UTF8

  Write-Host "Bundle created at $outputPath"
} finally {
  Pop-Location
}
