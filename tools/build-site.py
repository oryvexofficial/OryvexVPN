#!/usr/bin/env python3
"""Builds the multi-page website in site/ from one place.

    python3 tools/build-site.py

The site is laid out like the OryvexVPN app itself: a sidebar with the pages (number keys jump
between them, like Ctrl+1..3 in the app), a title bar, tiles on an ink (or paper) canvas, and
on phones a floating tab bar. The home page is the app's Connect page as a live demo that runs
in the browser and connects nothing.

Sidebar, tab bar, title bar and icons are shared, so a nav change is one edit here.
The output is plain static HTML (GitHub Pages serves site/ as is, see pages.yml).
`tools/set-repo.sh` rewrites the oryvexofficial/OryvexVPN links in the output and in this file.
style.css and app.js are hand-written and live in site/ directly.
"""
import pathlib, re, sys

if '--force' not in sys.argv:
    sys.exit('site/ is now maintained by hand (real home page, MITM docs). Running this generator would bring back the old demo page; pass --force if you really want that.')

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
REPO = "https://github.com/oryvexofficial/OryvexVPN"
RELEASES = REPO + "/releases/latest"

# ---------------------------------------------------------------- icons (24px, stroke)
ICONS = {
    "menu": '<path d="M4 7h16M4 12h16M4 17h16"/>',
    "close": '<path d="M6 6l12 12M18 6 6 18"/>',
    "route": '<circle cx="6" cy="19" r="3"/><path d="M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15"/><circle cx="18" cy="5" r="3"/>',
    "onion": '<path d="M12 21c-4.2 0-7-2.9-7-6.6C5 10 9.4 8.2 12 4c2.6 4.2 7 6 7 10.4 0 3.7-2.8 6.6-7 6.6z"/><path d="M12 21c-2 0-3.6-2.8-3.6-6.4 0-3.3 1.8-5.6 3.6-7.6"/><path d="M12 21c2 0 3.6-2.8 3.6-6.4 0-3.3-1.8-5.6-3.6-7.6"/><path d="M12 4V2.5"/>',
    "globe": '<circle cx="12" cy="12" r="9.5"/><path d="M12 2.5a14.5 14.5 0 0 0 0 19 14.5 14.5 0 0 0 0-19"/><path d="M2.5 12h19"/>',
    "shield": '<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z"/><path d="m9 12 2 2 4-4"/>',
    "download": '<path d="M12 15V3"/><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/>',
    "terminal": '<path d="m4 17 6-6-6-6"/><path d="M12 19h8"/>',
    "book": '<path d="M12 7v14"/><path d="M3 18a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h5a4 4 0 0 1 4 4 4 4 0 0 1 4-4h5a1 1 0 0 1 1 1v13a1 1 0 0 1-1 1h-6a3 3 0 0 0-3 3 3 3 0 0 0-3-3z"/>',
    "arrow": '<path d="M5 12h14"/><path d="m12 5 7 7-7 7"/>',
    "heart": '<path d="M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.3 1.5 4.05 3 5.5l7 7Z"/>',
    "box": '<path d="M21 8a2 2 0 0 0-1-1.73l-7-4a2 2 0 0 0-2 0l-7 4A2 2 0 0 0 3 8v8a2 2 0 0 0 1 1.73l7 4a2 2 0 0 0 2 0l7-4A2 2 0 0 0 21 16Z"/><path d="m3.3 7 8.7 5 8.7-5"/><path d="M12 22V12"/>',
    "monitor": '<rect width="20" height="14" x="2" y="3" rx="2"/><path d="M8 21h8M12 17v4"/>',
    "zap": '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
    "layers": '<path d="M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z"/><path d="m22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65"/><path d="m22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65"/>',
    "code": '<path d="m16 18 6-6-6-6"/><path d="m8 6-6 6 6 6"/>',
    "radar": '<circle cx="12" cy="12" r="2"/><path d="M16.24 7.76a6 6 0 0 1 0 8.49M7.76 16.24a6 6 0 0 1 0-8.49M19.07 4.93a10 10 0 0 1 0 14.14M4.93 19.07a10 10 0 0 1 0-14.14"/>',
    "external": '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
    "home": '<path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>',
    "bridge": '<path d="M3 19V9M21 19V9M3 13h18"/><path d="M3 9c3.5 3 14.5 3 18 0"/><path d="M8 13v6M16 13v6M12 13v6"/>',
    "user": '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
    "smartphone": '<rect width="14" height="20" x="5" y="2" rx="2.5"/><path d="M11 18h2"/>',
    "info": '<circle cx="12" cy="12" r="9.5"/><path d="M12 16v-4M12 8h.01"/>',
    "plug": '<path d="M12 22v-5"/><path d="M9 8V2M15 8V2"/><path d="M18 8v5a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8z"/>',
    "copy": '<rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>',
    "wifi-off": '<path d="M12 20h.01"/><path d="M8.5 16.43a5 5 0 0 1 7 0"/><path d="M2 8.82a15 15 0 0 1 4.18-2.65M22 8.82a15 15 0 0 0-11.29-3.76M5 12.86a10 10 0 0 1 5.17-2.69M19 12.86a10 10 0 0 0-2-1.51"/><path d="m2 2 20 20"/>',
}
FILLED = {
    "github": ('0 0 24 24', '<path d="M12 .5a11.5 11.5 0 0 0-3.64 22.41c.58.1.79-.25.79-.56v-2c-3.2.7-3.88-1.37-3.88-1.37-.52-1.33-1.28-1.69-1.28-1.69-1.05-.71.08-.7.08-.7 1.16.08 1.77 1.19 1.77 1.19 1.03 1.77 2.7 1.26 3.36.96.1-.75.4-1.26.73-1.55-2.55-.29-5.24-1.28-5.24-5.68 0-1.26.45-2.28 1.19-3.09-.12-.29-.52-1.46.11-3.04 0 0 .97-.31 3.17 1.18a11 11 0 0 1 5.77 0c2.2-1.49 3.17-1.18 3.17-1.18.63 1.58.23 2.75.11 3.04.74.81 1.19 1.83 1.19 3.09 0 4.41-2.69 5.39-5.25 5.67.41.36.78 1.06.78 2.14v3.17c0 .31.21.67.8.56A11.5 11.5 0 0 0 12 .5z"/>'),
    "windows": ('0 0 24 24', '<path d="M3 5.6 10.4 4.6v7H3zM11.4 4.45 21 3v8.6h-9.6zM3 12.4h7.4v7L3 18.4zM11.4 12.4H21V21l-9.6-1.4z"/>'),
    "android": ('0 0 24 24', '<path d="M17.6 9.48 19.44 6.3a.38.38 0 0 0-.66-.38l-1.87 3.23a11.4 11.4 0 0 0-9.82 0L5.22 5.92a.38.38 0 0 0-.66.38L6.4 9.48A10.8 10.8 0 0 0 1 18h22a10.8 10.8 0 0 0-5.4-8.52zM7 15.25a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5zm10 0a1.25 1.25 0 1 1 0-2.5 1.25 1.25 0 0 1 0 2.5z"/>'),
}

