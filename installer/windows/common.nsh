; OryvexVPN Setup: logic shared by the installer and the uninstaller.
; Included by OryvexVPN.nsi.

!define OX_APP        "OryvexVPN"
!define OX_EXE        "OryvexVPN.exe"
!define OX_CORE_EXE   "oryvexcore.exe"
!define OX_PUBLISHER  "Muvixo"
!define OX_UNINST_EXE "Uninstall OryvexVPN.exe"
!define OX_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\OryvexVPN"
!define OX_APP_KEY    "Software\Muvixo\OryvexVPN"
!define OX_RUN_KEY    "Software\Microsoft\Windows\CurrentVersion\Run"
!define OX_INET_KEY   "Software\Microsoft\Windows\CurrentVersion\Internet Settings"
!define OX_URL        "https://github.com/themuvixo/Oryvex-VirtualPrivateNetwork"

!ifndef VERSION
  !define VERSION "1.0.0"
!endif
!ifndef SOURCE_DIR
  !error "Pass /DSOURCE_DIR=<folder with OryvexVPN.exe> (apps\desktop-src\build\windows\x64\runner\Release). build-installer.ps1 does this for you."
!endif
!ifndef OUT_FILE
  !define OUT_FILE "OryvexVPN-Setup-${VERSION}-x64.exe"
!endif

Unicode true
ManifestDPIAware true
ManifestSupportedOS all
RequestExecutionLevel admin
SetCompressor /SOLID lzma
SetCompressorDictSize 32

Name "${OX_APP}"
OutFile "${OUT_FILE}"
InstallDir "$PROGRAMFILES64\${OX_APP}"
BrandingText " "

VIProductVersion "${VERSION}.0"
VIFileVersion "${VERSION}.0"

!include "LogicLib.nsh"
!include "x64.nsh"
!include "WinVer.nsh"
!include "FileFunc.nsh"
!include "WinMessages.nsh"
!include "nsDialogs.nsh"
!include "Sections.nsh"

; Choices (the components page fills these in; silent installs keep the defaults).
Var OxWantDesktop
Var OxWantStartMenu
Var OxWantLogin
Var OxWantTray
Var OxRemoveSettings

; ------------------------------------------------------------------------------------------------
; Functions needed in both the installer and the uninstaller ("un." prefix for the latter).
; ------------------------------------------------------------------------------------------------
!macro OX_SHARED_FUNCTIONS UN

; The app sets the per-user WinINet proxy while connected and keeps a backup. If it was killed
; while connected, switch off the loopback proxy it left, so the PC is never left offline.
Function ${UN}OxRestoreProxy
  SetShellVarContext current
  ${If} ${FileExists} "$APPDATA\OryvexCore\proxy-backup.json"
    ReadRegStr $0 HKCU "${OX_INET_KEY}" "ProxyServer"
    StrCpy $1 $0 10
    ${If} $1 == "127.0.0.1:"
      WriteRegDWORD HKCU "${OX_INET_KEY}" "ProxyEnable" 0
    ${EndIf}
    Delete "$APPDATA\OryvexCore\proxy-backup.json"
  ${EndIf}
FunctionEnd

; Files are in use while OryvexVPN runs: ask, then close it and its core.
Function ${UN}OxCloseRunningApp
  FindWindow $0 "FLUTTER_RUNNER_WIN32_WINDOW" "${OX_APP}"
  ${If} $0 <> 0
    MessageBox MB_OKCANCEL|MB_ICONINFORMATION "OryvexVPN is running. Setup will disconnect and close it to continue." /SD IDOK IDOK oxclose_go
    Abort
    oxclose_go:
  ${EndIf}
  nsExec::Exec '"$SYSDIR\taskkill.exe" /F /T /IM ${OX_EXE}'
  Pop $0
  nsExec::Exec '"$SYSDIR\taskkill.exe" /F /T /IM ${OX_CORE_EXE}'
  Pop $0
  Sleep 500
  Call ${UN}OxRestoreProxy
FunctionEnd

!macroend

!insertmacro OX_SHARED_FUNCTIONS ""
!insertmacro OX_SHARED_FUNCTIONS "un."

; Never spill files loose into a folder that is not ours: "D:\Apps" becomes "D:\Apps\OryvexVPN".
Function OxNormalizeInstDir
  StrCpy $1 $INSTDIR 1 -1
  ${If} $1 == "\"
    StrCpy $INSTDIR $INSTDIR -1
  ${EndIf}
  ${GetFileName} "$INSTDIR" $0
  ${If} $0 != "${OX_APP}"
  ${AndIfNot} ${FileExists} "$INSTDIR\${OX_EXE}"
    StrCpy $INSTDIR "$INSTDIR\${OX_APP}"
  ${EndIf}
FunctionEnd

; Shared checks for .onInit: 64-bit Windows 10/11, one setup at a time, previous folder, app closed.
Function OxInit
  ${IfNot} ${RunningX64}
  ${OrIfNot} ${AtLeastWin10}
    MessageBox MB_ICONSTOP "OryvexVPN needs 64-bit Windows 10 or 11.$\r$\nFor Windows 7 / 8 or 32-bit PCs use OryvexVPN Lite." /SD IDOK
    Abort
  ${EndIf}
  SetRegView 64
  System::Call 'kernel32::CreateMutex(p 0, i 0, t "OryvexVPN.Setup") p .r1 ?e'
  Pop $R0
  ${If} $R0 <> 0
    MessageBox MB_ICONEXCLAMATION "OryvexVPN Setup is already running." /SD IDOK
    Abort
  ${EndIf}
  ; Upgrades go where the last install went (unless /D= chose another folder).
  ${If} $INSTDIR == "$PROGRAMFILES64\${OX_APP}"
    ReadRegStr $0 HKLM "${OX_APP_KEY}" "InstallDir"
    ${If} $0 != ""
      StrCpy $INSTDIR $0
    ${EndIf}
  ${EndIf}
  StrCpy $OxWantDesktop 1
  StrCpy $OxWantStartMenu 1
  StrCpy $OxWantLogin 0
  StrCpy $OxWantTray 1
  Call OxCloseRunningApp
