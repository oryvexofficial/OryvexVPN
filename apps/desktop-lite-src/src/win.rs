//! The few Win32 calls OryvexCore Lite needs, declared by hand so the crate has no dependencies
//! and builds for the tier-3 `*-win7-windows-msvc` targets with nothing but `-Z build-std`.
#![allow(non_snake_case, non_camel_case_types, clippy::upper_case_acronyms, dead_code)]

use std::ffi::c_void;

pub type HWND = isize;
pub type HINSTANCE = isize;
pub type HMENU = isize;
pub type HBRUSH = isize;
pub type HFONT = isize;
pub type HDC = isize;
pub type HICON = isize;
pub type HCURSOR = isize;
pub type HGDIOBJ = isize;
pub type HKEY = isize;
pub type HANDLE = isize;
pub type WPARAM = usize;
pub type LPARAM = isize;
pub type LRESULT = isize;
pub type BOOL = i32;
pub type COLORREF = u32;

pub type WNDPROC = Option<unsafe extern "system" fn(HWND, u32, WPARAM, LPARAM) -> LRESULT>;

#[repr(C)]
pub struct WNDCLASSEXW {
    pub cbSize: u32,
    pub style: u32,
    pub lpfnWndProc: WNDPROC,
    pub cbClsExtra: i32,
    pub cbWndExtra: i32,
    pub hInstance: HINSTANCE,
    pub hIcon: HICON,
    pub hCursor: HCURSOR,
    pub hbrBackground: HBRUSH,
    pub lpszMenuName: *const u16,
    pub lpszClassName: *const u16,
    pub hIconSm: HICON,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct POINT {
    pub x: i32,
    pub y: i32,
}

#[repr(C)]
pub struct MSG {
    pub hwnd: HWND,
    pub message: u32,
    pub wParam: WPARAM,
    pub lParam: LPARAM,
    pub time: u32,
    pub pt: POINT,
}

#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct RECT {
    pub left: i32,
    pub top: i32,
    pub right: i32,
    pub bottom: i32,
}

#[repr(C)]
pub struct DRAWITEMSTRUCT {
    pub CtlType: u32,
    pub CtlID: u32,
    pub itemID: u32,
    pub itemAction: u32,
    pub itemState: u32,
    pub hwndItem: HWND,
    pub hDC: HDC,
    pub rcItem: RECT,
    pub itemData: usize,
}

#[repr(C)]
#[derive(Default)]
pub struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
    pub PerProcessUserTimeLimit: i64,
    pub PerJobUserTimeLimit: i64,
    pub LimitFlags: u32,
    pub MinimumWorkingSetSize: usize,
    pub MaximumWorkingSetSize: usize,
    pub ActiveProcessLimit: u32,
    pub Affinity: usize,
    pub PriorityClass: u32,
    pub SchedulingClass: u32,
}

#[repr(C)]
#[derive(Default)]
pub struct IO_COUNTERS {
    pub ReadOperationCount: u64,
    pub WriteOperationCount: u64,
    pub OtherOperationCount: u64,
    pub ReadTransferCount: u64,
    pub WriteTransferCount: u64,
    pub OtherTransferCount: u64,
}

#[repr(C)]
#[derive(Default)]
pub struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
    pub BasicLimitInformation: JOBOBJECT_BASIC_LIMIT_INFORMATION,
    pub IoInfo: IO_COUNTERS,
    pub ProcessMemoryLimit: usize,
    pub JobMemoryLimit: usize,
    pub PeakProcessMemoryUsed: usize,
    pub PeakJobMemoryUsed: usize,
}

// Window styles
pub const WS_OVERLAPPED: u32 = 0x0000_0000;
pub const WS_CAPTION: u32 = 0x00C0_0000;
pub const WS_SYSMENU: u32 = 0x0008_0000;
pub const WS_MINIMIZEBOX: u32 = 0x0002_0000;
pub const WS_VISIBLE: u32 = 0x1000_0000;
pub const WS_CHILD: u32 = 0x4000_0000;
pub const WS_TABSTOP: u32 = 0x0001_0000;
pub const WS_VSCROLL: u32 = 0x0020_0000;
pub const WS_BORDER: u32 = 0x0080_0000;
pub const WS_CLIPCHILDREN: u32 = 0x0200_0000;

pub const ES_MULTILINE: u32 = 0x0004;
pub const ES_AUTOVSCROLL: u32 = 0x0040;
pub const ES_AUTOHSCROLL: u32 = 0x0080;
pub const ES_READONLY: u32 = 0x0800;
pub const ES_NUMBER: u32 = 0x2000;
pub const BS_AUTOCHECKBOX: u32 = 0x0003;
pub const BS_OWNERDRAW: u32 = 0x000B;
pub const CBS_DROPDOWNLIST: u32 = 0x0003;
pub const SS_LEFT: u32 = 0x0000;