ICONS.update({
    "check": '<path d="M20 6 9 17l-5-5"/>',
    "chev": '<path d="m9 6 6 6-6 6"/>',
    "list": '<path d="M8 6h13M8 12h13M8 18h13"/><path d="M3 6h.01M3 12h.01M3 18h.01"/>',
    "sliders": '<path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0"/><circle cx="16" cy="6" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="18" cy="18" r="2"/>',
    "down": '<path d="M12 5v14"/><path d="m19 12-7 7-7-7"/>',
    "up": '<path d="M12 19V5"/><path d="m5 12 7-7 7 7"/>',
    "clock": '<circle cx="12" cy="12" r="9.5"/><path d="M12 7v5l3 2"/>',
    "spark": '<path d="M12 3v18M3 12h18M5.6 5.6l12.8 12.8M18.4 5.6 5.6 18.4"/>',
    "sun": '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/>',
    "moon": '<path d="M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5a8.5 8.5 0 1 0 11 11z"/>',
    "grid": '<rect width="7" height="7" x="3" y="3" rx="1.5"/><rect width="7" height="7" x="14" y="3" rx="1.5"/><rect width="7" height="7" x="3" y="14" rx="1.5"/><rect width="7" height="7" x="14" y="14" rx="1.5"/>',
    "alert": '<path d="M12 9v4M12 17h.01"/><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
    "lock": '<rect width="16" height="11" x="4" y="11" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/>',
    "eye-off": '<path d="M9.9 4.24A9 9 0 0 1 12 4c7 0 10 8 10 8a13.2 13.2 0 0 1-1.67 2.68"/><path d="M6.61 6.61A13.5 13.5 0 0 0 2 12s3 8 10 8a9.7 9.7 0 0 0 5.39-1.61"/><path d="M14.12 14.12a3 3 0 1 1-4.24-4.24"/><path d="m2 2 20 20"/>',
    "refresh": '<path d="M20 12a8 8 0 0 0-13.66-5.66L4 8.5"/><path d="M4 3.5v5h5"/><path d="M4 12a8 8 0 0 0 13.66 5.66L20 15.5"/><path d="M20 20.5v-5h-5"/>',
    "type": '<path d="M4 7V5h16v2"/><path d="M12 5v14"/><path d="M9 19h6"/>',
})

def icon(name, cls=""):
    c = ("i " + cls).strip()
    if name in FILLED:
        vb, body = FILLED[name]
        return f'<svg class="{c} fill" viewBox="{vb}" aria-hidden="true" focusable="false">{body}</svg>'
    return f'<svg class="{c}" viewBox="0 0 24 24" aria-hidden="true" focusable="false">{ICONS[name]}</svg>'

def expand(html):
    html = re.sub(r"\{\{i:([a-z-]+)(?: ([a-z-]+))?\}\}", lambda m: icon(m.group(1), m.group(2) or ""), html)
    return html.replace("@REPO@", REPO).replace("@REL@", RELEASES)

def proto(name, cls="proto"):
    return f'<img class="{cls}" src="assets/protocols/{name}.svg" alt="" width="22" height="22">'

# ---------------------------------------------------------------- shell
# (key, file, label, icon, title-bar text)
NAV = [
    ("home", "index.html", "Connect", "shield", "Connect"),
    ("guide", "guide.html", "How to use", "route", "How to use"),
    ("app", "app.html", "App", "smartphone", "App"),
    ("tor", "tor.html", "Tor", "onion", "Tor"),
    ("docs", "docs.html", "Docs", "terminal", "Docs"),
    ("about", "about.html", "About", "info", "About"),
    ("creator", "creator.html", "Creator", "heart", "Creator"),
    ("download", "download.html", "Download", "download", "Download"),
]
TABS = ["home", "guide", "tor", "docs"]

def nav_links(active, kbd=True):
    out = []
    for n, (key, href, label, ic, _) in enumerate(NAV, 1):
        cur = ' aria-current="page"' if key == active else ""
        k = f"<kbd>{n}</kbd>" if kbd else ""
        out.append(f'<a href="{href}"{cur}>{{{{i:{ic}}}}}<span>{label}</span>{k}</a>')
    return "".join(out)

BRAND = '<a class="brand" href="index.html" aria-label="OryvexVPN home"><img src="assets/mark.svg" alt="" width="28" height="28"><span>Oryvex<b>VPN</b></span></a>'

THEME_INIT = """<script>try{var t=localStorage.getItem('ox-theme');if(t)document.documentElement.setAttribute('data-theme',t);}catch(e){}</script>
"""

def shell(active, body):
    title = next(t for k, _, _, _, t in NAV if k == active) if active != "404" else "Not found"
    tabs = []
    for key in TABS:
        _, href, label, ic, _ = next(x for x in NAV if x[0] == key)
        cur = ' aria-current="page"' if key == active else ""
        tabs.append(f'<a href="{href}"{cur}>{{{{i:{ic}}}}}<span>{"Connect" if key == "home" else label.replace("How to use", "Guide")}</span></a>')
    more_cur = ' aria-current="page"' if active not in TABS and active != "404" else ""
    tabs.append(f'<button type="button" id="more"{more_cur} aria-haspopup="dialog" aria-controls="sheet">{{{{i:grid}}}}<span>More</span></button>')
    return f'''<a class="skip" href="#main">Skip to content</a>
<div class="shell">
<aside class="side" aria-label="Site">
{BRAND}
<nav class="nav" aria-label="Main">{nav_links(active)}</nav>
<div class="side-gap"></div>
<div class="card-status" id="side-status">
<span class="status" data-s="off" id="side-pill">Off</span>
<p id="side-line">Auto &middot; live demo</p>
<a class="btn quiet" id="side-btn" href="index.html#connect">Try the demo</a>
</div>
<div class="side-foot"><span>AGPL-3.0 &middot; Muvixo</span><button type="button" class="ibtn theme-btn" aria-label="Switch light or dark">{{{{i:moon i-moon}}}}{{{{i:sun i-sun}}}}</button></div>
</aside>
<div class="stage">
<header class="bar">
{BRAND}
<span class="bar-title">{title}</span>
<div class="bar-end">
<button type="button" class="ibtn theme-btn" aria-label="Switch light or dark">{{{{i:moon i-moon}}}}{{{{i:sun i-sun}}}}</button>
<a class="ibtn gh" href="@REPO@" aria-label="Source on GitHub">{{{{i:github}}}}</a>
<a class="btn sm" href="download.html">{{{{i:download}}}}Download</a>
</div>
</header>
<main id="main">
{body}
</main>
<footer class="credit"><span>&copy; <span id="year">2026</span> Muvixo &middot; OryvexVPN</span><a href="@REPO@">GitHub</a><a href="@REPO@/blob/main/LICENSE">AGPL-3.0</a><a href="@REPO@/blob/main/NOTICE.md">Notices</a></footer>
</div>
</div>
<nav class="tabs" aria-label="Tabs">{"".join(tabs)}</nav>
<div class="sheet" id="sheet" role="dialog" aria-modal="true" aria-label="All pages"><div class="sheet-in" tabindex="-1"><div class="sheet-grab"></div><nav class="nav" aria-label="All pages">{nav_links(active, kbd=False)}</nav></div></div>'''

