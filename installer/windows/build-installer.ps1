# Builds OryvexVPN-Setup-<version>-x64.exe from a finished Flutter Release folder.
#
#   cd apps/desktop-src
#   ./tool/bootstrap.ps1
#   flutter build windows --release
#   # copy the core into build/windows/x64/runner/Release/core (CI does this), then:
#   ../../installer/windows/build-installer.ps1
#
# Needs NSIS 3.x:  winget install NSIS.NSIS   (or: choco install nsis)
param(
  [string]$Source = (Join-Path $PSScriptRoot "..\..\apps\desktop-src\build\windows\x64\runner\Release"),
  [string]$Version = "",
  [string]$OutDir = (Join-Path $PSScriptRoot "..\..\dist")
)
$ErrorActionPreference = "Stop"

if (-not (Test-Path (Join-Path $Source "OryvexVPN.exe"))) {
  throw "OryvexVPN.exe not found in '$Source'. Build the app first: flutter build windows --release"
}
$Source = (Resolve-Path $Source).Path

if (-not $Version) {
  $pubspec = Join-Path $PSScriptRoot "..\..\apps\desktop-src\pubspec.yaml"
  $m = Select-String -Path $pubspec -Pattern '^version:\s*(\d+\.\d+\.\d+)' | Select-Object -First 1
  $Version = if ($m) { $m.Matches[0].Groups[1].Value } else { "1.0.0" }
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Version must look like 1.2.3 (got '$Version')" }

$makensis = (Get-Command makensis.exe -ErrorAction SilentlyContinue).Source
if (-not $makensis) {
  foreach ($p in @("${env:ProgramFiles(x86)}\NSIS\makensis.exe", "$env:ProgramFiles\NSIS\makensis.exe")) {
    if (Test-Path $p) { $makensis = $p; break }
  }
}
if (-not $makensis) { throw "NSIS not found. Install it with: winget install NSIS.NSIS  (or: choco install nsis)" }

New-Item -ItemType Directory -Force $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$out = Join-Path $OutDir "OryvexVPN-Setup-$Version-x64.exe"

Push-Location $PSScriptRoot
try {
  & $makensis /V3 /INPUTCHARSET UTF8 "/DVERSION=$Version" "/DSOURCE_DIR=$Source" "/DOUT_FILE=$out" "OryvexVPN.nsi"
  if ($LASTEXITCODE -ne 0) { throw "makensis failed with exit code $LASTEXITCODE" }
} finally {
  Pop-Location
}
Write-Host "Installer ready: $out"
