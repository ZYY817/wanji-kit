# scripts/package.ps1 —— release 打包一条龙：
#   1) flutter build windows --release
#   2) 从 VC++ CRT redist 目录（VCToolsRedistDir 的等价物：
#      <VS>\VC\Redist\MSVC\<ver>\x64\Microsoft.VC*.CRT）把
#      msvcp140 / vcruntime140 / vcruntime140_1 拷进 Release\——
#      目标机缺这三个 dll 时双击 exe 直接缺 dll 报错起不来
#   3) 整目录打 zip → dist\wanji-kit-v<Version>-windows-x64.zip
#
# 用法：powershell -File scripts/package.ps1 [-Version 0.3] [-SkipBuild]
param(
  [string]$Version = "0.3",
  [switch]$SkipBuild
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app  = Join-Path $root 'app'
$rel  = Join-Path $app 'build\windows\x64\runner\Release'

# —— 定位 flutter —— PATH → FLUTTER_ROOT → README 记的 F:\flutter ——
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter -and $env:FLUTTER_ROOT) {
  $cand = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
  if (Test-Path $cand) { $flutter = $cand }
}
if (-not $flutter -and (Test-Path 'F:\flutter\bin\flutter.bat')) {
  $flutter = 'F:\flutter\bin\flutter.bat'
}
if (-not $SkipBuild) {
  if (-not $flutter) { throw '找不到 flutter（不在 PATH 且 F:\flutter\bin 不存在）——可先构建后用 -SkipBuild' }
  Push-Location $app
  try {
    & $flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build windows --release 失败（exit $LASTEXITCODE）" }
  } finally { Pop-Location }
}
$exe = Get-ChildItem (Join-Path $rel '*.exe') |
    Where-Object { $_.Name -notlike '*test*' } | Select-Object -First 1
if (-not $exe) {
  throw "Release 产物缺失：$rel —— 先跑 flutter build windows --release"
}

# —— 定位 VC++ CRT redist ——
# 优先 vswhere 拿 VS 安装根（支持非默认安装盘符），
# 兜底在两处 Program Files 下 glob 2022 全版本（BuildTools/Community/…）。
$vsRoots = @()
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
  $vsRoots += & $vswhere -all -property installationPath |
      Where-Object { $_ -and (Test-Path $_) }
}
$vsRoots += 'C:\Program Files\Microsoft Visual Studio\2022\*',
            'C:\Program Files (x86)\Microsoft Visual Studio\2022\*'

$crtDir = $null
foreach ($vsr in $vsRoots) {
  $hits = Get-ChildItem -Directory -ErrorAction SilentlyContinue `
          -Path (Join-Path $vsr 'VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT') |
          Sort-Object { [version]($_.Parent.Parent.Name) } -Descending
  if ($hits) { $crtDir = $hits[0].FullName; break }
}
if (-not $crtDir) {
  throw '找不到 VC++ CRT redist 目录（VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT）'
}
Write-Host "CRT redist: $crtDir"

foreach ($d in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  $src = Join-Path $crtDir $d
  if (-not (Test-Path $src)) { throw "redist 目录缺 $d" }
  Copy-Item $src (Join-Path $rel $d) -Force
  $v = (Get-Item (Join-Path $rel $d)).VersionInfo.FileVersionRaw
  if (-not ("$v").StartsWith('14.')) { Write-Warning "$d 版本可疑：$v" }
  Write-Host "  + $d  $v"
}

# —— 打 zip ——
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
$zip = Join-Path $dist "wanji-kit-v$Version-windows-x64.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $rel '*') -DestinationPath $zip -CompressionLevel Optimal
$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Host "`n打包完成: $zip ($size MB)"