def page(key, title, desc, body, extra_head=""):
    full = "OryvexVPN · a way out of filtered networks" if key == "home" else f"{title} · OryvexVPN"
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
{extra_head}<title>{full}</title>
<meta name="description" content="{desc}">
<meta name="theme-color" content="#06080c">
<meta property="og:title" content="{full}">
<meta property="og:description" content="{desc}">
<meta property="og:image" content="assets/icon-256.png">
<link rel="icon" href="assets/mark.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="assets/icon-256.png">
<link rel="preload" href="assets/fonts/Inter-Regular.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="style.css">
{THEME_INIT}</head>
<body data-page="{key}">
{shell(key, body)}
<script src="app.js?v=bypass3"></script>
</body>
</html>
'''

def head(eyebrow, h1, lead="", actions=""):
    lead = f'<p class="lead">{lead}</p>' if lead else ""
    actions = f'<div class="actions">{actions}</div>' if actions else ""
    return f'<header class="ph"><div><span class="eyebrow">{eyebrow}</span><h1>{h1}</h1>{lead}</div>{actions}</header>'

def sec(ic, title, extra=""):
    return f'<div class="sec-h"><span class="ico">{{{{i:{ic}}}}}</span><h2>{title}</h2>{extra}</div>'

def rows(items, head=None):
    """Settings-style rows: (key, value) pairs, keys in mono."""
    h = ""
    if head:
        h = '<div class="group-head">' + "".join(f"<span>{x}</span>" for x in head) + "</div>"
    body = "".join(f'<div class="row kv"><div class="key">{k}</div><div class="row-main row-s">{v}</div></div>' for k, v in items)
    return f'<div class="group">{h}{body}</div>'

DL_BTN = '<a class="btn" href="download.html">{{i:download}}Download</a>'

# ---------------------------------------------------------------- the orb (widgets/orb.dart, in SVG)
ORB_SVG = '''<svg viewBox="0 0 300 300" aria-hidden="true" focusable="false">
<defs>
<radialGradient id="oxDiscOff" cx="50%" cy="26%" r="80%"><stop offset="0" stop-color="#ffffff"/><stop offset=".6" stop-color="#eef2f7"/><stop offset="1" stop-color="#cfd8e4"/></radialGradient>
<radialGradient id="oxDiscOn" cx="50%" cy="26%" r="80%"><stop offset="0" stop-color="#76b4ff"/><stop offset=".5" stop-color="#2a80ff"/><stop offset="1" stop-color="#0046d5"/></radialGradient>
<linearGradient id="oxTail" gradientUnits="userSpaceOnUse" x1="226.6" y1="85.7" x2="250" y2="150"><stop offset="0" stop-color="#0a6cff" stop-opacity="0"/><stop offset="1" stop-color="#8cc2ff" stop-opacity=".95"/></linearGradient>
</defs>
<circle class="sonar" cx="150" cy="150" r="140"/><circle class="sonar b" cx="150" cy="150" r="140"/>
<circle class="halo" cx="150" cy="150" r="134"/>
<path class="track" d="M243.97 115.8A100 100 0 1 1 184.2 56.03"/>
<path class="prog" pathLength="100" d="M243.97 115.8A100 100 0 1 1 184.2 56.03"/>
<circle class="closed" cx="150" cy="150" r="100"/>
<circle class="burst" cx="150" cy="150" r="100"/>
<g class="disc">
<circle class="disc-off" cx="150" cy="150" r="72" fill="url(#oxDiscOff)"/>
<circle class="disc-on" cx="150" cy="150" r="72" fill="url(#oxDiscOn)"/>
<g class="g-power" fill="none" stroke="#0a6cff" stroke-width="2.4" stroke-linecap="round" transform="translate(126 126) scale(2)"><path d="M12 3v8"/><path d="M17.7 6.7a8 8 0 1 1-11.4 0"/></g>
<g class="g-shield" transform="translate(126 125) scale(2)"><path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z" fill="#fff"/><path d="m8.8 12.2 2.3 2.3 4.3-4.6" fill="none" stroke="#0a6cff" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></g>
</g>
<g class="core"><path class="tail" d="M226.6 85.7A100 100 0 0 1 250 150"/><circle cx="250" cy="150" r="9"/></g>
</svg>'''

def stat(ic, label, vid, value, sid, sub, spark=False, mono=False):
    sp = ""
    if spark:
        sp = f'<svg class="spark" viewBox="0 0 120 30" preserveAspectRatio="none" aria-hidden="true"><defs><linearGradient id="oxSpark" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0a6cff" stop-opacity=".28"/><stop offset="1" stop-color="#0a6cff" stop-opacity="0"/></linearGradient></defs><path class="area" id="{vid}-a" d="M0 29H120V30H0Z"/><path id="{vid}-l" d="M0 29H120"/></svg>'
    cls = "stat-v mono" if mono else "stat-v"
    return f'<div class="tile stat"><div class="stat-h"><span class="ico">{{{{i:{ic}}}}}</span>{label}</div><div class="{cls}" id="{vid}">{value}</div>{sp}<div class="stat-s" id="{sid}">{sub}</div></div>'

PROTOS = [("auto", "auto", "Auto"), ("wg", "wg", "WireGuard"), ("masque", "masque", "MASQUE"),
          ("mim", "mim", "MASQUE²"), ("gool", "gool", "Gool"), ("tor", "tor", "Tor"), ("bypass", "bypass", "Bypass")]

# The Bypass list, kept in step with apps/shared/lib/src/core/bypass_services.dart.
BYPASS_SERVICES = [
    ("youtube", "YouTube", "Site and app, video servers included", False),
    ("x", "X (Twitter)", "Site, app and images", False),
    ("telegram", "Telegram", "Messages and media. Calls are not covered.", True),
    ("instagram", "Instagram", "Some networks cut it after it connects; use a tunnel route then.", True),
    ("whatsapp", "WhatsApp", "Messages only, and some networks cut it. Calls are not covered.", True),
    ("facebook", "Facebook", "Site, Messenger and media", False),
    ("discord", "Discord", "Chat and media. Voice is not covered.", True),
    ("reddit", "Reddit", "Site, app and media", False),
    ("twitch", "Twitch", "Site and streams", False),
    ("spotify", "Spotify", "App and web player", False),
    ("tiktok", "TikTok", "Site and app", False),
]
BYPASS_LIST_HTML = "".join(
    f'<div class="svc{" limited" if lim else ""}"><img src="assets/services/{sid}.svg" width="36" height="36" alt="">'
    f'<div><div class="svc-t">{name}</div><div class="svc-s">{note}</div></div></div>'
    for sid, name, note, lim in BYPASS_SERVICES)

PAGES = {}

# ---------------------------------------------------------------- home: Connect
route_choices = "".join(
    f'<button type="button" class="choice" data-p="{k}" aria-pressed="{str(k == "auto").lower()}">{proto(f, "proto")}{label}</button>'
    for k, f, label in PROTOS)

PAGES["index.html"] = ("home", "Connect",
"OryvexVPN: WireGuard, MASQUE and Tor with exit-country choice, for Windows and Android. Free software by Muvixo.",
'''<div class="banner" id="dirty" hidden>{{i:sliders}}<p>Your settings changed. Reconnect to apply them.</p><button type="button" class="link" id="reapply">Reconnect</button></div>
<div class="connect" id="connect">
<section class="panel" id="panel" data-state="off" aria-labelledby="p-head">
<div class="panel-top"><span class="status" data-s="off" id="p-pill">Off</span><span class="pill" id="p-chip">''' + proto("auto") + '''<span>Auto</span></span></div>
<span class="eyebrow" id="p-eyebrow">Private by Design</span>
<h1 class="p-head" id="p-head">A way out.</h1>
<p class="p-sub" id="p-sub">Auto: WireGuard &rsaquo; MASQUE &rsaquo; MASQUE&sup2; &rsaquo; Gool</p>
<button type="button" class="orb" id="orb" aria-label="Connect (demo)">''' + ORB_SVG + '''</button>
<button type="button" class="btn p-cta" id="cta">Connect</button>
<p class="p-note" id="p-note">Live demo: it runs in this page and connects nothing. <a href="download.html">Get the real app</a></p>
</section>
<div class="dash">
<section class="tile steps-tile" id="steps" hidden aria-live="polite"><div class="dash-h"><h2>Building your secure connection</h2><span class="val" id="pct">0%</span></div><ol class="steps" id="step-list"></ol></section>
<div class="bento">
''' + stat("down", "Download", "s-down", "0 B/s", "s-down-t", "0 B total", spark=True)
    + stat("up", "Upload", "s-up", "0 B/s", "s-up-t", "0 B total", spark=True)
    + stat("clock", "Session", "s-time", "00:00:00", "s-time-s", "Not started", mono=True)
    + stat("spark", "Gateway", "s-gw", "&ndash;", "s-gw-s", "Found by the scan", mono=True) + '''
</div>
<section class="tile route-tile" aria-labelledby="route-h">
<div class="dash-h" style="margin-bottom:12px"><h2 id="route-h">Route</h2></div>
<div class="choices" id="routes" role="group" aria-label="Route">''' + route_choices + '''</div>
<p class="hint" id="route-hint">Try WireGuard, MASQUE, MASQUE&sup2;, and Gool in order. Keep the first route that connects.</p>
<div id="carrier-box" hidden><h3 class="lbl">Carrier</h3><div class="seg" id="carrier" role="group" aria-label="Carrier"><button type="button" data-c="h2" aria-pressed="true">HTTP/2</button><button type="button" data-c="h3" aria-pressed="false">HTTP/3</button></div></div>
<pre><code id="route-cmd">oryvexcore --protocol auto --scan balanced</code></pre>
</section>
</div>
</div>