// Messages
pub const WM_CREATE: u32 = 0x0001;
pub const WM_DESTROY: u32 = 0x0002;
pub const WM_SETFONT: u32 = 0x0030;
pub const WM_DRAWITEM: u32 = 0x002B;
pub const WM_COMMAND: u32 = 0x0111;
pub const WM_CTLCOLOREDIT: u32 = 0x0133;
pub const WM_CTLCOLORLISTBOX: u32 = 0x0134;
pub const WM_CTLCOLORBTN: u32 = 0x0135;
pub const WM_CTLCOLORSTATIC: u32 = 0x0138;
pub const WM_APP: u32 = 0x8000;

pub const CB_ADDSTRING: u32 = 0x0143;
pub const CB_GETCURSEL: u32 = 0x0147;
pub const CB_SETCURSEL: u32 = 0x014E;
pub const BM_GETCHECK: u32 = 0x00F0;
pub const BM_SETCHECK: u32 = 0x00F1;
pub const BST_CHECKED: usize = 1;
pub const EM_SETSEL: u32 = 0x00B1;
pub const EM_REPLACESEL: u32 = 0x00C2;
pub const EM_SETLIMITTEXT: u32 = 0x00C5;
pub const BN_CLICKED: u16 = 0;

pub const ODS_SELECTED: u32 = 0x0001;
pub const ODS_DISABLED: u32 = 0x0004;

pub const IDC_ARROW: *const u16 = 32512 as *const u16;
pub const IMAGE_ICON: u32 = 1;
pub const LR_DEFAULTSIZE: u32 = 0x0040;
pub const LR_SHARED: u32 = 0x8000;
pub const SW_SHOW: i32 = 5;
pub const MB_ICONERROR: u32 = 0x10;
pub const DT_CENTER: u32 = 0x01;
pub const DT_VCENTER: u32 = 0x04;
pub const DT_SINGLELINE: u32 = 0x20;
pub const TRANSPARENT: i32 = 1;
pub const LOGPIXELSY: i32 = 90;
pub const FW_NORMAL: i32 = 400;
pub const FW_BOLD: i32 = 700;
pub const DEFAULT_CHARSET: u32 = 1;
pub const CLEARTYPE_QUALITY: u32 = 5;
pub const PS_SOLID: i32 = 0;

pub const CREATE_NO_WINDOW: u32 = 0x0800_0000;
pub const JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE: u32 = 0x2000;
pub const JOB_OBJECT_LIMIT_BREAKAWAY_OK: u32 = 0x0800;
pub const JOB_OBJECT_EXTENDED_LIMIT_INFORMATION_CLASS: i32 = 9;

pub const HKEY_CURRENT_USER: HKEY = 0x8000_0001u32 as i32 as isize;
pub const KEY_QUERY_VALUE: u32 = 0x0001;
pub const KEY_SET_VALUE: u32 = 0x0002;
pub const REG_SZ: u32 = 1;
pub const REG_DWORD: u32 = 4;
pub const INTERNET_OPTION_REFRESH: u32 = 37;
pub const INTERNET_OPTION_SETTINGS_CHANGED: u32 = 39;

#[link(name = "user32")]
extern "system" {
    pub fn RegisterClassExW(class: *const WNDCLASSEXW) -> u16;
    pub fn CreateWindowExW(
        ex_style: u32,
        class: *const u16,
        name: *const u16,
        style: u32,
        x: i32,
        y: i32,
        w: i32,
        h: i32,
        parent: HWND,
        menu: HMENU,
        instance: HINSTANCE,
        param: *const c_void,
    ) -> HWND;
    pub fn DefWindowProcW(hwnd: HWND, msg: u32, w: WPARAM, l: LPARAM) -> LRESULT;
    pub fn GetMessageW(msg: *mut MSG, hwnd: HWND, min: u32, max: u32) -> BOOL;
    pub fn IsDialogMessageW(hwnd: HWND, msg: *mut MSG) -> BOOL;
    pub fn TranslateMessage(msg: *const MSG) -> BOOL;
    pub fn DispatchMessageW(msg: *const MSG) -> LRESULT;
    pub fn PostQuitMessage(code: i32);
    pub fn SendMessageW(hwnd: HWND, msg: u32, w: WPARAM, l: LPARAM) -> LRESULT;
    pub fn PostMessageW(hwnd: HWND, msg: u32, w: WPARAM, l: LPARAM) -> BOOL;
    pub fn SetWindowTextW(hwnd: HWND, text: *const u16) -> BOOL;
    pub fn GetWindowTextW(hwnd: HWND, buf: *mut u16, max: i32) -> i32;
    pub fn GetWindowTextLengthW(hwnd: HWND) -> i32;
    pub fn LoadCursorW(instance: HINSTANCE, name: *const u16) -> HCURSOR;
    pub fn LoadImageW(instance: HINSTANCE, name: *const u16, kind: u32, cx: i32, cy: i32, flags: u32) -> HANDLE;
    pub fn ShowWindow(hwnd: HWND, cmd: i32) -> BOOL;
    pub fn UpdateWindow(hwnd: HWND) -> BOOL;
    pub fn MessageBoxW(hwnd: HWND, text: *const u16, caption: *const u16, kind: u32) -> i32;
    pub fn EnableWindow(hwnd: HWND, enable: BOOL) -> BOOL;
    pub fn GetDC(hwnd: HWND) -> HDC;
    pub fn ReleaseDC(hwnd: HWND, hdc: HDC) -> i32;
    pub fn FillRect(hdc: HDC, rect: *const RECT, brush: HBRUSH) -> i32;
    pub fn DrawTextW(hdc: HDC, text: *const u16, len: i32, rect: *mut RECT, format: u32) -> i32;
    pub fn InvalidateRect(hwnd: HWND, rect: *const RECT, erase: BOOL) -> BOOL;
    pub fn AdjustWindowRectEx(rect: *mut RECT, style: u32, menu: BOOL, ex_style: u32) -> BOOL;
    pub fn DestroyWindow(hwnd: HWND) -> BOOL;
}

