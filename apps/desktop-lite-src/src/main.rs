//! OryvexCore Lite: a native Win32 window around the OryvexCore core, for the machines Flutter
//! cannot reach: Windows 7 and 8, and 32-bit Windows. Same blue-on-black look, same core flags.
#![cfg_attr(windows, windows_subsystem = "windows")]

#[cfg(not(windows))]
fn main() {
    eprintln!("OryvexVPN Lite is a Windows program; on other systems run the oryvexcore core directly.");
}

#[cfg(windows)]
mod win;

#[cfg(windows)]
fn main() {
    app::run();
}

#[cfg(windows)]
mod app {
    use crate::win::*;
    use std::cell::{Cell, RefCell};
    use std::ffi::c_void;
    use std::io::{BufRead, BufReader, Read};
    use std::os::windows::process::CommandExt;
    use std::path::PathBuf;
    use std::process::{Child, Command, Stdio};
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    const BG: COLORREF = rgb(0x00, 0x00, 0x00);
    const FIELD: COLORREF = rgb(0x16, 0x16, 0x1A);
    const BLUE: COLORREF = rgb(0x0A, 0x84, 0xFF);
    const BLUE_DEEP: COLORREF = rgb(0x0B, 0x3F, 0xD1);
    const BLUE_SOFT: COLORREF = rgb(0x8E, 0xC5, 0xFF);
    const TEXT: COLORREF = rgb(0xE8, 0xEF, 0xFF);
    const MUTED: COLORREF = rgb(0x83, 0x94, 0xB8);
    const LINE: COLORREF = rgb(0x1B, 0x27, 0x42);

    const ID_PROTOCOL: u16 = 101;
    const ID_SCAN: u16 = 102;
    const ID_CARRIER: u16 = 103;
    const ID_PORT: u16 = 104;
    const ID_HTTP: u16 = 105;
    const ID_SYSPROXY: u16 = 106;
    const ID_CONNECT: u16 = 107;
    const ID_LOG: u16 = 108;

    const WM_CORE_LINE: u32 = WM_APP + 1;
    const WM_CORE_EXIT: u32 = WM_APP + 2;

    const PROTOCOLS: [(&str, &str); 4] =
        [("MASQUE", "masque"), ("WireGuard", "wg"), ("Gool (WG in MASQUE)", "gool"), ("MASQUE in MASQUE", "mim")];
    const SCANS: [(&str, &str); 5] = [
        ("Turbo", "turbo"),
        ("Balanced", "balanced"),
        ("Thorough", "thorough"),
        ("Verified", "verified"),
        ("Ironclad", "ironclad"),
    ];
    const CARRIERS: [(&str, &str); 2] = [("HTTP/3 (QUIC)", "--h3"), ("HTTP/2 (TCP)", "--h2")];

    #[derive(Clone, Copy)]
    struct Ui {
        main: HWND,
        title: HWND,
        status: HWND,
        protocol: HWND,
        scan: HWND,
        carrier: HWND,
        port: HWND,
        http: HWND,
        sysproxy: HWND,
        connect: HWND,
        log: HWND,
        br_bg: HBRUSH,
        br_field: HBRUSH,
        br_blue: HBRUSH,
        br_deep: HBRUSH,
        font: HFONT,
        font_title: HFONT,
        font_mono: HFONT,
        font_bold: HFONT,
        scale: f32,
    }

    #[derive(Default)]
    struct State {
        child: Option<Child>,
        running: bool,
        generation: usize,
        port: u16,
        proxy_backup: Option<ProxyBackup>,
    }

    thread_local! {
        static UI: Cell<Option<Ui>> = const { Cell::new(None) };
        static STATE: RefCell<State> = RefCell::new(State::default());
    }

    fn ui() -> Option<Ui> {
        UI.with(|u| u.get())
    }