<section class="sec" aria-labelledby="act-h">
''' + sec("list", '<span id="act-h">Activity</span>', '<div class="seg" id="log-tabs" role="group" aria-label="Log filter" style="margin-left:auto"><button type="button" data-f="core" aria-pressed="true">Core</button><button type="button" data-f="problems" aria-pressed="false">Problems</button></div>') + '''
<div class="log" id="log" role="log" aria-label="Demo core log"><div><span class="t">--:--:--</span><span class="l">INFO</span><span class="dim">[=] OryvexCore idle. Press Connect to watch a route come up.</span></div></div>
</section>

<section class="sec" aria-labelledby="get-h">
''' + sec("download", '<span id="get-h">Get the app</span>') + '''
<div class="group">
<a class="row" href="@REL@"><span class="ico">{{i:android}}</span><div class="row-main"><div class="row-t">Android 5.0+</div><div class="row-s">Whole-device VPN or proxy only. Not sure which APK? arm64-v8a.</div></div>{{i:chev chev}}</a>
<a class="row" href="@REL@"><span class="ico">{{i:windows}}</span><div class="row-main"><div class="row-t">Windows 10 / 11</div><div class="row-s">Desktop app with system proxy, Tor and Psiphon bundled.</div></div>{{i:chev chev}}</a>
<a class="row" href="@REL@"><span class="ico">{{i:monitor}}</span><div class="row-main"><div class="row-t">Windows 7 / 8 Lite</div><div class="row-s">A tiny native Win32 app, 32 and 64-bit.</div></div>{{i:chev chev}}</a>
<a class="row" href="download.html"><span class="ico">{{i:terminal}}</span><div class="row-main"><div class="row-t">Linux, macOS, OpenWrt, Termux, Docker</div><div class="row-s">The core on its own, one command to install.</div></div>{{i:chev chev}}</a>
</div>
</section>

<section class="sec" aria-labelledby="in-h">
''' + sec("layers", '<span id="in-h">What&rsquo;s inside</span>') + '''
<div class="grid">
<a class="tile" href="about.html"><span class="ico ico-lg">{{i:radar}}</span><h3>Finds its own way out</h3><p>Scans for gateways and trusts one only after real traffic passes.</p><span class="more">About{{i:arrow}}</span></a>
<a class="tile" href="tor.html"><span class="ico ico-lg">{{i:onion}}</span><h3>Tor, built in</h3><p>Arti inside the core. Auto, Fastest or the exit country you pick.</p><span class="more">Tor{{i:arrow}}</span></a>
<a class="tile" href="app.html"><span class="ico ico-lg">{{i:smartphone}}</span><h3>One app, two screens</h3><p>The same design on Windows and Android, phone to widescreen.</p><span class="more">See the app{{i:arrow}}</span></a>
<a class="tile" href="docs.html"><span class="ico ico-lg">{{i:terminal}}</span><h3>Scriptable</h3><p>Every option is a flag or an environment variable.</p><span class="more">Docs{{i:arrow}}</span></a>
</div>
</section>''')

# ---------------------------------------------------------------- about
PAGES["about.html"] = ("about", "About",
"What OryvexVPN does: auto route, built-in Tor, exit choice, fingerprint resistance and real scanning.",
head("Why it exists", "Built for networks that fight back.",
     "Deep packet inspection, fingerprinting, UDP throttling, blocked endpoints. OryvexCore scans, verifies real HTTPS traffic before it says Connected, and serves the tunnel as a SOCKS5 proxy or a whole-device VPN.") + '''
<div class="grid-3">
<div class="tile lit"><span class="ico ico-lg">{{i:route}}</span><h3>Auto route</h3><p>Tries WireGuard, then MASQUE, MASQUE&sup2; and Gool, and keeps the first one that passes real traffic.</p></div>
<div class="tile"><span class="ico ico-lg">{{i:onion}}</span><h3>Tor, built in</h3><p>Arti (Rust Tor) inside the core on Windows and Android. Bridges fetched for you when Tor is blocked.</p></div>
<div class="tile"><span class="ico ico-lg">{{i:globe}}</span><h3>Pick your exit</h3><p>Auto, Fastest (measured on connect) or a country. The exit list is fetched through Tor itself, never over your filtered line.</p></div>
<div class="tile"><span class="ico ico-lg">{{i:eye-off}}</span><h3>Hard to fingerprint</h3><p>Chrome-shaped TLS, ClientHello fragmentation and obfuscation profiles from light to GFW.</p></div>
<div class="tile"><span class="ico ico-lg">{{i:radar}}</span><h3>Real scanning</h3><p>Five scan modes from turbo to ironclad. Ironclad opens a full tunnel and sends a real request before trusting a gateway.</p></div>
<div class="tile"><span class="ico ico-lg">{{i:plug}}</span><h3>Proxy or VPN</h3><p>A SOCKS5 proxy on <code>127.0.0.1:1819</code>, automatic Windows system proxy for Bypass, or whole-device routing through Android VPN.</p></div>
</div>

<section class="sec">
''' + sec("layers", "Ways through") + '''
<div class="grid">
<div class="tile"><span class="ico ico-lg">''' + proto("masque") + '''</span><h3>MASQUE</h3><p>Traffic hides inside an encrypted connection that looks like ordinary web traffic, over HTTP/3 or HTTP/2.</p></div>
<div class="tile"><span class="ico ico-lg">''' + proto("wg") + '''</span><h3>WireGuard</h3><p>Lean and very fast. Best on networks that block known addresses but don&rsquo;t look closely at traffic shape.</p></div>
<div class="tile"><span class="ico ico-lg">''' + proto("mim") + '''</span><h3>MASQUE&sup2;</h3><p>MASQUE carried inside MASQUE, for a different exit address.</p></div>
<div class="tile"><span class="ico ico-lg">''' + proto("gool") + '''</span><h3>Gool</h3><p>Tunnel in a tunnel: WireGuard inside MASQUE, or inside WireGuard. Slower, but it can be the difference.</p></div>
</div>
</section>

<section class="sec">
''' + sec("zap", "Bypass, no tunnel") + '''
<div class="tile"><p>A direct route that reshapes the first packets of every connection and resolves names itself, so filters that read the site name are fooled. Your address stays the same. Beats packet-by-packet filters and DNS blocking, not filters that block by address. Windows and Android, <code>--bypass</code>.</p></div>
<section class="sec" id="bypass-list" aria-labelledby="bl-h">
<h3 id="bl-h">Bypass list</h3>
<p class="muted">Services with built-in handling. They open where the network filters site names or DNS, not where it blocks addresses. Other sites are tried automatically too.</p>
<div class="svc-grid">''' + BYPASS_LIST_HTML + '''</div>
</section>
<div class="grid-2 platform-grid" aria-label="Bypass platform support">
<article class="tile">
<div class="platform-head"><img class="platform-mark" src="assets/platforms/windows.svg" width="28" height="28" alt=""><h3>Windows</h3></div>
<p><b>Windows 10/11, x64:</b> Desktop app. <b>Windows 7/8/10/11, x86 and x64:</b> OryvexVPN Lite.</p>
<p>Bypass automatically enables the per-user Windows system proxy and restores the previous setting when disconnected. It routes apps that honor Windows proxy settings; apps that ignore them still need an explicit proxy.</p>
</article>
<article class="tile">
<div class="platform-head"><img class="platform-mark" src="assets/platforms/android.svg" width="28" height="28" alt=""><h3>Android 5.0+</h3></div>
<p>The Android app supports Bypass on its shipped ABIs: arm64-v8a, armeabi-v7a and x86_64. Enable <b>Whole-device VPN</b> to route device traffic; Android asks for its standard VPN permission.</p>
</article>
</div>
<div class="note">{{i:terminal}}<p><b>Linux and macOS:</b> the CLI can run Bypass when both <code>oryvexcore</code> and a native <code>oryvex-bypass</code> engine are built/installed. Use the local proxy from clients; there is no bundled GUI or whole-system Bypass VPN.</p></div>
</section>''')

# ---------------------------------------------------------------- guide
PAGES["guide.html"] = ("guide", "How to use",
"Install OryvexVPN, pick a route, connect. Proxy mode and what to do when it won't connect.",
head("How to use", "Three taps to connected.",
     "Install, pick a route, connect. The defaults are good; change them only when your network pushes back.") + '''