#[link(name = "gdi32")]
extern "system" {
    pub fn CreateSolidBrush(color: COLORREF) -> HBRUSH;
    pub fn CreateFontW(
        height: i32,
        width: i32,
        escapement: i32,
        orientation: i32,
        weight: i32,
        italic: u32,
        underline: u32,
        strike_out: u32,
        charset: u32,
        out_precision: u32,
        clip_precision: u32,
        quality: u32,
        pitch_and_family: u32,
        face: *const u16,
    ) -> HFONT;
    pub fn SetTextColor(hdc: HDC, color: COLORREF) -> COLORREF;
    pub fn SetBkColor(hdc: HDC, color: COLORREF) -> COLORREF;
    pub fn SetBkMode(hdc: HDC, mode: i32) -> i32;
    pub fn SelectObject(hdc: HDC, obj: HGDIOBJ) -> HGDIOBJ;
    pub fn GetDeviceCaps(hdc: HDC, index: i32) -> i32;
    pub fn CreatePen(style: i32, width: i32, color: COLORREF) -> HGDIOBJ;
    pub fn RoundRect(hdc: HDC, l: i32, t: i32, r: i32, b: i32, w: i32, h: i32) -> BOOL;
    pub fn DeleteObject(obj: HGDIOBJ) -> BOOL;
}

#[link(name = "kernel32")]
extern "system" {
    pub fn GetModuleHandleW(name: *const u16) -> HINSTANCE;
    pub fn CreateJobObjectW(attrs: *const c_void, name: *const u16) -> HANDLE;
    pub fn SetInformationJobObject(job: HANDLE, class: i32, info: *const c_void, len: u32) -> BOOL;
    pub fn AssignProcessToJobObject(job: HANDLE, process: HANDLE) -> BOOL;
    pub fn GetCurrentProcess() -> HANDLE;
    pub fn CloseHandle(h: HANDLE) -> BOOL;
}

#[link(name = "advapi32")]
extern "system" {
    pub fn RegOpenKeyExW(key: HKEY, sub: *const u16, options: u32, sam: u32, out: *mut HKEY) -> i32;
    pub fn RegSetValueExW(key: HKEY, name: *const u16, reserved: u32, kind: u32, data: *const u8, len: u32) -> i32;
    pub fn RegQueryValueExW(
        key: HKEY,
        name: *const u16,
        reserved: *mut u32,
        kind: *mut u32,
        data: *mut u8,
        len: *mut u32,
    ) -> i32;
    pub fn RegDeleteValueW(key: HKEY, name: *const u16) -> i32;
    pub fn RegCloseKey(key: HKEY) -> i32;
}

#[link(name = "wininet")]
extern "system" {
    pub fn InternetSetOptionW(h: *const c_void, option: u32, buf: *const c_void, len: u32) -> BOOL;
}

#[link(name = "dwmapi")]
extern "system" {
    pub fn DwmSetWindowAttribute(hwnd: HWND, attr: u32, value: *const c_void, size: u32) -> i32;
}

pub const fn rgb(r: u8, g: u8, b: u8) -> COLORREF {
    (r as u32) | ((g as u32) << 8) | ((b as u32) << 16)
}

/// UTF-16, NUL-terminated.
pub fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

pub fn loword(v: usize) -> u16 {
    (v & 0xFFFF) as u16
}

pub fn hiword(v: usize) -> u16 {
    ((v >> 16) & 0xFFFF) as u16
}
