Unicode true
!include "MUI2.nsh"

!ifndef PRODUCT_VERSION
  !define PRODUCT_VERSION "1.0.2.7"
!endif

Name "VexoStream"
OutFile "VexoStream-${PRODUCT_VERSION}-Setup.exe"
InstallDir "$LOCALAPPDATA\Programs\VexoStream"
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 32

VIProductVersion "${PRODUCT_VERSION}"
VIAddVersionKey "ProductName" "VexoStream"
VIAddVersionKey "ProductVersion" "${PRODUCT_VERSION}"
VIAddVersionKey "FileDescription" "VexoStream Windows installer"
VIAddVersionKey "CompanyName" "VexoStream"

!define MUI_ABORTWARNING
!define MUI_ICON "..\branding\app_icon.ico"
!define MUI_UNICON "..\branding\app_icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\VexoStream.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Launch VexoStream"
!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

BrandingText "VexoStream"

Section "VexoStream" SEC_INSTALL
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  File /r "..\build\windows\x64\runner\Release\*"

  CreateDirectory "$SMPROGRAMS\VexoStream"
  CreateShortcut "$SMPROGRAMS\VexoStream\VexoStream.lnk" "$INSTDIR\VexoStream.exe" "" "$INSTDIR\VexoStream.exe"
  CreateShortcut "$SMPROGRAMS\VexoStream\Uninstall VexoStream.lnk" "$INSTDIR\Uninstall.exe"

  WriteUninstaller "$INSTDIR\Uninstall.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\VexoStream" "DisplayName" "VexoStream"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\VexoStream" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\VexoStream" "Publisher" "VexoStream"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\VexoStream" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\VexoStream" "DisplayIcon" "$INSTDIR\VexoStream.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\VexoStream" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\VexoStream" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\VexoStream" "NoRepair" 1
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  Delete "$SMPROGRAMS\VexoStream\VexoStream.lnk"
  Delete "$SMPROGRAMS\VexoStream\Uninstall VexoStream.lnk"
  RMDir "$SMPROGRAMS\VexoStream"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\VexoStream"
  RMDir /r "$INSTDIR"
SectionEnd