<div class="tile">
<ol class="steps big">
<li><span class="dot"></span><div><div class="s-t">Install</div><div class="s-d">Android: the APK for your phone (arm64-v8a for most). Windows: unzip and run <code>OryvexVPN.exe</code>.</div></div></li>
<li><span class="dot"></span><div><div class="s-t">Pick a route</div><div class="s-d">Leave it on <b>Auto</b>, or choose <b>Tor</b> for the Tor network with no tunnel underneath.</div></div></li>
<li><span class="dot"></span><div><div class="s-t">Choose a Tor exit <span class="badge">Tor route only</span></div><div class="s-d"><b>Auto</b>, <b>Fastest</b>, or a <b>Country</b> such as Germany or Netherlands. <a href="tor.html#exits">Try the picker</a></div></div></li>
<li><span class="dot"></span><div><div class="s-t">Connect</div><div class="s-d">The app shows each stage live and reports Connected when the core says the selected route and proxy are ready. <a href="index.html#connect">Watch it in the demo</a></div></div></li>
</ol>
</div>

<section class="sec">
''' + sec("plug", "Point any app at it") + '''
<div class="tile">
<p>The core serves a SOCKS5 proxy. Use <code>socks5h</code> so DNS goes through the selected route too. In Windows Bypass mode, the app also enables the Windows system HTTP proxy automatically. On Android, enable <b>Whole-device VPN</b> for device-wide routing.</p>
<pre><code>socks5h://127.0.0.1:1819</code></pre>
<p>For tunnel routes, seeing <code>warp=on</code> means traffic is passing through WARP. Bypass is direct and does not change your exit address.</p>
<pre><code>curl -x socks5h://127.0.0.1:1819 https://www.cloudflare.com/cdn-cgi/trace</code></pre>
</div>
</section>

<section class="sec">
''' + sec("alert", "When it won&rsquo;t connect") + '''
<p class="muted">Turn it up one step at a time.</p>
<div class="group">
<div class="row"><span class="ico">{{i:wifi-off}}</span><div class="row-main"><div class="row-t">Nothing connects</div><div class="row-s">Switch MASQUE to HTTP/2. If that handshake is blocked too, add ClientHello fragmentation. Then try WireGuard or classic Gool.</div></div></div>
<div class="row"><span class="ico">{{i:refresh}}</span><div class="row-main"><div class="row-t">Connects, then drops</div><div class="row-s">Take the obfuscation profile one step heavier: <code>gfw</code> for MASQUE, <code>aggressive</code> for WireGuard.</div></div></div>
<div class="row"><span class="ico">{{i:clock}}</span><div class="row-main"><div class="row-t">Scan is slow</div><div class="row-s">Use the turbo scan, and say yes to reconnecting to your last working gateway.</div></div></div>
<a class="row" href="tor.html#bridges"><span class="ico">{{i:onion}}</span><div class="row-main"><div class="row-t">Tor is blocked</div><div class="row-s">Bridges are fetched for you. Or run Tor through the tunnel.</div></div>{{i:chev chev}}</a>
</div>
</section>''')

# ---------------------------------------------------------------- app
SHOTS = [
    ("connected", "Connected", "desktop-connected.jpg", 1600, 1086, "Connect: the orb, live numbers and the route, side by side."),
    ("connecting", "Connecting", "desktop-connecting.jpg", 1600, 1086, "Every stage of the chosen route, live, while it comes up."),
    ("settings", "Settings", "desktop-settings.jpg", 1600, 1000, "Settings grouped like the system ones: proxy, routes, advanced."),
    ("activity", "Activity", "desktop-activity.jpg", 1600, 1086, "The core&rsquo;s log with level tags, folded repeats and one-tap copy."),
    ("phone", "Android", "phone-connected.jpg", 600, 1298, "Android: the same app, as a whole-device VPN."),
]
shot_tabs = "".join(f'<button type="button" data-shot="{k}" aria-pressed="{str(n == 0).lower()}">{label}</button>' for n, (k, label, *_r) in enumerate(SHOTS))
shot_data = "".join(f'<template data-shot="{k}" data-cap="{cap}"><img src="assets/shots/{f}" width="{w}" height="{h}" alt="OryvexVPN {label} screen"></template>' for k, label, f, w, h, cap in SHOTS)

PAGES["app.html"] = ("app", "App",
"The OryvexVPN app for Windows and Android: one design, live connection stages, activity log, updates.",
head("App", "One blue. One canvas.", "Same design on Windows and Android, responsive from small phones to wide desktops.") + '''
<section class="tile shot-tile" id="shots">
<div class="seg scroll" role="group" aria-label="Screen">''' + shot_tabs + '''</div>
<div class="shot" id="shot" style="margin-top:14px"><img src="assets/shots/desktop-connected.jpg" width="1600" height="1086" alt="OryvexVPN Connected screen"></div>
<div class="shot-cap"><p id="shot-cap">Connect: the orb, live numbers and the route, side by side.</p><a class="link" href="index.html#connect">Try the Connect page live{{i:chev}}</a></div>
''' + shot_data + '''
</section>

