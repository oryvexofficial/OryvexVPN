param(
  [Parameter(Mandatory=$true)][ValidateSet('payload','installer')][string]$Stage,
  [Parameter(Mandatory=$true)][string]$Path
)
$ErrorActionPreference = 'Stop'
$refType = $env:GITHUB_REF_TYPE
$encoded = $env:WINDOWS_PFX_BASE64
$password = $env:WINDOWS_PFX_PASSWORD
if ([string]::IsNullOrWhiteSpace($encoded) -or [string]::IsNullOrWhiteSpace($password)) {
  if ($refType -eq 'tag') { Write-Host '::warning::WINDOWS_PFX_BASE64 / WINDOWS_PFX_PASSWORD not set: this tagged build is NOT Authenticode-signed.' }
  else { Write-Host 'Non-release build: Windows artifacts are not Authenticode-signed.' }
  exit 0
}

$files = @()
if ($Stage -eq 'payload') {
  foreach ($relative in @('OryvexVPN.exe', 'core/oryvexcore.exe', 'core/oryvex-bypass.exe', 'core/fox-core.exe')) {
    $file = Join-Path $Path $relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing first-party executable: $relative" }
    $files += (Get-Item -LiteralPath $file)
  }
} else {
  $files = @(Get-ChildItem -Path $Path -Filter 'OryvexVPN-Setup-*-x64.exe' -File)
  if ($files.Count -ne 1) { throw 'Expected exactly one Windows installer to sign.' }
}

$signtool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" -ErrorAction SilentlyContinue |
  Sort-Object FullName -Descending | Select-Object -First 1
if (-not $signtool) { throw 'Windows SDK signtool.exe is unavailable.' }
$pfx = Join-Path $env:RUNNER_TEMP ("oryvex-" + [Guid]::NewGuid().ToString('N') + '.pfx')
$cert = $null
try {
  [IO.File]::WriteAllBytes($pfx, [Convert]::FromBase64String($encoded))
  $secure = ConvertTo-SecureString $password -AsPlainText -Force
  $imported = @(Import-PfxCertificate -FilePath $pfx -CertStoreLocation 'Cert:\CurrentUser\My' -Password $secure)
  $signers = @($imported | Where-Object { $_.HasPrivateKey })
  if ($signers.Count -ne 1) { throw 'The PFX must contain exactly one signing certificate with its private key.' }
  $cert = $signers[0]
  if ($cert.NotAfter -le (Get-Date)) { throw 'The Windows signing certificate is expired.' }
  foreach ($file in $files) {
    & $signtool.FullName sign /sha1 $cert.Thumbprint /fd SHA256 /tr 'https://timestamp.digicert.com' /td SHA256 $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "Signing failed: $($file.Name)" }
    & $signtool.FullName verify /pa /all $file.FullName
    if ($LASTEXITCODE -ne 0) { throw "Authenticode verification failed: $($file.Name)" }
    Write-Host "Signed and verified $($file.Name)"
  }
} finally {
  if ($cert) { Remove-Item -LiteralPath "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue }
  Remove-Item -LiteralPath $pfx -Force -ErrorAction SilentlyContinue
}