    pub fn run() {
        unsafe {
            join_kill_on_close_job();
            let instance = GetModuleHandleW(std::ptr::null());
            let class = wide("OryvexVPNLiteWindow");
            let br_bg = CreateSolidBrush(BG);
            let icon = LoadImageW(instance, 1 as *const u16, IMAGE_ICON, 0, 0, LR_DEFAULTSIZE | LR_SHARED);
            let wc = WNDCLASSEXW {
                cbSize: std::mem::size_of::<WNDCLASSEXW>() as u32,
                style: 0,
                lpfnWndProc: Some(wndproc),
                cbClsExtra: 0,
                cbWndExtra: 0,
                hInstance: instance,
                hIcon: icon,
                hCursor: LoadCursorW(0, IDC_ARROW),
                hbrBackground: br_bg,
                lpszMenuName: std::ptr::null(),
                lpszClassName: class.as_ptr(),
                hIconSm: icon,
            };
            RegisterClassExW(&wc);

            let scale = screen_scale();
            let style = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPCHILDREN;
            let mut rect = RECT { left: 0, top: 0, right: px(440, scale), bottom: px(620, scale) };
            AdjustWindowRectEx(&mut rect, style, 0, 0);
            let title = wide("OryvexVPN Lite");
            let hwnd = CreateWindowExW(
                0,
                class.as_ptr(),
                title.as_ptr(),
                style,
                px(80, scale),
                px(60, scale),
                rect.right - rect.left,
                rect.bottom - rect.top,
                0,
                0,
                instance,
                std::ptr::null(),
            );
            if hwnd == 0 {
                return;
            }
            // Dark title bar on Windows 10 1809+ / 11; ignored on Windows 7.
            let dark: i32 = 1;
            DwmSetWindowAttribute(hwnd, 20, &dark as *const i32 as *const c_void, 4);
            DwmSetWindowAttribute(hwnd, 19, &dark as *const i32 as *const c_void, 4);

            ShowWindow(hwnd, SW_SHOW);
            UpdateWindow(hwnd);

            let mut msg: MSG = std::mem::zeroed();
            while GetMessageW(&mut msg, 0, 0, 0) > 0 {
                if IsDialogMessageW(hwnd, &mut msg) == 0 {
                    TranslateMessage(&msg);
                    DispatchMessageW(&msg);
                }
            }
        }
    }

    fn px(v: i32, scale: f32) -> i32 {
        (v as f32 * scale).round() as i32
    }

    unsafe fn screen_scale() -> f32 {
        let dc = GetDC(0);
        let dpi = GetDeviceCaps(dc, LOGPIXELSY);
        ReleaseDC(0, dc);
        if dpi > 0 {
            dpi as f32 / 96.0
        } else {
            1.0
        }
    }

    /// The core (a child) dies with this window even if Lite itself crashes.
    unsafe fn join_kill_on_close_job() {
        let job = CreateJobObjectW(std::ptr::null(), std::ptr::null());
        if job == 0 {
            return;
        }
        let mut info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
        info.BasicLimitInformation.LimitFlags =
            JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_BREAKAWAY_OK;
        let ok = SetInformationJobObject(
            job,
            JOB_OBJECT_EXTENDED_LIMIT_INFORMATION_CLASS,
            &info as *const _ as *const c_void,
            std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
        ) != 0
            && AssignProcessToJobObject(job, GetCurrentProcess()) != 0;
        if !ok {
            // Windows 7 has no nested jobs; Lite stops the core itself on close instead.
            CloseHandle(job);
        }
    }

    unsafe fn child(
        parent: HWND,
        class: &str,
        text: &str,
        style: u32,
        ex: u32,
        (x, y, w, h): (i32, i32, i32, i32),
        id: u16,
        font: HFONT,
        scale: f32,
    ) -> HWND {
        let c = wide(class);
        let t = wide(text);
        let hwnd = CreateWindowExW(
            ex,
            c.as_ptr(),
            t.as_ptr(),
            WS_CHILD | WS_VISIBLE | style,
            px(x, scale),
            px(y, scale),
            px(w, scale),
            px(h, scale),
            parent,
            id as HMENU,
            GetModuleHandleW(std::ptr::null()),
            std::ptr::null(),
        );
        SendMessageW(hwnd, WM_SETFONT, font as WPARAM, 1);
        hwnd
    }