<section class="sec">
''' + sec("grid", "Built in") + '''
<div class="grid-3">
<div class="tile"><span class="ico ico-lg">{{i:list}}</span><h3>Live stages</h3><p>Identity, gateway scan, tunnel, proxy, then Tor, Psiphon or the device VPN when they apply.</p></div>
<div class="tile"><span class="ico ico-lg">{{i:terminal}}</span><h3>Activity</h3><p>The core&rsquo;s log with level tags, folded repeats and one-tap copy.</p></div>
<div class="tile"><span class="ico ico-lg">{{i:refresh}}</span><h3>Updates</h3><p>Checks GitHub for a newer release, through the tunnel when connected, and says so.</p></div>
<div class="tile"><span class="ico ico-lg">{{i:type}}</span><h3>No network fonts</h3><p>Inter and JetBrains Mono ship inside the app. Nothing loads from outside.</p></div>
<div class="tile"><span class="ico ico-lg">{{i:moon}}</span><h3>Ink and paper</h3><p>Dark and light appearances, one switch in Settings. This site has it too, top right.</p></div>
<div class="tile"><span class="ico ico-lg">{{i:lock}}</span><h3>Never looks you up</h3><p>Connected means the core reported tunnel and proxy up. The app never asks for your IP or country.</p></div>
</div>
</section>''')

# ---------------------------------------------------------------- tor
TOR_EXITS = "de nl us fr se ch fi ro at lu no gb ca pl cz is md bg dk es it lt lv ee ua hu sg jp hk au br in za tr rs tw vn pe az be ie pt gr sk si hr il kr nz ar cl mx cr pa ru kz th my id ph ae cy mt li sc bz gi ge am al mk ba ec co uy by".split()

def country_names():
    f = ROOT / "apps" / "shared" / "lib" / "src" / "core" / "country_names.dart"
    try:
        return {k.lower(): v for k, v in re.findall(r"'([A-Z]{2})': '([^']+)'", f.read_text(encoding="utf-8"))}
    except OSError:
        return {}

def flag_buttons():
    names = country_names()
    out = []
    for n, cc in enumerate(TOR_EXITS):
        name = names.get(cc, cc.upper()).replace("&", "&amp;")
        extra = ' data-extra' if n >= 12 else ""
        out.append(f'<button type="button" class="flag" data-c="{cc}" aria-pressed="{str(cc == "de").lower()}"{extra}><img src="assets/flags/{cc}.png" alt="" width="24" height="18" loading="lazy"><span>{name}</span></button>')
    return "".join(out)

ARROW = "{{i:arrow}}"
def hops(*names):
    return '<div class="hops">' + ARROW.join(f'<span class="hop{" tor" if n == "Tor" else ""}">{n}</span>' for n in names) + "</div>"

PAGES["tor.html"] = ("tor", "Tor",
"Tor in OryvexVPN: Tor alone, Tor through the tunnel, or the tunnel through Tor, with exit-country choice and bridges.",
head("Tor", "Tor, built in.", "Arti, the Rust implementation of Tor, runs inside OryvexCore. Use it on its own, inside the tunnel, or carry the tunnel through it.") + '''
<div class="grid-3">
<div class="tile"><h3>Tor alone</h3><p>No tunnel, no WARP identity. The proxy is plain Tor. In the apps this is the <b>Tor</b> route.</p>''' + hops("You", "Tor", "Internet") + '''<pre><code>oryvexcore --tor-only</code></pre></div>
<div class="tile"><h3>Tor through the tunnel</h3><p>Tor rides inside WARP, so a network that blocks Tor never sees it. Tor proxy on <code>127.0.0.1:1820</code>.</p>''' + hops("You", "WARP", "Tor", "Internet") + '''<pre><code>oryvexcore --masque --tor</code></pre></div>
<div class="tile"><h3>The tunnel through Tor</h3><p>Tor first, then WARP is dialled through it. You leave from a WARP exit. MASQUE over HTTP/2 only.</p>''' + hops("You", "Tor", "WARP", "Internet") + '''<pre><code>oryvexcore --masque --tor-reverse</code></pre></div>
</div>
<div class="tile" style="margin-top:16px"><h3>Check you&rsquo;re on Tor</h3><p>Ask the Tor Project which address it sees.</p><pre><code>curl -x socks5h://127.0.0.1:1820 https://check.torproject.org/api/ip</code></pre></div>

<section class="sec doc-sec" id="exits">
''' + sec("globe", "Leave from where you want", '<span class="badge">' + str(len(TOR_EXITS)) + ' countries</span>') + '''
<div class="tile exit-tile" id="exit-picker">
<h3 class="lbl" style="font-size:16px;margin-bottom:8px">Tor exit</h3>
<div class="seg" role="group" aria-label="Exit mode"><button type="button" data-m="auto" aria-pressed="false">{{i:globe}}Auto</button><button type="button" data-m="fastest" aria-pressed="false">{{i:zap}}Fastest</button><button type="button" data-m="country" aria-pressed="true">{{i:route}}Country</button></div>
<p class="muted" id="exit-hint" aria-live="polite" style="margin:0">Choose the exit country. Tor identifies each relay using its built-in GeoIP data.</p>
<div id="exit-country"><div class="flags" id="flags">''' + flag_buttons() + '''</div>
<button type="button" class="link" id="flags-all" style="margin-top:14px">Show all ''' + str(len(TOR_EXITS)) + ''' countries{{i:chev}}</button></div>
<div class="exit-foot"><div class="row-main"><div class="row-t" style="font-size:15px">Strict exit</div>Fail instead of leaving from another country.</div><button type="button" class="switch" role="switch" aria-checked="false" id="strict" aria-label="Strict exit"></button></div>
<pre style="margin-top:16px"><code id="exit-cmd">oryvexcore --tor-only --tor-exit de</code></pre>
</div>
''' + rows([
    ("--tor-exit auto", "Default. Tor picks an exit itself, weighted by bandwidth."),
    ("--tor-exit fastest", "On every connect, tests exits in the 6 best-served countries and keeps the quickest."),
    ("--tor-exit de,nl,se", "Leave from that country, first that answers."),
    ("--tor-exit-strict", "Fail instead of falling back to another country."),
], head=("Value", "What happens")).replace('class="group"', 'class="group" style="margin-top:16px"') + '''
<div class="note" style="margin-top:16px">{{i:info}}<p>The exit list is only ever fetched <b>through Tor itself</b>, then cached in <code>&lt;tor-dir&gt;/exits.json</code>. Until then a bundled list of 32 exit countries is used, resolved locally by Arti&rsquo;s GeoIP table.</p></div>
</section>

<section class="sec doc-sec" id="bridges">
''' + sec("bridge", "When Tor itself is blocked") + '''
<p class="muted">OryvexCore tries Tor plainly for a moment, then fetches bridges and pluggable transports on its own. You can bring your own too.</p>
<pre><code>oryvexcore --tor-only \\
  --tor-bridge "obfs4 192.0.2.55:38114 FINGERPRINT cert=... iat-mode=0" \\
  --tor-pt /usr/bin/lyrebird</code></pre>
''' + rows([
    ("--tor-bind<small>127.0.0.1:1820</small>", "The Tor proxy address"),
    ("--tor-dir<small>&lt;config&gt;-tor</small>", "Directory cache and state"),
    ("--tor-bridge<small>fetched as needed</small>", "Bridge lines; repeat for more"),
    ("--tor-bridge-file", "Your own bridge lines from a file"),
    ("--tor-bridges", "Go to bridges at once"),
    ("--no-tor-bridges", "Never use bridges"),
    ("--tor-pt<small>found on its own</small>", "Pluggable transport binaries"),
    ("--tor-pt-dir<small>pt/ beside the binary</small>", "Another folder to search"),
], head=("Flag (default)", "What it does")) + '''
</section>