FunctionEnd

; Opens the app without admin rights (Setup itself runs elevated).
Function OxLaunchApp
  Exec '"$WINDIR\explorer.exe" "$INSTDIR\${OX_EXE}"'
FunctionEnd

; ------------------------------------------------------------------------------------------------
; Install steps (called from the sections of each variant).
; ------------------------------------------------------------------------------------------------
!macro OX_INSTALL_FILES
  SetOutPath "$INSTDIR"
  ; An upgrade replaces the app payload; user data lives in %APPDATA% and is never touched.
  ${If} ${FileExists} "$INSTDIR\${OX_EXE}"
    RMDir /r "$INSTDIR\data"
    RMDir /r "$INSTDIR\core"
  ${EndIf}
  File /r "${SOURCE_DIR}\*.*"
  WriteUninstaller "$INSTDIR\${OX_UNINST_EXE}"

  WriteRegStr HKLM "${OX_APP_KEY}" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "${OX_APP_KEY}" "Version" "${VERSION}"
  WriteRegStr HKLM "${OX_UNINST_KEY}" "DisplayName" "${OX_APP}"
  WriteRegStr HKLM "${OX_UNINST_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${OX_UNINST_KEY}" "Publisher" "${OX_PUBLISHER}"
  WriteRegStr HKLM "${OX_UNINST_KEY}" "DisplayIcon" "$INSTDIR\${OX_EXE},0"
  WriteRegStr HKLM "${OX_UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${OX_UNINST_KEY}" "URLInfoAbout" "${OX_URL}"
  WriteRegStr HKLM "${OX_UNINST_KEY}" "UninstallString" '"$INSTDIR\${OX_UNINST_EXE}"'
  WriteRegStr HKLM "${OX_UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\${OX_UNINST_EXE}" /S'
  WriteRegDWORD HKLM "${OX_UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKLM "${OX_UNINST_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKLM "${OX_UNINST_KEY}" "EstimatedSize" "$0"
!macroend

!macro OX_INSTALL_DESKTOP
  SetShellVarContext all
  CreateShortcut "$DESKTOP\${OX_APP}.lnk" "$INSTDIR\${OX_EXE}" "" "$INSTDIR\${OX_EXE}" 0 SW_SHOWNORMAL "" "OryvexVPN: a way out of filtered networks"
!macroend

!macro OX_INSTALL_STARTMENU
  SetShellVarContext all
  CreateShortcut "$SMPROGRAMS\${OX_APP}.lnk" "$INSTDIR\${OX_EXE}" "" "$INSTDIR\${OX_EXE}" 0 SW_SHOWNORMAL "" "OryvexVPN: a way out of filtered networks"
!macroend

; The same HKCU Run value the app's "Launch at Windows sign-in" switch reads and writes.
!macro OX_INSTALL_LOGIN IN_TRAY
  ${If} ${IN_TRAY} == 1
    WriteRegStr HKCU "${OX_RUN_KEY}" "${OX_APP}" '"$INSTDIR\${OX_EXE}" --background'
  ${Else}
    WriteRegStr HKCU "${OX_RUN_KEY}" "${OX_APP}" '"$INSTDIR\${OX_EXE}"'
  ${EndIf}
!macroend

; ------------------------------------------------------------------------------------------------
; Uninstall.
; ------------------------------------------------------------------------------------------------
Function un.OxInit
  SetRegView 64
  Call un.OxCloseRunningApp
  StrCpy $OxRemoveSettings 0
FunctionEnd

Function un.OxAskRemoveSettings
  MessageBox MB_YESNO|MB_ICONQUESTION|MB_DEFBUTTON2 "Also remove your OryvexVPN settings and saved WARP identity?$\r$\n$\r$\nChoose No to keep them for a later reinstall." /SD IDNO IDNO oxkeep
  StrCpy $OxRemoveSettings 1
  oxkeep:
FunctionEnd

!macro OX_UNINSTALL
  SetShellVarContext all
  Delete "$DESKTOP\${OX_APP}.lnk"
  Delete "$SMPROGRAMS\${OX_APP}.lnk"
  SetShellVarContext current
  Delete "$DESKTOP\${OX_APP}.lnk"
  Delete "$SMPROGRAMS\${OX_APP}.lnk"
  DeleteRegValue HKCU "${OX_RUN_KEY}" "${OX_APP}"

  ; Only what Setup put there: a folder the user shares with other files keeps them.
  RMDir /r "$INSTDIR\data"
  RMDir /r "$INSTDIR\core"
  Delete "$INSTDIR\${OX_EXE}"
  Delete "$INSTDIR\*.dll"
  Delete "$INSTDIR\LICENSE.txt"
  Delete "$INSTDIR\${OX_UNINST_EXE}"
  RMDir "$INSTDIR"

  DeleteRegKey HKLM "${OX_UNINST_KEY}"
  DeleteRegKey HKLM "${OX_APP_KEY}"
  DeleteRegKey /ifempty HKLM "Software\Muvixo"

  ${If} $OxRemoveSettings == 1
    SetShellVarContext current
    RMDir /r "$APPDATA\OryvexCore"
    RMDir /r "$APPDATA\Muvixo\OryvexVPN"
    RMDir "$APPDATA\Muvixo"
  ${EndIf}
!macroend