    unsafe fn font(face: &str, size: i32, weight: i32, scale: f32) -> HFONT {
        let f = wide(face);
        CreateFontW(-px(size, scale), 0, 0, 0, weight, 0, 0, 0, DEFAULT_CHARSET, 0, 0, CLEARTYPE_QUALITY, 0, f.as_ptr())
    }

    unsafe fn create_ui(hwnd: HWND) {
        let s = screen_scale();
        let f = font("Segoe UI", 14, FW_NORMAL, s);
        let fb = font("Segoe UI", 14, FW_BOLD, s);
        let ft = font("Segoe UI", 24, FW_BOLD, s);
        let fm = font("Consolas", 12, FW_NORMAL, s);

        let label = |text: &str, y: i32| {
            child(hwnd, "STATIC", text, SS_LEFT, 0, (20, y + 4, 110, 22), 0, f, s);
        };

        let title = child(hwnd, "STATIC", "OryvexVPN  \u{b7}  Created by Muvixo", SS_LEFT, 0, (20, 14, 400, 36), 0, ft, s);
        let status = child(hwnd, "STATIC", "Disconnected", SS_LEFT, 0, (20, 52, 400, 22), 0, f, s);

        label("Protocol", 88);
        let protocol = child(hwnd, "COMBOBOX", "", CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL, 0, (140, 88, 280, 200), ID_PROTOCOL, f, s);
        label("Scan", 122);
        let scan = child(hwnd, "COMBOBOX", "", CBS_DROPDOWNLIST | WS_TABSTOP | WS_VSCROLL, 0, (140, 122, 280, 200), ID_SCAN, f, s);
        label("Carrier", 156);
        let carrier = child(hwnd, "COMBOBOX", "", CBS_DROPDOWNLIST | WS_TABSTOP, 0, (140, 156, 280, 120), ID_CARRIER, f, s);
        label("SOCKS5 port", 190);
        let port = child(hwnd, "EDIT", "1819", ES_NUMBER | ES_AUTOHSCROLL | WS_TABSTOP | WS_BORDER, 0, (140, 190, 120, 26), ID_PORT, f, s);
        let http = child(hwnd, "BUTTON", "Also serve an HTTP proxy (port + 1)", BS_AUTOCHECKBOX | WS_TABSTOP, 0, (20, 226, 400, 24), ID_HTTP, f, s);
        let sysproxy = child(hwnd, "BUTTON", "Set the Windows system proxy while connected", BS_AUTOCHECKBOX | WS_TABSTOP, 0, (20, 252, 400, 24), ID_SYSPROXY, f, s);
        let connect = child(hwnd, "BUTTON", "Connect", BS_OWNERDRAW | WS_TABSTOP, 0, (20, 290, 400, 46), ID_CONNECT, fb, s);
        let log = child(
            hwnd,
            "EDIT",
            "",
            ES_MULTILINE | ES_AUTOVSCROLL | ES_READONLY | WS_VSCROLL | WS_BORDER,
            0,
            (20, 350, 400, 252),
            ID_LOG,
            fm,
            s,
        );
        SendMessageW(log, EM_SETLIMITTEXT, 0x10_0000, 0);

        for (name, _) in PROTOCOLS {
            add_item(protocol, name);
        }
        for (name, _) in SCANS {
            add_item(scan, name);
        }
        for (name, _) in CARRIERS {
            add_item(carrier, name);
        }

        let saved = Saved::load();
        SendMessageW(protocol, CB_SETCURSEL, saved.protocol.min(PROTOCOLS.len() - 1), 0);
        SendMessageW(scan, CB_SETCURSEL, saved.scan.min(SCANS.len() - 1), 0);
        SendMessageW(carrier, CB_SETCURSEL, saved.carrier.min(CARRIERS.len() - 1), 0);
        set_text(port, &saved.port.to_string());
        SendMessageW(http, BM_SETCHECK, saved.http as usize, 0);
        SendMessageW(sysproxy, BM_SETCHECK, saved.sysproxy as usize, 0);

        UI.with(|u| {
            u.set(Some(Ui {
                main: hwnd,
                title,
                status,
                protocol,
                scan,
                carrier,
                port,
                http,
                sysproxy,
                connect,
                log,
                br_bg: CreateSolidBrush(BG),
                br_field: CreateSolidBrush(FIELD),
                br_blue: CreateSolidBrush(BLUE),
                br_deep: CreateSolidBrush(BLUE_DEEP),
                font: f,
                font_title: ft,
                font_mono: fm,
                font_bold: fb,
                scale: s,
            }))
        });

        // Undo a system proxy a crash may have left pointing at a dead port.
        proxy_restore_stale();
        append_log("OryvexVPN Lite ready. Pick a route and press Connect.");
    }

