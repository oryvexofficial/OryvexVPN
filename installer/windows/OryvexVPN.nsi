; OryvexVPN Setup: standard NSIS Modern UI 2 wizard.
; Welcome > License > Folder > Components > Install > Finish. No custom pages, no recolouring.
;
; Build: installer\windows\build-installer.ps1   (or makensis /DSOURCE_DIR=... OryvexVPN.nsi)

!include "common.nsh"
!include "MUI2.nsh"

ShowInstDetails show
ShowUninstDetails show

!define MUI_ICON "assets\app.ico"
!define MUI_UNICON "assets\app.ico"
!define MUI_ABORTWARNING
!define MUI_ABORTWARNING_TEXT "Are you sure you want to cancel OryvexVPN Setup?"
!define MUI_UNABORTWARNING
!define MUI_COMPONENTSPAGE_SMALLDESC

; --- Installer pages ---------------------------------------------------------------------------
!define MUI_WELCOMEPAGE_TITLE "Welcome to OryvexVPN Setup"
!define MUI_WELCOMEPAGE_TEXT "This wizard installs OryvexVPN ${VERSION} on your computer.$\r$\n$\r$\nOryvexVPN connects you through WireGuard, MASQUE or Tor and lets you choose the exit country.$\r$\n$\r$\nClose OryvexVPN before you continue. Click Next to continue."
!insertmacro MUI_PAGE_WELCOME

!define MUI_LICENSEPAGE_TEXT_TOP "OryvexVPN is free software under the GNU AGPL-3.0."
!insertmacro MUI_PAGE_LICENSE "LICENSE.txt"

!insertmacro MUI_PAGE_DIRECTORY

!define MUI_COMPONENTSPAGE_TEXT_TOP "Choose which shortcuts and startup options you want."
!insertmacro MUI_PAGE_COMPONENTS

!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_TITLE "OryvexVPN is installed"
!define MUI_FINISHPAGE_TEXT "Setup has finished installing OryvexVPN ${VERSION}.$\r$\n$\r$\nOpen the app and press the power button to connect. Auto mode picks a route that works on your network."
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Launch OryvexVPN"
!define MUI_FINISHPAGE_RUN_FUNCTION OxLaunchApp
!define MUI_FINISHPAGE_NOREBOOTSUPPORT
!insertmacro MUI_PAGE_FINISH

; --- Uninstaller pages -------------------------------------------------------------------------
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

VIAddVersionKey "ProductName" "OryvexVPN"
VIAddVersionKey "CompanyName" "Muvixo"
VIAddVersionKey "FileDescription" "OryvexVPN Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Created by Muvixo. AGPL-3.0."

; --- Sections ----------------------------------------------------------------------------------
Section "OryvexVPN (required)" SecMain
  SectionIn RO
  !insertmacro OX_INSTALL_FILES
SectionEnd

Section "Desktop shortcut" SecDesktop
  !insertmacro OX_INSTALL_DESKTOP
SectionEnd

Section "Start menu shortcut" SecStartMenu
  !insertmacro OX_INSTALL_STARTMENU
SectionEnd

Section /o "Start with Windows (in the tray)" SecLogin
  !insertmacro OX_INSTALL_LOGIN 1
SectionEnd

; Clears a sign-in entry left by an older install when the option is not ticked.
Section "-Cleanup"
  ${IfNot} ${SectionIsSelected} ${SecLogin}
    DeleteRegValue HKCU "${OX_RUN_KEY}" "${OX_APP}"
  ${EndIf}
SectionEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMain} "The OryvexVPN app, the OryvexCore engine and Tor."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} "Add an OryvexVPN icon to the desktop."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecStartMenu} "Add OryvexVPN to the Start menu."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecLogin} "Open OryvexVPN in the tray when you sign in to Windows."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Function .onInit
  Call OxInit
FunctionEnd

Function un.onInit
  Call un.OxInit
  Call un.OxAskRemoveSettings
FunctionEnd

Section "Uninstall"
  !insertmacro OX_UNINSTALL
SectionEnd
