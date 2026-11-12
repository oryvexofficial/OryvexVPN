# Windows twin of tool/bootstrap.sh.
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
flutter create --org com.oryvex --project-name oryvexcore --platforms windows .
$cmake = "windows/CMakeLists.txt"
if (Test-Path $cmake) {
  (Get-Content $cmake) -replace 'set\(BINARY_NAME "oryvexcore"\)', 'set(BINARY_NAME "OryvexVPN")' | Set-Content $cmake
}
# The window is shown by window_manager in lib/main.dart, so "--background" (start in tray at
# sign-in) can keep it hidden. Drop the template's show-on-first-frame call.
$fw = "windows/runner/flutter_window.cpp"
if (Test-Path $fw) {
  (Get-Content $fw) -replace '^\s*this->Show\(\);', '    // Shown by window_manager in lib/main.dart.' | Set-Content $fw
}
git checkout -- test/widget_test.dart 2>$null
flutter pub get
Write-Host "desktop bootstrap done"