    unsafe fn add_item(combo: HWND, text: &str) {
        let w = wide(text);
        SendMessageW(combo, CB_ADDSTRING, 0, w.as_ptr() as LPARAM);
    }

    unsafe fn set_text(hwnd: HWND, text: &str) {
        let w = wide(text);
        SetWindowTextW(hwnd, w.as_ptr());
    }

    unsafe fn get_text(hwnd: HWND) -> String {
        let len = GetWindowTextLengthW(hwnd);
        if len <= 0 {
            return String::new();
        }
        let mut buf = vec![0u16; len as usize + 1];
        let n = GetWindowTextW(hwnd, buf.as_mut_ptr(), buf.len() as i32);
        String::from_utf16_lossy(&buf[..n.max(0) as usize])
    }

    fn selection(combo: HWND) -> usize {
        let v = unsafe { SendMessageW(combo, CB_GETCURSEL, 0, 0) };
        if v < 0 {
            0
        } else {
            v as usize
        }
    }

    fn checked(button: HWND) -> bool {
        unsafe { SendMessageW(button, BM_GETCHECK, 0, 0) as usize == BST_CHECKED }
    }

    fn append_log(line: &str) {
        let Some(ui) = ui() else { return };
        unsafe {
            if GetWindowTextLengthW(ui.log) > 400_000 {
                set_text(ui.log, "");
            }
            let len = GetWindowTextLengthW(ui.log) as usize;
            SendMessageW(ui.log, EM_SETSEL, len, len as LPARAM);
            let w = wide(&format!("{line}\r\n"));
            SendMessageW(ui.log, EM_REPLACESEL, 0, w.as_ptr() as LPARAM);
        }
    }

    fn set_status(text: &str) {
        if let Some(ui) = ui() {
            unsafe { set_text(ui.status, text) };
        }
    }

    fn set_running_ui(running: bool) {
        let Some(ui) = ui() else { return };
        unsafe {
            set_text(ui.connect, if running { "Disconnect" } else { "Connect" });
            for h in [ui.protocol, ui.scan, ui.carrier, ui.port, ui.http, ui.sysproxy] {
                EnableWindow(h, (!running) as BOOL);
            }
            InvalidateRect(ui.connect, std::ptr::null(), 1);
        }
    }

    fn exe_dir() -> PathBuf {
        std::env::current_exe()
            .ok()
            .and_then(|p| p.parent().map(|d| d.to_path_buf()))
            .unwrap_or_else(|| PathBuf::from("."))
    }

    fn data_dir() -> PathBuf {
        let base = std::env::var_os("APPDATA").map(PathBuf::from).unwrap_or_else(exe_dir);
        base.join("OryvexCore")
    }

