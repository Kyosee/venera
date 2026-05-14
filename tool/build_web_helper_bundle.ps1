param(
  [string]$Output = "build/web-helper-bundle",
  [string]$BaseHref = "/",
  [ValidateSet("Auto", "Always", "Skip")]
  [string]$FlutterBuildMode = "Auto",
  [switch]$SkipFlutterBuild,
  [switch]$ForceFlutterBuild
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
$webBuildStampPath = Join-Path $webBuildPath ".venera-build-stamp.json"
$flutterInputPaths = @(
  (Join-Path $root "pubspec.yaml"),
  (Join-Path $root "pubspec.lock"),
  (Join-Path $root "lib"),
  (Join-Path $root "assets"),
  (Join-Path $root "web/index.html"),
  (Join-Path $root "web/manifest.json"),
  (Join-Path $root "web/flutter_bootstrap.js"),
  (Join-Path $root "web/flutter.js"),
  (Join-Path $root "web/icons"),
  (Join-Path $root "web/favicon.png"),
  (Join-Path $root "web/apple-touch-icon.png"),
  (Join-Path $root "web/venera_runtime.js"),
  (Join-Path $root "web/sqlite3.wasm"),
  (Join-Path $root "web/proxy.php")
)
$legacyWebBuildEntries = @("dist", "node_modules", "public", "src")

function Get-FlutterInputFiles {
  param([string[]]$Paths)

  $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
  foreach ($path in $Paths) {
    if (-not (Test-Path -LiteralPath $path)) {
      continue
    }
    $item = Get-Item -LiteralPath $path -Force
    if ($item.PSIsContainer) {
      foreach ($file in Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue) {
        $files.Add($file)
      }
    } else {
      $files.Add($item)
    }
  }
  return $files | Sort-Object FullName
}

function Get-RelativeFingerprintPath {
  param([System.IO.FileInfo]$File)

  $rootFullPath = [System.IO.Path]::GetFullPath($root).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
  $fileFullPath = [System.IO.Path]::GetFullPath($File.FullName)
  return $fileFullPath.Substring($rootFullPath.Length).Replace('\', '/')
}

function Get-WebBuildFingerprint {
  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.AppendLine("target=lib/main_web.dart")
  [void]$builder.AppendLine("baseHref=$BaseHref")
  foreach ($file in (Get-FlutterInputFiles $flutterInputPaths)) {
    $relative = Get-RelativeFingerprintPath $file
    [void]$builder.AppendLine("$relative|$($file.Length)|$($file.LastWriteTimeUtc.Ticks)")
  }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
    return [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-LatestWriteTimeUtc {
  param([string[]]$Paths)

  $latest = [DateTime]::MinValue
  foreach ($file in (Get-FlutterInputFiles $Paths)) {
    if ($file.LastWriteTimeUtc -gt $latest) {
      $latest = $file.LastWriteTimeUtc
    }
  }
  return $latest
}

function Write-WebBuildStamp {
  param([string]$Fingerprint)

  @{
    version = 1
    baseHref = $BaseHref
    target = "lib/main_web.dart"
    fingerprint = $Fingerprint
    builtAt = (Get-Date).ToUniversalTime().ToString("o")
  } | ConvertTo-Json | Set-Content -LiteralPath $webBuildStampPath -Encoding UTF8
}

function Test-WebBuildFresh {
  param([string]$Fingerprint)

  $mainJsPath = Join-Path $webBuildPath "main.dart.js"
  $indexPath = Join-Path $webBuildPath "index.html"
  if (-not (Test-Path -LiteralPath $mainJsPath) -or -not (Test-Path -LiteralPath $indexPath)) {
    return $false
  }

  if (Test-Path -LiteralPath $webBuildStampPath) {
    try {
      $stamp = Get-Content -LiteralPath $webBuildStampPath -Raw | ConvertFrom-Json
      return $stamp.baseHref -eq $BaseHref `
        -and $stamp.target -eq "lib/main_web.dart" `
        -and $stamp.fingerprint -eq $Fingerprint
    } catch {
      return $false
    }
  } else {
    Write-Host "No build stamp found; using file timestamps once."
  }

  $outputTime = (Get-Item -LiteralPath $mainJsPath).LastWriteTimeUtc
  $inputTime = Get-LatestWriteTimeUtc $flutterInputPaths
  if ($outputTime -ge $inputTime) {
    Write-WebBuildStamp $Fingerprint
    return $true
  }
  return $false
}

function Invoke-FlutterWebBuild {
  param([string]$Fingerprint)

  flutter build web --target lib/main_web.dart --release --base-href $BaseHref --no-wasm-dry-run --no-tree-shake-icons
  if ($LASTEXITCODE -ne 0) {
    throw "flutter build web failed with exit code $LASTEXITCODE"
  }
  Write-WebBuildStamp $Fingerprint
}

function Copy-WebBuild {
  foreach ($entry in Get-ChildItem -LiteralPath $webBuildPath -Force) {
    if ($legacyWebBuildEntries -contains $entry.Name) {
      Write-Host "Skip stale web build entry: $($entry.Name)"
      continue
    }
    Copy-Item -LiteralPath $entry.FullName -Destination $publicPath -Recurse -Force
  }
}

Push-Location $root
try {
  if ($SkipFlutterBuild -and $ForceFlutterBuild) {
    throw "Use either -SkipFlutterBuild or -ForceFlutterBuild, not both."
  }
  if ($SkipFlutterBuild) {
    $FlutterBuildMode = "Skip"
  }
  if ($ForceFlutterBuild) {
    $FlutterBuildMode = "Always"
  }

  $fingerprint = if ($FlutterBuildMode -eq "Skip") { "" } else { Get-WebBuildFingerprint }

  if ($FlutterBuildMode -eq "Skip") {
    Write-Host "Skipping Flutter build because FlutterBuildMode=Skip."
  } elseif (-not (Test-Path $webBuildPath)) {
    Invoke-FlutterWebBuild $fingerprint
  } elseif ($FlutterBuildMode -eq "Always") {
    Invoke-FlutterWebBuild $fingerprint
  } elseif (Test-WebBuildFresh $fingerprint) {
    Write-Host "Reusing fresh build/web. Use -ForceFlutterBuild to rebuild."
  } else {
    Invoke-FlutterWebBuild $fingerprint
  }

  if (-not (Test-Path $webBuildPath)) {
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

  Copy-WebBuild

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

## 快速重新打包

```powershell
.\tool\build_web_helper_bundle.ps1
```

默认会复用新鲜的 `build/web`，避免每次都跑 Flutter 编译。

```powershell
.\tool\build_web_helper_bundle.ps1 -ForceFlutterBuild
```

源码没变但需要强制重建 Flutter Web 时使用。

```powershell
.\tool\build_web_helper_bundle.ps1 -SkipFlutterBuild
```

确认 `build/web` 已经可用时，可以完全跳过新鲜度检查。

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