<section class="sec doc-sec" id="source">
''' + sec("code", "Where Tor lives in the code") + '''
<div class="note">{{i:info}}<p>Tor is a <b>cargo feature</b>, off by default. Plain <code>cargo build</code> gives a core with no Tor. Build with <code>scripts/build-core.sh</code> (what CI and Docker use) or <code>--features tor,tor-exit-country</code>.</p></div>
<pre><code>cd oryvexcore
bash scripts/build-core.sh cargo build --release   <span class="c"># tor + exit country, falls back on tor</span>
cargo build --release --features tor,tor-exit-country</code></pre>
<div class="group">
''' + "".join(f'<a class="row kv" href="@REPO@/blob/main/{p}"><div class="key">{short}</div><div class="row-main row-s">{d}</div>{{{{i:chev chev}}}}</a>' for p, short, d in [
    ("oryvexcore/src/tor.rs", "oryvexcore/src/tor.rs", "The Arti client: modes (alone, through, reverse), bootstrap, the 1820 proxy"),
    ("oryvexcore/src/tor_exits.rs", "oryvexcore/src/tor_exits.rs", "Exit-country choice: auto, fastest, country list, cache"),
    ("oryvexcore/src/bridges.rs", "oryvexcore/src/bridges.rs", "Bridge fetching and pluggable transports"),
    ("oryvexcore/src/cli.rs", "oryvexcore/src/cli.rs", "The <code>--tor*</code> flags"),
    ("oryvexcore/Cargo.toml", "oryvexcore/Cargo.toml", "The <code>tor</code> and <code>tor-exit-country</code> features (arti-client 0.46)"),
    ("oryvexcore/scripts/pt-build.sh", "oryvexcore/scripts/pt-build.sh", "Builds the pluggable transports shipped in <code>pt/</code>"),
    ("apps/shared/lib/src/ui/widgets/tor_exit_picker.dart", "apps/shared/.../tor_exit_picker.dart", "The exit picker in the Windows and Android apps"),
    ("oryvexcore/tor/exit-nodes.txt", "oryvexcore/tor/exit-nodes.txt", "Latest Tor exit IPs from the Tor Project, refresh with <code>tools/update-tor-exits.sh</code>"),
    ("docs/TOR.md", "docs/TOR.md", "Tor route and exit selection notes"),
]) + '''
</div>
</section>''')

# ---------------------------------------------------------------- docs
DOC_TOC = [("start", "Run it"), ("transports", "Transports"), ("scan", "Scanning"), ("noise", "Obfuscation"),
           ("h2", "HTTP/2 vs 3"), ("tor", "Tor"), ("flags", "Flags"), ("docker", "Docker"), ("help", "Troubleshooting")]

PAGES["docs.html"] = ("docs", "Docs",
"OryvexCore command line: transports, scanning, obfuscation, HTTP/2 vs HTTP/3, Tor, flags and Docker.",
head("Docs", "Command line.", "Every prompt has a flag, every flag has an environment variable. Mix them however you like.") + '''
<nav class="seg scroll toc docs-toc" aria-label="On this page">''' + "".join(f'<a href="#{k}">{v}</a>' for k, v in DOC_TOC) + '''</nav>
<section class="tile doc-sec" id="start">''' + sec("terminal", "Run it") + '''
<p class="muted">With no arguments, OryvexCore asks its questions one by one. Flags skip them.</p>
<pre><code>oryvexcore                                 <span class="c"># answer the questions as they come</span>
oryvexcore --masque --turbo -4             <span class="c"># straight to work</span>
oryvexcore --tor-only --tor-exit fastest   <span class="c"># plain Tor, fastest exit country</span>
oryvexcore --tor-only --tor-exit de,nl     <span class="c"># Germany, else Netherlands</span>
oryvexcore --wg --tor --tor-exit se        <span class="c"># Tor inside WireGuard, exit in Sweden</span>
oryvexcore help                            <span class="c"># every flag and variable</span></code></pre>
</section>
<section class="tile doc-sec" id="transports">''' + sec("layers", "Transports") + rows([
    ("--masque", "<b>MASQUE</b>: the default. Looks like ordinary web traffic. Start here."),
    ("--wg", "<b>WireGuard</b>: least overhead, fastest when it works."),
    ("--gool", "<b>Gool over MASQUE</b>: WireGuard inside MASQUE, for a different exit address."),
    ("--gool-classic", "<b>Classic Gool</b>: WireGuard inside WireGuard, two layers. Use when plain WireGuard is unstable."),
]) + '''</section>
<section class="tile doc-sec" id="scan">''' + sec("radar", "Scanning") + '''
<p class="muted">No address is hard-coded. OryvexCore measures real responses and picks the best gateway.</p>''' + rows([
    ("turbo", "You want to connect fast; first answer wins"),
    ("balanced", "Default, good for most networks"),
    ("thorough", "You want the best ping, can wait"),
    ("stealth", "You want less noise on the network"),
    ("ironclad", "Gateways looked fine but never passed traffic"),
], head=("Mode", "Use it when")) + '''</section>
<section class="tile doc-sec" id="noise">''' + sec("eye-off", "Obfuscation") + rows([
    ("MASQUE, Gool", "<code>firewall</code> (default), <code>gfw</code> (heavier), <code>off</code>"),
    ("WireGuard, classic Gool", "<code>balanced</code> (default), <code>aggressive</code>, <code>light</code>, <code>off</code>"),
]) + '''<p class="muted" style="margin:14px 0 0">Start on the default. Didn&rsquo;t connect or kept dropping? Go one step heavier.</p></section>
<section class="tile doc-sec" id="h2">''' + sec("zap", "HTTP/2 vs HTTP/3") + '''
<p class="muted">MASQUE uses HTTP/3 (QUIC over UDP) by default. If your network throttles UDP, switch to HTTP/2 over TCP. If the HTTP/2 handshake gets blocked, fragment the ClientHello.</p>
<pre><code>oryvexcore --h2
oryvexcore --h2 --fragment --fragment-size 8-24 --fragment-delay 5-15</code></pre>
</section>
<section class="tile doc-sec" id="tor">''' + sec("onion", "Tor") + '''
<p class="muted">Three modes, exit choice and bridges are covered on the <a href="tor.html">Tor page</a>.</p>
<pre><code>oryvexcore --tor-only                   <span class="c"># Tor alone</span>
oryvexcore --masque --tor               <span class="c"># Tor through the tunnel, Tor on :1820</span>
oryvexcore --masque --tor-reverse       <span class="c"># the tunnel through Tor</span></code></pre>
</section>
<section class="tile doc-sec" id="flags">''' + sec("sliders", "Common flags") + rows([
    ("--bind &lt;addr&gt;", "SOCKS5 listen address, default <code>127.0.0.1:1819</code>"),
    ("-4 / -6 / --dual", "Scan IPv4, IPv6 or both"),
    ("--peer &lt;ip:port&gt;", "Force a gateway and skip scanning"),
    ("--scan &lt;mode&gt;", "turbo, balanced, thorough, stealth, ironclad"),
    ("--noize &lt;profile&gt;", "Obfuscation profile"),
    ("--h2", "MASQUE over HTTP/2"),
    ("--fragment", "Fragment the TLS ClientHello"),
    ("--quick-reconnect", "Always reuse the last working gateway"),
    ("--tor-exit auto|fastest|cc", "Where Tor leaves from"),
    ("--tor-exit-strict", "Fail instead of leaving elsewhere"),
    ("--tor-bridge-file", "Your own bridge lines"),
    ("--bypass", "Direct route with reshaped first packets, no tunnel (Windows and Android apps; Windows app configures its system proxy automatically)"),
], head=("Flag", "What it does")) + '''</section>
<section class="tile doc-sec" id="docker">''' + sec("box", "Docker") + '''
<div class="note">{{i:alert}}<p>The SOCKS5 proxy has no authentication. Publish it on <code>127.0.0.1</code> only, or anyone on your network can use your tunnel.</p></div>
<pre><code>docker run -it -p 127.0.0.1:1819:1819 -v oryvexcore-data:/data \\
  -e ORYVEXCORE_PROTOCOL=masque \\
  ghcr.io/oryvexofficial/oryvexvpn:latest</code></pre>
</section>
<section class="tile doc-sec" id="help">''' + sec("alert", "Troubleshooting") + '''
<div class="group" style="margin-bottom:16px">
<div class="row"><div class="row-main"><div class="row-t">No connection at all</div><div class="row-s">MASQUE on h2, then <code>--fragment</code>, then WireGuard or classic Gool.</div></div></div>
<div class="row"><div class="row-main"><div class="row-t">Connects but nothing loads</div><div class="row-s">The data check rejects that gateway and keeps scanning on its own.</div></div></div>
<div class="row"><div class="row-main"><div class="row-t">Keeps dropping</div><div class="row-s">Heavier obfuscation profile.</div></div></div>
<div class="row"><div class="row-main"><div class="row-t">Slow</div><div class="row-s">Drop from Gool to a single tunnel; try h3 if UDP is open.</div></div></div>
</div>
<p class="muted" style="margin:0">Full reference: <a href="@REPO@/blob/main/docs/DOCS.md">DOCS.md</a> &middot; <a href="@REPO@/blob/main/docs/GUIDE.md">Guide</a> &middot; <a href="@REPO@/blob/main/docs/OPENWRT.md">OpenWrt</a></p>
</section>''')

# ---------------------------------------------------------------- creator
PAGES["creator.html"] = ("creator", "Creator",
"OryvexVPN is free software by Muvixo, under the AGPL-3.0.",
head("Creator", "Made by Muvixo.", "Free software under the AGPL-3.0. MASQUE on Cloudflare&rsquo;s quiche, Tor on Arti.") + '''
<div class="group">
<a class="row" href="@REPO@"><span class="ico">{{i:github}}</span><div class="row-main"><div class="row-t">Open source</div><div class="row-s">Every line of the core and the apps is on GitHub.</div></div>{{i:chev chev}}</a>
<a class="row" href="@REPO@/blob/main/LICENSE"><span class="ico">{{i:book}}</span><div class="row-main"><div class="row-t">License</div><div class="row-s">AGPL-3.0. Third-party notices ship with every build.</div></div>{{i:chev chev}}</a>
<div class="row"><span class="ico">{{i:layers}}</span><div class="row-main"><div class="row-t">Built on</div><div class="row-s">quiche for MASQUE, Arti for Tor, Flutter for the apps, Rust for the core.</div></div></div>
</div>
''')

# ---------------------------------------------------------------- download
PAGES["download.html"] = ("download", "Download",
"Download OryvexVPN for Android, Windows 10/11, Windows 7/8, Linux, macOS, OpenWrt and Docker.",
head("Download", "Get OryvexVPN.", "Every build comes from GitHub Actions, straight from the source.",
     '<a class="btn" href="@REL@">{{i:download}}Latest release</a>') + '''