    fn start_core() {
        let Some(ui) = ui() else { return };
        if STATE.with(|s| s.borrow().running) {
            return;
        }
        let exe = exe_dir().join("oryvexcore.exe");
        if !exe.exists() {
            unsafe {
                let text = wide(&format!("oryvexcore.exe was not found next to OryvexVPNLite.exe:\n{}", exe.display()));
                let cap = wide("OryvexVPN Lite");
                MessageBoxW(ui.main, text.as_ptr(), cap.as_ptr(), MB_ICONERROR);
            }
            return;
        }
        let dir = data_dir();
        let _ = std::fs::create_dir_all(&dir);

        let saved = Saved::from_ui(&ui);
        saved.save();
        let port = saved.port;
        let http_port = port.wrapping_add(1).max(1);
        let protocol = PROTOCOLS[saved.protocol.min(PROTOCOLS.len() - 1)].1;
        let mut args: Vec<String> = vec![
            "--config".into(),
            dir.join("oryvexcore.toml").display().to_string(),
            "--bind".into(),
            format!("127.0.0.1:{port}"),
            "--protocol".into(),
            protocol.into(),
            "--scan".into(),
            SCANS[saved.scan.min(SCANS.len() - 1)].1.into(),
            "-4".into(),
            "--quick-reconnect".into(),
            "--stats".into(),
            "--stats-secs".into(),
            "3".into(),
        ];
        if protocol != "wg" {
            args.push(CARRIERS[saved.carrier.min(CARRIERS.len() - 1)].1.into());
        }
        if saved.http || saved.sysproxy {
            args.push("--http-proxy".into());
            args.push(format!("127.0.0.1:{http_port}"));
        }

        let mut cmd = Command::new(&exe);
        cmd.args(&args)
            .current_dir(&dir)
            .env("RUST_LOG_STYLE", "never")
            .env("NO_COLOR", "1")
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .creation_flags(CREATE_NO_WINDOW);

        let mut child = match cmd.spawn() {
            Ok(c) => c,
            Err(e) => {
                append_log(&format!("[lite] could not start the core: {e}"));
                return;
            }
        };
        append_log(&format!("[lite] oryvexcore {}", args.join(" ")));

        let generation = STATE.with(|s| {
            let mut s = s.borrow_mut();
            s.generation = s.generation.wrapping_add(1);
            s.generation
        });
        let open = Arc::new(AtomicUsize::new(2));
        let hwnd = ui.main;
        if let Some(out) = child.stdout.take() {
            pump(out, hwnd, open.clone(), generation);
        }
        if let Some(err) = child.stderr.take() {
            pump(err, hwnd, open.clone(), generation);
        }

        let backup = if saved.sysproxy { proxy_enable(&format!("127.0.0.1:{http_port}")) } else { None };
        if saved.sysproxy {
            append_log(if backup.is_some() { "[lite] system proxy set" } else { "[lite] could not set the system proxy" });
        }

        STATE.with(|s| {
            let mut s = s.borrow_mut();
            s.child = Some(child);
            s.running = true;
            s.port = port;
            s.proxy_backup = backup;
        });
        set_status("Finding a way out…");
        set_running_ui(true);
    }