<div class="group">
<div class="row"><span class="ico">{{i:android}}</span><div class="row-main"><div class="row-t">Android 5.0+</div><div class="row-s">arm64-v8a, armeabi-v7a, x86_64 or universal APK. Not sure? Take arm64-v8a.</div></div><a class="btn sm" href="@REL@">APK</a></div>
<div class="row"><span class="ico">{{i:windows}}</span><div class="row-main"><div class="row-t">Windows 10 / 11</div><div class="row-s">Desktop app with Tor, transports and Psiphon bundled.</div></div><a class="btn sm" href="@REL@">Windows x64</a></div>
<div class="row"><span class="ico">{{i:monitor}}</span><div class="row-main"><div class="row-t">Windows 7 / 8 Lite</div><div class="row-s">Tiny native app, 32 and 64-bit.</div></div><a class="btn sm quiet" href="@REL@">Legacy</a></div>
<div class="row"><span class="ico">{{i:box}}</span><div class="row-main"><div class="row-t">CLI &amp; Docker</div><div class="row-s">Linux, macOS, OpenWrt, Termux and a ghcr.io image.</div></div><a class="btn sm quiet" href="@REL@">All builds</a></div>
</div>

<section class="sec">
''' + sec("terminal", "Linux, macOS, Termux") + '''
<pre><code>curl -fsSL https://raw.githubusercontent.com/oryvexofficial/OryvexVPN/main/oryvexcore/scripts/oryvexcore.sh -o oryvexcore.sh
bash oryvexcore.sh</code></pre>
<p class="muted">OpenWrt routers have their own guide: <a href="@REPO@/blob/main/docs/OPENWRT.md">OPENWRT.md</a></p>
</section>''')

# 404 is served by GitHub Pages at ANY missing path (/OryvexCore/a/b/c), so relative links and
# styles would break there. The page carries its CSS and logo inline, then finds the site root:
# on a project site that is /<repo>/, on a custom domain or user site it is /.
ROOT_SCRIPT = """<script>(function(){
var seg=location.pathname.split('/')[1]||'';
var routePages={about:1,app:1,creator:1,docs:1,download:1,guide:1,tor:1};
function apply(root){
  var a=document.querySelectorAll('[data-href]');
  for(var k=0;k<a.length;k++){a[k].setAttribute('href',root+a[k].getAttribute('data-href'));}
  var css=document.createElement('link');css.rel='stylesheet';css.href=root+'style.css';document.head.appendChild(css);
  var ico=document.createElement('link');ico.rel='icon';ico.type='image/svg+xml';ico.href=root+'assets/logo.svg';document.head.appendChild(ico);
  var js=document.createElement('script');js.src=root+'app.js';document.body.appendChild(js);
}
function ready(f){document.readyState==='loading'?document.addEventListener('DOMContentLoaded',f):f();}
if(!seg){ready(function(){apply('/');});return;}
var done=false;function go(r){
  if(done)return;done=true;
  var relative=r==='/'?location.pathname.replace(/^\\/+/, ''):location.pathname.slice(r.length);
  var slug=relative.replace(/^\\/+|\\/+$/g,'');
  if(routePages[slug]){location.replace(r+slug+'.html'+location.search+location.hash);return;}
  ready(function(){apply(r);});
}
try{fetch('/'+seg+'/app.js',{method:'HEAD',cache:'no-store'}).then(function(r){go(r.ok?'/'+seg+'/':'/');},function(){go('/');});}catch(e){go('/');}
setTimeout(function(){go('/');},2500);
})();</script>
"""

PAGES["404.html"] = ("404", "Page not found",
"This page doesn't exist on the OryvexVPN site.",
'''<section class="lost"><div>
<div class="orb panel-404" aria-hidden="true">''' + ORB_SVG + '''</div>
<span class="eyebrow">Error 404</span>
<h1>No Route.</h1>
<p class="lead" style="margin:12px auto 0">This page moved, or it never existed.</p>
<div class="log" aria-hidden="true"><div><span class="t">scan</span><span class="dim">this address</span><span class="bad">no answer</span></div><div><span class="t">scan</span><span class="dim">home page&nbsp;&nbsp;&nbsp;</span><span class="ok">200 OK</span></div></div>
<div class="actions"><a class="btn" href="index.html">{{i:home}}Back home</a><a class="btn quiet" href="docs.html">{{i:book}}Docs</a><a class="btn quiet" href="download.html">{{i:download}}Download</a></div>
</div></section>''', ROOT_SCRIPT)


def clean_links(html):
    """Keep explicit static-page filenames; only the site's root maps to index.html."""
    html = re.sub(r'href="index\.html(#[^"]*)?"', lambda m: 'href="./' + (m.group(1) or '') + '"', html)
    return html


def make_404(html, css, mark):
    # every internal link gets a root-relative fallback plus data-href for the root finder
    def fix(m):
        url = m.group(1)
        if re.match(r'(https?:|mailto:|#|data:)', url):
            return m.group(0)
        rel = "" if url == "./" else url
        return f'href="/{rel}" data-href="{rel}"'
    html = re.sub(r'href="([^"]*)"', lambda m: m.group(0) if 'rel="stylesheet"' in m.group(0) else fix(m), html)
    # no external CSS/fonts/icons in <head>: the root finder adds them once it knows the root
    html = re.sub(r'<link rel="(icon|apple-touch-icon|preload|stylesheet)"[^>]*>\n', "", html)
    html = re.sub(r'<meta property="og:image"[^>]*>\n', "", html)
    html = html.replace('<script src="app.js?v=bypass3"></script>\n', "")
    inline = re.sub(r'@font-face\{[^}]*\}\n?', "", css)
    inline = re.sub(r'/\*.*?\*/', "", inline, flags=re.S)
    html = html.replace("</head>", f"<style>{inline}</style>\n</head>")
    count = [0]
    def copy(size):
        # the mark is inlined several times: give each copy its own gradient ids
        count[0] += 1
        m = re.sub(r'(id="|url\(#)(ox[A-Za-z]+)', lambda g: f"{g.group(1)}{g.group(2)}{count[0]}", mark)
        # only the root <svg>: the tile <rect> inside has the same width/height
        return m.replace('width="512" height="512"', f'width="{size}" height="{size}" aria-hidden="true" focusable="false"', 1)
    return re.sub(r'<img src="/?assets/mark\.svg"[^>]*>', lambda _: copy(28), html)


def main():
    css = (SITE / "style.css").read_text(encoding="utf-8")
    mark = (SITE / "assets" / "mark.svg").read_text(encoding="utf-8")
    mark = re.sub(r"<title>.*?</title>\s*", "", mark).strip()
    mark = re.sub(r"<!--.*?-->\s*", "", mark, flags=re.S)
    for fname, spec in PAGES.items():
        key, title, desc, body = spec[:4]
        extra = spec[4] if len(spec) > 4 else ""
        html = clean_links(expand(page(key, title, desc, body, extra)))
        if fname == "404.html":
            html = make_404(html, css, mark)
        (SITE / fname).write_text(html, encoding="utf-8")
        print("wrote site/" + fname)

if __name__ == "__main__":
    main()