    fn pump<R: Read + Send + 'static>(stream: R, hwnd: HWND, open: Arc<AtomicUsize>, generation: usize) {
        std::thread::spawn(move || {
            let reader = BufReader::new(stream);
            for line in reader.split(b'\n') {
                let Ok(bytes) = line else { break };
                let text = String::from_utf8_lossy(&bytes).trim_end().to_string();
                let boxed = Box::into_raw(Box::new(text));
                unsafe {
                    if PostMessageW(hwnd, WM_CORE_LINE, 0, boxed as LPARAM) == 0 {
                        drop(Box::from_raw(boxed));
                    }
                }
            }
            if open.fetch_sub(1, Ordering::SeqCst) == 1 {
                unsafe {
                    PostMessageW(hwnd, WM_CORE_EXIT, generation, 0);
                }
            }
        });
    }

    fn stop_core() {
        let (child, backup) = STATE.with(|s| {
            let mut s = s.borrow_mut();
            s.running = false;
            (s.child.take(), s.proxy_backup.take())
        });
        if let Some(b) = backup {
            proxy_restore(&b);
        }
        if let Some(mut c) = child {
            let _ = c.kill();
            let _ = c.wait();
        }
        set_status("Disconnected");
        set_running_ui(false);
    }

    fn on_line(raw: String) {
        // env_logger: "[2026-10-29T18:00:00.123Z INFO  oryvexcore::socks] message"
        let mut shown = raw.clone();
        if raw.starts_with('[') {
            if let Some(end) = raw.find("] ") {
                let head = &raw[1..end];
                let time = head.get(11..19).unwrap_or("");
                let level = head.split_whitespace().nth(1).unwrap_or("");
                let msg = &raw[end + 2..];
                shown = match level {
                    "ERROR" | "WARN" => format!("{time} {level} {msg}"),
                    _ => format!("{time} {msg}"),
                };
            }
        }
        if raw.contains("listening on") && !raw.contains("http proxy") && raw.trim_end().ends_with(&format!(":{}", STATE.with(|s| s.borrow().port))) {
            set_status("Connected · SOCKS5 ready");
        } else if raw.contains("reconnecting") {
            set_status("Reconnecting…");
        } else if let Some(i) = raw.find("[=] up ") {
            // "[=] up 1.2 MB down 8.4 MB uptime 3m 2s"
            let stats = &raw[i + 4..];
            // Newer cores append the exact byte counts ("... bytes 123 456"); the status line
            // keeps the rounded totals only.
            let stats = stats.split(" bytes ").next().unwrap_or(stats);
            set_status(&format!("Connected · {stats}"));
        }
        append_log(&shown);
    }

    fn on_exit(generation: usize) {
        let (child, backup) = STATE.with(|s| {
            let mut s = s.borrow_mut();
            if s.generation != generation {
                // A core from before the latest Connect; it was already stopped and reaped.
                return (None, None);
            }
            s.running = false;
            (s.child.take(), s.proxy_backup.take())
        });
        if let Some(b) = backup {
            proxy_restore(&b);
        }
        let code = child.and_then(|mut c| c.wait().ok()).and_then(|st| st.code());
        match code {
            Some(c) => append_log(&format!("[lite] core exited with code {c}")),
            None => append_log("[lite] core stopped"),
        }
        set_status("Disconnected");
        set_running_ui(false);
    }

    unsafe fn draw_button(dis: &DRAWITEMSTRUCT) {
        let Some(ui) = ui() else { return };
        let running = STATE.with(|s| s.borrow().running);
        let hdc = dis.hDC;
        let mut rc = dis.rcItem;
        FillRect(hdc, &rc, ui.br_bg);
        let pressed = dis.itemState & ODS_SELECTED != 0;
        let fill = if running || pressed { ui.br_deep } else { ui.br_blue };
        let pen = CreatePen(PS_SOLID, 1, if running { BLUE } else { BLUE_SOFT });
        let old_pen = SelectObject(hdc, pen);
        let old_brush = SelectObject(hdc, fill);
        let r = px(12, ui.scale);
        RoundRect(hdc, rc.left, rc.top, rc.right, rc.bottom, r, r);
        SelectObject(hdc, old_pen);
        SelectObject(hdc, old_brush);
        DeleteObject(pen);

        let text = wide(&get_text(dis.hwndItem));
        SetBkMode(hdc, TRANSPARENT);
        SetTextColor(hdc, rgb(0xFF, 0xFF, 0xFF));
        let old_font = SelectObject(hdc, ui.font_bold);
        DrawTextW(hdc, text.as_ptr(), -1, &mut rc, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        SelectObject(hdc, old_font);
    }

    unsafe extern "system" fn wndproc(hwnd: HWND, msg: u32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
        match msg {
            WM_CREATE => {
                create_ui(hwnd);
                0
            }
            WM_COMMAND => {
                if loword(wparam) == ID_CONNECT && hiword(wparam) == BN_CLICKED {
                    if STATE.with(|s| s.borrow().running) {
                        stop_core();
                    } else {
                        start_core();
                    }
                    return 0;
                }
                DefWindowProcW(hwnd, msg, wparam, lparam)
            }
            WM_DRAWITEM => {
                let dis = &*(lparam as *const DRAWITEMSTRUCT);
                if dis.CtlID == ID_CONNECT as u32 {
                    draw_button(dis);
                    return 1;
                }
                DefWindowProcW(hwnd, msg, wparam, lparam)
            }
            WM_CTLCOLORSTATIC | WM_CTLCOLORBTN => {
                let Some(ui) = ui() else { return DefWindowProcW(hwnd, msg, wparam, lparam) };
                let hdc = wparam as HDC;
                let ctl = lparam as HWND;
                let color = if ctl == ui.title {
                    BLUE_SOFT
                } else if ctl == ui.status {
                    BLUE
                } else if ctl == ui.log {
                    TEXT
                } else {
                    MUTED
                };
                SetTextColor(hdc, color);
                if ctl == ui.log {
                    SetBkColor(hdc, FIELD);
                    return ui.br_field;
                }
                SetBkColor(hdc, BG);
                ui.br_bg
            }
            WM_CTLCOLOREDIT | WM_CTLCOLORLISTBOX => {
                let Some(ui) = ui() else { return DefWindowProcW(hwnd, msg, wparam, lparam) };
                let hdc = wparam as HDC;
                SetTextColor(hdc, TEXT);
                SetBkColor(hdc, FIELD);
                ui.br_field
            }
            WM_CORE_LINE => {
                let text = *Box::from_raw(lparam as *mut String);
                on_line(text);
                0
            }
            WM_CORE_EXIT => {
                if STATE.with(|s| s.borrow().generation) == wparam {
                    on_exit(wparam);
                }
                0
            }
            WM_DESTROY => {
                if let Some(ui) = ui() {
                    Saved::from_ui(&ui).save();
                }
                stop_core();
                PostQuitMessage(0);
                0
            }
            _ => DefWindowProcW(hwnd, msg, wparam, lparam),
        }
    }

    // --- settings -----------------------------------------------------------------------

    struct Saved {
        protocol: usize,
        scan: usize,
        carrier: usize,
        port: u16,
        http: bool,
        sysproxy: bool,
    }

    impl Saved {
        fn path() -> PathBuf {
            data_dir().join("lite.ini")
        }

        fn load() -> Self {
            let mut s = Saved { protocol: 0, scan: 1, carrier: 0, port: 1819, http: false, sysproxy: false };
            if let Ok(text) = std::fs::read_to_string(Self::path()) {
                for line in text.lines() {
                    let Some((k, v)) = line.split_once('=') else { continue };
                    let v = v.trim();
                    match k.trim() {
                        "protocol" => s.protocol = v.parse().unwrap_or(s.protocol),
                        "scan" => s.scan = v.parse().unwrap_or(s.scan),
                        "carrier" => s.carrier = v.parse().unwrap_or(s.carrier),
                        "port" => s.port = v.parse().unwrap_or(s.port),
                        "http" => s.http = v == "1",
                        "sysproxy" => s.sysproxy = v == "1",
                        _ => {}
                    }
                }
            }
            s
        }

        fn from_ui(ui: &Ui) -> Self {
            let port = unsafe { get_text(ui.port) }.trim().parse::<u16>().ok().filter(|p| *p > 0).unwrap_or(1819);
            Saved {
                protocol: selection(ui.protocol),
                scan: selection(ui.scan),
                carrier: selection(ui.carrier),
                port,
                http: checked(ui.http),
                sysproxy: checked(ui.sysproxy),
            }
        }

        fn save(&self) {
            let _ = std::fs::create_dir_all(data_dir());
            let _ = std::fs::write(
                Self::path(),
                format!(
                    "protocol={}\nscan={}\ncarrier={}\nport={}\nhttp={}\nsysproxy={}\n",
                    self.protocol, self.scan, self.carrier, self.port, self.http as u8, self.sysproxy as u8
                ),
            );
        }
    }

    // --- system proxy (WinINet, per user) ------------------------------------------------

    struct ProxyBackup {
        enable: u32,
        server: Option<String>,
        overrides: Option<String>,
    }

    const INET_KEY: &str = "Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";

    fn stale_marker() -> PathBuf {
        data_dir().join("lite-proxy-backup.txt")
    }

    unsafe fn open_inet() -> Option<HKEY> {
        let path = wide(INET_KEY);
        let mut key: HKEY = 0;
        if RegOpenKeyExW(HKEY_CURRENT_USER, path.as_ptr(), 0, KEY_QUERY_VALUE | KEY_SET_VALUE, &mut key) == 0 {
            Some(key)
        } else {
            None
        }
    }

    unsafe fn query_dword(key: HKEY, name: &str) -> Option<u32> {
        let n = wide(name);
        let mut kind = 0u32;
        let mut value = 0u32;
        let mut len = 4u32;
        let rc = RegQueryValueExW(key, n.as_ptr(), std::ptr::null_mut(), &mut kind, &mut value as *mut u32 as *mut u8, &mut len);
        (rc == 0 && kind == REG_DWORD).then_some(value)
    }

    unsafe fn query_string(key: HKEY, name: &str) -> Option<String> {
        let n = wide(name);
        let mut kind = 0u32;
        let mut buf = vec![0u16; 2048];
        let mut len = (buf.len() * 2) as u32;
        let rc = RegQueryValueExW(key, n.as_ptr(), std::ptr::null_mut(), &mut kind, buf.as_mut_ptr() as *mut u8, &mut len);
        if rc != 0 || (kind != REG_SZ && kind != 2) {
            return None;
        }
        let chars = (len as usize / 2).min(buf.len());
        let s = String::from_utf16_lossy(&buf[..chars]);
        Some(s.trim_end_matches('\0').to_string())
    }

    unsafe fn set_dword(key: HKEY, name: &str, v: u32) {
        let n = wide(name);
        RegSetValueExW(key, n.as_ptr(), 0, REG_DWORD, &v as *const u32 as *const u8, 4);
    }

    unsafe fn set_string(key: HKEY, name: &str, v: &str) {
        let n = wide(name);
        let data = wide(v);
        RegSetValueExW(key, n.as_ptr(), 0, REG_SZ, data.as_ptr() as *const u8, (data.len() * 2) as u32);
    }

    unsafe fn delete_value(key: HKEY, name: &str) {
        let n = wide(name);
        RegDeleteValueW(key, n.as_ptr());
    }

    unsafe fn broadcast_proxy_change() {
        InternetSetOptionW(std::ptr::null(), INTERNET_OPTION_SETTINGS_CHANGED, std::ptr::null(), 0);
        InternetSetOptionW(std::ptr::null(), INTERNET_OPTION_REFRESH, std::ptr::null(), 0);
    }

    fn proxy_enable(server: &str) -> Option<ProxyBackup> {
        unsafe {
            let key = open_inet()?;
            let backup = ProxyBackup {
                enable: query_dword(key, "ProxyEnable").unwrap_or(0),
                server: query_string(key, "ProxyServer"),
                overrides: query_string(key, "ProxyOverride"),
            };
            let _ = std::fs::write(
                stale_marker(),
                format!(
                    "{}\n{}\n{}\n",
                    backup.enable,
                    backup.server.clone().unwrap_or_default(),
                    backup.overrides.clone().unwrap_or_default()
                ),
            );
            set_string(key, "ProxyServer", server);
            set_string(key, "ProxyOverride", "localhost;127.*;10.*;192.168.*;<local>");
            set_dword(key, "ProxyEnable", 1);
            RegCloseKey(key);
            broadcast_proxy_change();
            Some(backup)
        }
    }

    fn proxy_restore(b: &ProxyBackup) {
        unsafe {
            if let Some(key) = open_inet() {
                set_dword(key, "ProxyEnable", b.enable);
                match &b.server {
                    Some(s) if !s.is_empty() => set_string(key, "ProxyServer", s),
                    _ => delete_value(key, "ProxyServer"),
                }
                match &b.overrides {
                    Some(s) if !s.is_empty() => set_string(key, "ProxyOverride", s),
                    _ => delete_value(key, "ProxyOverride"),
                }
                RegCloseKey(key);
                broadcast_proxy_change();
            }
        }
        let _ = std::fs::remove_file(stale_marker());
    }

    fn proxy_restore_stale() {
        let Ok(text) = std::fs::read_to_string(stale_marker()) else { return };
        let mut lines = text.lines();
        let enable = lines.next().and_then(|v| v.trim().parse().ok()).unwrap_or(0);
        let server = lines.next().map(|s| s.to_string()).filter(|s| !s.is_empty());
        let overrides = lines.next().map(|s| s.to_string()).filter(|s| !s.is_empty());
        proxy_restore(&ProxyBackup { enable, server, overrides });
        append_log("[lite] restored the system proxy left behind by an earlier run");
    }

    #[allow(dead_code)]
    fn unused(ui: &Ui) -> (HFONT, HFONT, COLORREF) {
        (ui.font, ui.font_mono, LINE)
    }
}
