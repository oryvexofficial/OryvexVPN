#!/usr/bin/env python3
"""Builds the multi-page website in site/ from one place.

    python3 tools/build-site.py

Header, footer and icons are shared, so a nav change is one edit here instead of nine.
The output is plain static HTML (GitHub Pages serves site/ as is, see pages.yml).
`tools/set-repo.sh` rewrites the OWNER/OryvexCore links in the output and in this file.
"""
import pathlib, re

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / "site"
REPO = "https://github.com/OWNER/OryvexCore"
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

def icon(name, cls=""):
    c = ("i " + cls).strip()
    if name in FILLED:
        vb, body = FILLED[name]
        return f'<svg class="{c} fill" viewBox="{vb}" aria-hidden="true" focusable="false">{body}</svg>'
    return f'<svg class="{c}" viewBox="0 0 24 24" aria-hidden="true" focusable="false">{ICONS[name]}</svg>'

def expand(html):
    return re.sub(r"\{\{i:([a-z-]+)(?: ([a-z-]+))?\}\}", lambda m: icon(m.group(1), m.group(2) or ""), html)

# ---------------------------------------------------------------- shell
NAV = [("about", "about.html", "About"), ("guide", "guide.html", "How to use"), ("app", "app.html", "App"),
       ("tor", "tor.html", "Tor"), ("docs", "docs.html", "Docs"), ("creator", "creator.html", "Creator")]

def header(active):
    links = "".join(
        f'<a href="{href}"' + (' aria-current="page"' if key == active else "") + f">{label}</a>"
        for key, href, label in NAV)
    cta_cur = ' aria-current="page"' if active == "download" else ""
    return f'''<a class="skip" href="#main">Skip to content</a>
<header class="site-header"><div class="wrap nav">
<a class="brand" href="index.html"><img src="assets/mark.svg" alt="" width="30" height="30">OryvexVPN</a>
<button id="menu" class="menu-btn" type="button" aria-label="Open menu" aria-expanded="false" aria-controls="nav-links">{{{{i:menu i-open}}}}{{{{i:close i-close}}}}</button>
<nav id="nav-links" class="nav-links" aria-label="Main">{links}<a class="nav-cta" href="download.html"{cta_cur}>{{{{i:download}}}}Download</a></nav>
</div></header>'''

FOOTER = f'''<footer class="site-footer"><div class="wrap">
<div class="foot">
<div><a class="brand" href="index.html"><img src="assets/mark.svg" alt="" width="30" height="30">OryvexVPN</a><p>A way out of filtered networks. Free software by Muvixo.</p></div>
<div><h4>Product</h4><nav aria-label="Product"><a href="about.html">About</a><a href="app.html">App</a><a href="download.html">Download</a></nav></div>
<div><h4>Learn</h4><nav aria-label="Learn"><a href="guide.html">How to use</a><a href="tor.html">Tor</a><a href="docs.html">Docs</a></nav></div>
<div><h4>Project</h4><nav aria-label="Project"><a href="creator.html">Creator</a><a href="{REPO}">{{{{i:github}}}}GitHub</a><a href="{REPO}/blob/main/LICENSE">AGPL-3.0</a></nav></div>
</div>
<div class="legal">&copy; <span id="year">2026</span> Muvixo &middot; OryvexVPN &middot; AGPL-3.0</div>
</div></footer>'''

def page(key, title, desc, body, head_extra=""):
    full_title = "OryvexVPN · a way out of filtered networks" if key == "home" else f"{title} · OryvexVPN"
    return f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
{head_extra}<title>{full_title}</title>
<meta name="description" content="{desc}">
<meta name="theme-color" content="#06080c">
<meta property="og:title" content="{full_title}">
<meta property="og:description" content="{desc}">
<meta property="og:image" content="assets/icon-256.png">
<link rel="icon" href="assets/mark.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="assets/icon-256.png">
<link rel="preload" href="assets/fonts/Inter-Regular.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="style.css">
</head>
<body data-page="{key}">
{header(key)}
<main id="main">
{body}
</main>
{FOOTER}
<script src="app.js"></script>
</body>
</html>
'''

def head(eyebrow_icon, eyebrow, h1, lead):
    return f'''<section class="page-head"><div class="wrap">
<div class="eyebrow">{{{{i:{eyebrow_icon}}}}}{eyebrow}</div>
<h1>{h1}</h1>
<p class="lead">{lead}</p>
</div></section>'''

BAND = '''<div class="wrap"><div class="band"><div><h2>Ready to get out?</h2><p>Android 5.0+, Windows 7 to 11, Linux, macOS and OpenWrt.</p></div>
<a class="btn" href="download.html">{{i:download}}Download OryvexVPN</a></div></div>'''

# ---------------------------------------------------------------- pages
PAGES = {}

PAGES["index.html"] = ("home", "Home",
"OryvexVPN: WireGuard, MASQUE and Tor with exit-country choice, for Windows and Android. Free software by Muvixo.",
'''<section class="hero"><div class="wrap">
<div class="orb" aria-hidden="true"></div>
<div class="eyebrow">{{i:shield}}Private by design</div>
<h1>A way out.</h1>
<p class="lead">OryvexCore finds a route that works on your network: WireGuard, MASQUE over HTTP/3 or HTTP/2, or straight into Tor with the exit country you choose.</p>
<div class="actions"><a class="btn" href="download.html">{{i:download}}Download</a><a class="btn ghost" href="guide.html">How it works{{i:arrow}}</a></div>
<div class="proof"><span>{{i:windows}}Windows</span><span>{{i:android}}Android</span><span>{{i:terminal}}Linux, macOS, OpenWrt</span><span>{{i:code}}Open source, AGPL-3.0</span></div>
</div></section>

<section class="section"><div class="wrap">
<div class="eyebrow">{{i:route}}What it does</div>
<h2>Built for networks that fight back.</h2>
<p class="lead">Scans, verifies real HTTPS traffic before it says Connected, then serves the tunnel as a SOCKS5 proxy or a whole-device VPN.</p>
<div class="grid" style="margin-top:36px">
<a class="card card-link" href="about.html"><div class="ico">{{i:route}}</div><h3>Auto route</h3><p>Tries WireGuard, MASQUE, MASQUE² and Gool, keeps the first that passes real traffic.</p><span class="more">About{{i:arrow}}</span></a>
<a class="card card-link" href="tor.html"><div class="ico">{{i:onion}}</div><h3>Tor, built in</h3><p>Arti (Rust Tor) inside the core, with bridges fetched when Tor is blocked.</p><span class="more">Tor route{{i:arrow}}</span></a>
<a class="card card-link" href="app.html"><div class="ico">{{i:globe}}</div><h3>Pick your exit</h3><p>Auto, Fastest or a country. Try the picker yourself.</p><span class="more">See the app{{i:arrow}}</span></a>
<a class="card card-link" href="docs.html"><div class="ico">{{i:terminal}}</div><h3>Scriptable</h3><p>Every option is a flag or an environment variable.</p><span class="more">Docs{{i:arrow}}</span></a>
</div>
</div></section>
''' + BAND)

PAGES["about.html"] = ("about", "About",
"What OryvexVPN does: auto route selection, built-in Tor, exit-country choice and fingerprint resistance.",
head("info", "About", "Built for networks that fight back.",
"Deep packet inspection, fingerprinting, UDP throttling, blocked endpoints. OryvexCore scans, verifies real HTTPS traffic before it says Connected, and serves the tunnel as a local SOCKS5 proxy or a whole-device VPN.") + '''
<section class="section"><div class="wrap">
<div class="grid">
<div class="card"><div class="ico">{{i:route}}</div><h3>Auto route</h3><p>Tries WireGuard, then MASQUE, MASQUE² and Gool, and keeps the first one that passes real traffic.</p></div>
<div class="card"><div class="ico">{{i:onion}}</div><h3>Tor, built in</h3><p>Arti (Rust Tor) inside the core on Windows and Android. Bridges fetched for you when Tor is blocked.</p></div>
<div class="card"><div class="ico">{{i:globe}}</div><h3>Pick your exit</h3><p>Auto, Fastest (measured on connect) or a country. The exit list is fetched through Tor itself, never over your filtered line.</p></div>
<div class="card"><div class="ico">{{i:shield}}</div><h3>Hard to fingerprint</h3><p>Chrome-shaped TLS, ClientHello fragmentation and obfuscation profiles from light to GFW.</p></div>
<div class="card"><div class="ico">{{i:radar}}</div><h3>Real scanning</h3><p>Five scan modes from turbo to ironclad. Ironclad opens a full tunnel and sends a real request before trusting a gateway.</p></div>
<div class="card"><div class="ico">{{i:plug}}</div><h3>Proxy or VPN</h3><p>A SOCKS5 proxy on <code>127.0.0.1:1819</code>, an optional Windows system proxy, or the whole device on Android.</p></div>
</div>
</div></section>

<section class="section"><div class="wrap">
<div class="eyebrow">{{i:layers}}Transports</div>
<h2>Three ways through.</h2>
<div class="grid" style="margin-top:28px">
<div class="card"><h3>MASQUE</h3><p>The default. Traffic hides inside an encrypted connection that looks like ordinary web traffic, over HTTP/3 or HTTP/2.</p></div>
<div class="card"><h3>WireGuard</h3><p>Lean and very fast. Best on networks that block known addresses but don't look closely at traffic shape.</p></div>
<div class="card"><h3>Gool</h3><p>Tunnel in a tunnel: WireGuard inside MASQUE, or inside WireGuard. Slower, but it can be the difference.</p></div>
</div>
</div></section>
''' + BAND)

PAGES["guide.html"] = ("guide", "How to use",
"Install OryvexVPN, pick a route, choose a Tor exit and connect in a few taps.",
head("book", "How to use", "Three taps to connected.", "Install, pick a route, connect. The defaults are good; change them only when your network pushes back.") + '''
<section class="section"><div class="wrap">
<ol class="steps">
<li><b>Install.</b> Android: the APK for your phone (arm64-v8a for most). Windows: unzip and run <code>OryvexVPN.exe</code>.</li>
<li><b>Pick a route.</b> Leave it on <b>Auto</b>, or choose <b>Tor</b> for the Tor network with no tunnel underneath.</li>
<li><b>Choose a Tor exit</b> (Tor route): <b>Auto</b>, <b>Fastest</b>, or a <b>Country</b> such as Germany or Netherlands.</li>
<li><b>Connect.</b> The orb shows each stage live; it turns Connected only after HTTPS returns 200 through the tunnel.</li>
</ol>
</div></section>

<section class="section"><div class="wrap">
<div class="eyebrow">{{i:plug}}Proxy mode</div>
<h2>Point any app at it.</h2>
<p class="lead">The core serves a SOCKS5 proxy. Use <code>socks5h</code> so DNS goes through the tunnel too.</p>
<pre><code>socks5h://127.0.0.1:1819</code></pre>
<p class="muted">Check it works:</p>
<pre><code>curl -x socks5h://127.0.0.1:1819 https://www.cloudflare.com/cdn-cgi/trace</code></pre>
<p class="muted">Seeing <code>warp=on</code> means your traffic is passing through the tunnel.</p>
</div></section>

<section class="section"><div class="wrap">
<div class="eyebrow">{{i:wifi-off}}When it won't connect</div>
<h2>Turn it up one step at a time.</h2>
<div class="grid" style="margin-top:28px">
<div class="card"><h3>Nothing connects</h3><p>Switch MASQUE to HTTP/2. If that handshake is blocked too, add ClientHello fragmentation. Then try WireGuard or classic Gool.</p></div>
<div class="card"><h3>Connects, then drops</h3><p>Take the obfuscation profile one step heavier: <code>gfw</code> for MASQUE, <code>aggressive</code> for WireGuard.</p></div>
<div class="card"><h3>Scan is slow</h3><p>Use the turbo scan, and say yes to reconnecting to your last working gateway.</p></div>
<div class="card"><h3>Tor is blocked</h3><p>Bridges are fetched for you. Or run Tor through the tunnel. <a href="tor.html#bridges">Tor bridges</a></p></div>
</div>
</div></section>
''' + BAND)

PAGES["app.html"] = ("app", "App",
"The OryvexVPN app for Windows and Android: one design, live connection stages and a Tor exit picker.",
head("smartphone", "App", "One blue. One canvas.", "Same design on Windows and Android, responsive from small phones to wide desktops.") + '''
<section class="section"><div class="wrap split">
<div>
<h2>Try the exit picker.</h2>
<p class="lead">This is the Tor exit control from the app. Pick a mode and see the matching command line.</p>
<pre><code id="flag-mirror" aria-live="polite"></code></pre>
</div>
<div class="mock" id="exit-picker">
<div class="mock-title">Tor exit<span class="status">Connected</span></div>
<div class="seg" role="group" aria-label="Exit mode">
<button type="button" data-m="auto">{{i:globe}}Auto</button>
<button type="button" data-m="fastest">{{i:zap}}Fastest</button>
<button type="button" data-m="country">{{i:route}}Country</button>
</div>
<p class="hint" id="hint" aria-live="polite"></p>
<div class="chips" id="chips"></div>
<p class="sr-only" id="flag"></p>
</div>
</div></section>

<section class="section"><div class="wrap">
<div class="grid">
<div class="card"><div class="ico">{{i:radar}}</div><h3>Live stages</h3><p>Identity, gateway scan, tunnel, proxy, then Tor, Psiphon or the device VPN when they apply.</p></div>
<div class="card"><div class="ico">{{i:terminal}}</div><h3>Activity</h3><p>The core's log with level tags, folded repeats and one-tap copy.</p></div>
<div class="card"><div class="ico">{{i:globe}}</div><h3>Updates</h3><p>Checks GitHub for a newer release, through the tunnel when connected, and says so.</p></div>
<div class="card"><div class="ico">{{i:shield}}</div><h3>No network fonts</h3><p>Inter and JetBrains Mono ship inside the app. Nothing loads from outside.</p></div>
</div>
</div></section>
<script>
// Mirror the picker's command into the visible code block.
(function(){var src=document.getElementById('flag'),dst=document.getElementById('flag-mirror');if(!src||!dst)return;
new MutationObserver(function(){dst.textContent=src.textContent;}).observe(src,{childList:true,characterData:true,subtree:true});})();
</script>
''' + BAND)

PAGES["tor.html"] = ("tor", "Tor",
"Tor in OryvexVPN: three ways to combine Tor with the tunnel, exit-country choice, bridges and where it lives in the code.",
head("onion", "Tor", "Tor, built in.",
"Arti, the Rust implementation of Tor, runs inside OryvexCore. Use it on its own, inside the tunnel, or carry the tunnel through it.") + f'''
<section class="section"><div class="wrap">
<div class="eyebrow">{{{{i:layers}}}}Three modes</div>
<h2>Pick how Tor fits in.</h2>
<div class="grid-2" style="margin-top:28px">
<div class="card"><h3>Tor alone</h3><p>No tunnel, no WARP identity. The proxy is plain Tor. In the apps this is the <b>Tor</b> route.</p>
<div class="route"><span class="hop">{{{{i:user}}}}You</span>{{{{i:arrow arrow}}}}<span class="hop tor">{{{{i:onion}}}}Tor</span>{{{{i:arrow arrow}}}}<span class="hop">{{{{i:globe}}}}Internet</span></div>
<pre style="margin:18px 0 0"><code>oryvexcore --tor-only</code></pre></div>
<div class="card"><h3>Tor through the tunnel</h3><p>Tor rides inside WARP, so a network that blocks Tor never sees it. Tor proxy on <code>127.0.0.1:1820</code>.</p>
<div class="route"><span class="hop">{{{{i:user}}}}You</span>{{{{i:arrow arrow}}}}<span class="hop">{{{{i:shield}}}}WARP</span>{{{{i:arrow arrow}}}}<span class="hop tor">{{{{i:onion}}}}Tor</span>{{{{i:arrow arrow}}}}<span class="hop">{{{{i:globe}}}}Internet</span></div>
<pre style="margin:18px 0 0"><code>oryvexcore --masque --tor</code></pre></div>
<div class="card"><h3>The tunnel through Tor</h3><p>Tor first, then WARP is dialled through it. You leave from a WARP exit. MASQUE over HTTP/2 only, Tor carries TCP.</p>
<div class="route"><span class="hop">{{{{i:user}}}}You</span>{{{{i:arrow arrow}}}}<span class="hop tor">{{{{i:onion}}}}Tor</span>{{{{i:arrow arrow}}}}<span class="hop">{{{{i:shield}}}}WARP</span>{{{{i:arrow arrow}}}}<span class="hop">{{{{i:globe}}}}Internet</span></div>
<pre style="margin:18px 0 0"><code>oryvexcore --masque --tor-reverse</code></pre></div>
<div class="card"><h3>Check you're on Tor</h3><p>Ask the Tor Project which address it sees.</p>
<pre style="margin:18px 0 0"><code>curl -x socks5h://127.0.0.1:1820 https://check.torproject.org/api/ip</code></pre></div>
</div>
</div></section>

<section class="section" id="exits"><div class="wrap">
<div class="eyebrow">{{{{i:globe}}}}Exit choice</div>
<h2>Leave from where you want.</h2>
<div class="table-wrap"><table>
<thead><tr><th>Value</th><th>What happens</th></tr></thead>
<tbody>
<tr><td><code>--tor-exit auto</code></td><td>Default. Tor picks an exit itself, weighted by bandwidth.</td></tr>
<tr><td><code>--tor-exit fastest</code></td><td>On every connect, tests exits in the 6 best-served countries and keeps the quickest.</td></tr>
<tr><td><code>--tor-exit de,nl,se</code></td><td>Leave from that country, first that answers.</td></tr>
<tr><td><code>--tor-exit-strict</code></td><td>Fail instead of falling back to another country.</td></tr>
</tbody></table></div>
<div class="note">{{{{i:info}}}}<p>The exit list is only ever fetched <b>through Tor itself</b>, then cached in <code>&lt;tor-dir&gt;/exits.json</code>. Until then a bundled list of 32 exit countries is used, resolved locally by Arti's GeoIP table.</p></div>
</div></section>

<section class="section" id="bridges"><div class="wrap">
<div class="eyebrow">{{{{i:bridge}}}}Bridges</div>
<h2>When Tor itself is blocked.</h2>
<p class="lead">OryvexCore tries Tor plainly for a moment, then fetches bridges and pluggable transports on its own. You can bring your own too.</p>
<pre><code>oryvexcore --tor-only \\
  --tor-bridge "obfs4 192.0.2.55:38114 FINGERPRINT cert=... iat-mode=0" \\
  --tor-pt /usr/bin/lyrebird</code></pre>
<div class="table-wrap"><table>
<thead><tr><th>Flag</th><th>Default</th><th>What it does</th></tr></thead>
<tbody>
<tr><td><code>--tor-bind</code></td><td><code>127.0.0.1:1820</code></td><td>The Tor proxy address</td></tr>
<tr><td><code>--tor-dir</code></td><td><code>&lt;config&gt;-tor</code></td><td>Directory cache and state</td></tr>
<tr><td><code>--tor-bridge</code></td><td>fetched as needed</td><td>Bridge lines; repeat for more</td></tr>
<tr><td><code>--tor-bridge-file</code></td><td></td><td>Your own bridge lines from a file</td></tr>
<tr><td><code>--tor-bridges</code></td><td></td><td>Go to bridges at once</td></tr>
<tr><td><code>--no-tor-bridges</code></td><td></td><td>Never use bridges</td></tr>
<tr><td><code>--tor-pt</code></td><td>found on its own</td><td>Pluggable transport binaries</td></tr>
<tr><td><code>--tor-pt-dir</code></td><td><code>pt/</code> beside the binary</td><td>Another folder to search</td></tr>
</tbody></table></div>
</div></section>

<section class="section" id="source"><div class="wrap">
<div class="eyebrow">{{{{i:code}}}}Under the hood</div>
<h2>Where Tor lives in the code.</h2>
<div class="note">{{{{i:info}}}}<p>Tor is a <b>cargo feature</b>, off by default. Plain <code>cargo build</code> gives a core with no Tor. Build with <code>scripts/build-core.sh</code> (what CI and Docker use) or <code>--features tor,tor-exit-country</code>.</p></div>
<pre><code>cd oryvexcore
bash scripts/build-core.sh cargo build --release   <span class="c"># tor + exit country, falls back on tor</span>
cargo build --release --features tor,tor-exit-country</code></pre>
<div class="table-wrap"><table>
<thead><tr><th>File</th><th>What's in it</th></tr></thead>
<tbody>
<tr><td><a href="{REPO}/blob/main/oryvexcore/src/tor.rs"><code>oryvexcore/src/tor.rs</code></a></td><td>The Arti client: modes (alone, through, reverse), bootstrap, the 1820 proxy</td></tr>
<tr><td><a href="{REPO}/blob/main/oryvexcore/src/tor_exits.rs"><code>oryvexcore/src/tor_exits.rs</code></a></td><td>Exit-country choice: auto, fastest, country list, cache</td></tr>
<tr><td><a href="{REPO}/blob/main/oryvexcore/src/bridges.rs"><code>oryvexcore/src/bridges.rs</code></a></td><td>Bridge fetching and pluggable transports</td></tr>
<tr><td><a href="{REPO}/blob/main/oryvexcore/src/cli.rs"><code>oryvexcore/src/cli.rs</code></a></td><td>The <code>--tor*</code> flags</td></tr>
<tr><td><a href="{REPO}/blob/main/oryvexcore/Cargo.toml"><code>oryvexcore/Cargo.toml</code></a></td><td>The <code>tor</code> and <code>tor-exit-country</code> features (arti-client 0.46)</td></tr>
<tr><td><a href="{REPO}/blob/main/oryvexcore/scripts/pt-build.sh"><code>oryvexcore/scripts/pt-build.sh</code></a></td><td>Builds the pluggable transports shipped in <code>pt/</code></td></tr>
<tr><td><a href="{REPO}/blob/main/apps/shared/lib/src/ui/widgets/tor_exit_picker.dart"><code>apps/shared/.../tor_exit_picker.dart</code></a></td><td>The exit picker in the Windows and Android apps</td></tr>
<tr><td><a href="{REPO}/blob/main/oryvexcore/tor/exit-nodes.txt"><code>oryvexcore/tor/exit-nodes.txt</code></a></td><td>Latest Tor exit IPs from the Tor Project, refresh with <code>tools/update-tor-exits.sh</code></td></tr>
<tr><td><a href="{REPO}/blob/main/docs/TOR.md"><code>docs/TOR.md</code></a></td><td>Tor route and exit selection notes</td></tr>
</tbody></table></div>
</div></section>
''' + BAND)

DOC_TOC = [("start", "Run it"), ("transports", "Transports"), ("scan", "Scanning"), ("noise", "Obfuscation"),
           ("h2", "HTTP/2 vs HTTP/3"), ("tor", "Tor"), ("flags", "Flags"), ("docker", "Docker"), ("help", "Troubleshooting")]
toc_html = "".join(f'<a href="#{k}">{v}</a>' for k, v in DOC_TOC)

PAGES["docs.html"] = ("docs", "Docs",
"OryvexCore command-line reference: transports, scan modes, obfuscation profiles, Tor and Docker.",
head("terminal", "Docs", "Command line.", "Every prompt has a flag, every flag has an environment variable. Mix them however you like.") + f'''
<div class="wrap doc">
<nav class="toc" aria-label="On this page">{toc_html}</nav>
<div class="doc-body">
<section id="start"><h2>Run it</h2>
<p class="muted">With no arguments, OryvexCore asks its questions one by one. Flags skip them.</p>
<pre><code>oryvexcore                                 <span class="c"># answer the questions as they come</span>
oryvexcore --masque --turbo -4             <span class="c"># straight to work</span>
oryvexcore --tor-only --tor-exit fastest   <span class="c"># plain Tor, fastest exit country</span>
oryvexcore --tor-only --tor-exit de,nl     <span class="c"># Germany, else Netherlands</span>
oryvexcore --wg --tor --tor-exit se        <span class="c"># Tor inside WireGuard, exit in Sweden</span>
oryvexcore help                            <span class="c"># every flag and variable</span></code></pre>
</section>
<section id="transports"><h2>Transports</h2>
<ul>
<li><b>MASQUE</b> <code>--masque</code>: the default. Looks like ordinary web traffic. Start here.</li>
<li><b>WireGuard</b> <code>--wg</code>: least overhead, fastest when it works.</li>
<li><b>Gool over MASQUE</b> <code>--gool</code>: WireGuard inside MASQUE, for a different exit address.</li>
<li><b>Classic Gool</b> <code>--gool-classic</code>: WireGuard inside WireGuard, two layers. Use when plain WireGuard is unstable.</li>
</ul>
</section>
<section id="scan"><h2>Scanning</h2>
<p class="muted">No address is hard-coded. OryvexCore measures real responses and picks the best gateway.</p>
<div class="table-wrap"><table><thead><tr><th>Mode</th><th>Use it when</th></tr></thead><tbody>
<tr><td><code>turbo</code></td><td>You want to connect fast; first answer wins</td></tr>
<tr><td><code>balanced</code></td><td>Default, good for most networks</td></tr>
<tr><td><code>thorough</code></td><td>You want the best ping, can wait</td></tr>
<tr><td><code>stealth</code></td><td>You want less noise on the network</td></tr>
<tr><td><code>ironclad</code></td><td>Gateways looked fine but never passed traffic</td></tr>
</tbody></table></div>
</section>
<section id="noise"><h2>Obfuscation</h2>
<ul>
<li><b>MASQUE and Gool:</b> <code>firewall</code> (default), <code>gfw</code> (heavier), <code>off</code>.</li>
<li><b>WireGuard and classic Gool:</b> <code>balanced</code> (default), <code>aggressive</code>, <code>light</code>, <code>off</code>.</li>
</ul>
<p class="muted">Start on the default. Didn't connect or kept dropping? Go one step heavier.</p>
</section>
<section id="h2"><h2>HTTP/2 vs HTTP/3</h2>
<p class="muted">MASQUE uses HTTP/3 (QUIC over UDP) by default. If your network throttles UDP, switch to HTTP/2 over TCP. If the HTTP/2 handshake gets blocked, fragment the ClientHello.</p>
<pre><code>oryvexcore --h2
oryvexcore --h2 --fragment --fragment-size 8-24 --fragment-delay 5-15</code></pre>
</section>
<section id="tor"><h2>Tor</h2>
<p class="muted">Three modes, exit choice and bridges are covered on the <a href="tor.html">Tor page</a>.</p>
<pre><code>oryvexcore --tor-only                   <span class="c"># Tor alone</span>
oryvexcore --masque --tor               <span class="c"># Tor through the tunnel, Tor on :1820</span>
oryvexcore --masque --tor-reverse       <span class="c"># the tunnel through Tor</span></code></pre>
</section>
<section id="flags"><h2>Common flags</h2>
<div class="table-wrap"><table><thead><tr><th>Flag</th><th>What it does</th></tr></thead><tbody>
<tr><td><code>--bind &lt;addr&gt;</code></td><td>SOCKS5 listen address, default <code>127.0.0.1:1819</code></td></tr>
<tr><td><code>-4</code> / <code>-6</code> / <code>--dual</code></td><td>Scan IPv4, IPv6 or both</td></tr>
<tr><td><code>--peer &lt;ip:port&gt;</code></td><td>Force a gateway and skip scanning</td></tr>
<tr><td><code>--scan &lt;mode&gt;</code></td><td>turbo, balanced, thorough, stealth, ironclad</td></tr>
<tr><td><code>--noize &lt;profile&gt;</code></td><td>Obfuscation profile</td></tr>
<tr><td><code>--h2</code></td><td>MASQUE over HTTP/2</td></tr>
<tr><td><code>--fragment</code></td><td>Fragment the TLS ClientHello</td></tr>
<tr><td><code>--quick-reconnect</code></td><td>Always reuse the last working gateway</td></tr>
<tr><td><code>--tor-exit auto|fastest|cc</code></td><td>Where Tor leaves from</td></tr>
<tr><td><code>--tor-exit-strict</code></td><td>Fail instead of leaving elsewhere</td></tr>
<tr><td><code>--tor-bridge-file</code></td><td>Your own bridge lines</td></tr>
</tbody></table></div>
</section>
<section id="docker"><h2>Docker</h2>
<div class="note">{{{{i:info}}}}<p>The SOCKS5 proxy has no authentication. Publish it on <code>127.0.0.1</code> only, or anyone on your network can use your tunnel.</p></div>
<pre><code>docker run -it -p 127.0.0.1:1819:1819 -v oryvexcore-data:/data \\
  -e ORYVEXCORE_PROTOCOL=masque \\
  ghcr.io/owner/oryvexcore:latest</code></pre>
</section>
<section id="help"><h2>Troubleshooting</h2>
<ul>
<li><b>No connection at all:</b> MASQUE on h2, then <code>--fragment</code>, then WireGuard or classic Gool.</li>
<li><b>Connects but nothing loads:</b> the data check rejects that gateway and keeps scanning on its own.</li>
<li><b>Keeps dropping:</b> heavier obfuscation profile.</li>
<li><b>Slow:</b> drop from Gool to a single tunnel; try h3 if UDP is open.</li>
</ul>
<p>Full reference: <a href="{REPO}/blob/main/docs/DOCS.md">DOCS.md</a> &middot; <a href="{REPO}/blob/main/docs/GUIDE.md">Guide</a> &middot; <a href="{REPO}/blob/main/docs/OPENWRT.md">OpenWrt</a></p>
</section>
</div>
</div>''')

PAGES["creator.html"] = ("creator", "Creator",
"OryvexVPN is made by Muvixo. Free software under the AGPL-3.0.",
head("heart", "Creator", "Made by Muvixo.", "Free software under the AGPL-3.0. MASQUE on Cloudflare's quiche, Tor on Arti.") + f'''
<section class="section"><div class="wrap">
<div class="grid">
<div class="card"><div class="ico">{{{{i:code}}}}</div><h3>Open source</h3><p>Every line of the core and the apps is on GitHub.</p><a class="btn ghost" href="{REPO}">{{{{i:github}}}}Source code</a></div>
<div class="card"><div class="ico">{{{{i:book}}}}</div><h3>License</h3><p>AGPL-3.0. Third-party notices ship with every build.</p><a class="btn ghost" href="{REPO}/blob/main/LICENSE">Read the license</a></div>
<div class="card"><div class="ico">{{{{i:layers}}}}</div><h3>Built on</h3><p>quiche for MASQUE, Arti for Tor, Flutter for the apps, Rust for the core.</p></div>
</div>
</div></section>
<section class="section"><div class="wrap">
<div class="eyebrow">{{{{i:heart}}}}Support the work</div>
<h2>Donate.</h2>
<p class="muted">TRX (TRON)</p>
<div class="wallet"><code>TRxVSHcoADZnBfztFmFb2TQopusAwWYEVR</code><button type="button" class="copy" data-copy="TRxVSHcoADZnBfztFmFb2TQopusAwWYEVR" aria-label="Copy TRX address">{{{{i:copy}}}}<span>Copy</span></button></div>
</div></section>''')

PAGES["download.html"] = ("download", "Download",
"Download OryvexVPN for Android, Windows 10/11, Windows 7/8, Linux, macOS, OpenWrt and Docker.",
head("download", "Download", "Get OryvexVPN.", "Every build comes from GitHub Actions, straight from the source.") + f'''
<section class="section"><div class="wrap">
<div class="grid">
<div class="card"><div class="ico">{{{{i:android}}}}</div><h3>Android 5.0+</h3><p>arm64-v8a, armeabi-v7a, x86_64 or universal APK. Not sure? Take arm64-v8a.</p><a class="btn" href="{RELEASES}">{{{{i:download}}}}APK</a></div>
<div class="card"><div class="ico">{{{{i:windows}}}}</div><h3>Windows 10/11</h3><p>Desktop app with Tor, transports and Psiphon bundled.</p><a class="btn" href="{RELEASES}">{{{{i:download}}}}Windows x64</a></div>
<div class="card"><div class="ico">{{{{i:monitor}}}}</div><h3>Windows 7/8 Lite</h3><p>Tiny native app, 32 and 64-bit.</p><a class="btn ghost" href="{RELEASES}">{{{{i:download}}}}Legacy</a></div>
<div class="card"><div class="ico">{{{{i:box}}}}</div><h3>CLI &amp; Docker</h3><p>Linux, macOS, OpenWrt, Termux and a ghcr.io image.</p><a class="btn ghost" href="{RELEASES}">{{{{i:download}}}}All builds</a></div>
</div>
</div></section>
<section class="section"><div class="wrap">
<div class="eyebrow">{{{{i:terminal}}}}One-liner</div>
<h2>Linux, macOS, Termux.</h2>
<pre><code>curl -fsSL https://raw.githubusercontent.com/OWNER/OryvexCore/main/oryvexcore/scripts/oryvexcore.sh -o oryvexcore.sh
bash oryvexcore.sh</code></pre>
<p class="muted">OpenWrt routers have their own guide: <a href="{REPO}/blob/main/docs/OPENWRT.md">OPENWRT.md</a></p>
</div></section>''')

# 404 is served by GitHub Pages at ANY missing path (/OryvexCore/a/b/c), so relative links and
# styles would break there. The page carries its CSS and logo inline, then finds the site root:
# on a project site that is /<repo>/, on a custom domain or user site it is /.
ROOT_SCRIPT = """<script>(function(){
var seg=location.pathname.split('/')[1]||'';
function apply(root){
  var a=document.querySelectorAll('[data-href]');
  for(var k=0;k<a.length;k++){a[k].setAttribute('href',root+a[k].getAttribute('data-href'));}
  var css=document.createElement('link');css.rel='stylesheet';css.href=root+'style.css';document.head.appendChild(css);
  var ico=document.createElement('link');ico.rel='icon';ico.type='image/svg+xml';ico.href=root+'assets/mark.svg';document.head.appendChild(ico);
  var js=document.createElement('script');js.src=root+'app.js';document.body.appendChild(js);
}
function ready(f){document.readyState==='loading'?document.addEventListener('DOMContentLoaded',f):f();}
if(!seg||seg.indexOf('.')>-1){ready(function(){apply('/');});return;}
var done=false;function go(r){if(done)return;done=true;ready(function(){apply(r);});}
try{fetch('/'+seg+'/app.js',{method:'HEAD',cache:'no-store'}).then(function(r){go(r.ok?'/'+seg+'/':'/');},function(){go('/');});}catch(e){go('/');}
setTimeout(function(){go('/');},2500);
})();</script>
"""

PAGES["404.html"] = ("404", "Page not found",
"This page doesn't exist on the OryvexVPN site.",
'''<section class="lost"><div class="wrap">
<div class="mark" aria-hidden="true">@@MARK@@</div>
<h1>404</h1>
<p class="lead">No route to this page. It moved, or it never existed.</p>
<div class="scanlog" aria-hidden="true"><div>scan&nbsp;&nbsp;this address&nbsp;&nbsp;<span class="bad">no answer</span></div><div>scan&nbsp;&nbsp;home page&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<span class="ok">200 OK</span></div></div>
<div class="actions"><a class="btn" href="index.html">{{i:home}}Back home</a><a class="btn ghost" href="docs.html">{{i:book}}Docs</a><a class="btn ghost" href="download.html">{{i:download}}Download</a></div>
</div></section>''', ROOT_SCRIPT)


def clean_links(html):
    """download.html -> download, index.html -> ./  (GitHub Pages serves /download from download.html)."""
    html = re.sub(r'href="index\.html(#[^"]*)?"', lambda m: 'href="./' + (m.group(1) or '') + '"', html)
    return re.sub(r'href="([a-z0-9-]+)\.html(#[^"]*)?"', lambda m: f'href="{m.group(1)}{m.group(2) or ""}"', html)


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
    html = html.replace('<script src="app.js"></script>\n', "")
    inline = re.sub(r'@font-face\{[^}]*\}\n?', "", css)
    html = html.replace("</head>", f"<style>{inline}</style>\n</head>")
    count = [0]
    def copy(size):
        # the mark is inlined several times: give each copy its own gradient ids
        count[0] += 1
        m = re.sub(r'(id="|url\(#)(ox[A-Za-z]+)', lambda g: f"{g.group(1)}{g.group(2)}{count[0]}", mark)
        return m.replace('width="512" height="512"', f'width="{size}" height="{size}" aria-hidden="true" focusable="false"')
    html = re.sub(r'<img src="/?assets/mark\.svg"[^>]*>', lambda _: copy(30), html)
    return html.replace("@@MARK@@", copy(220))


def main():
    css = (SITE / "style.css").read_text(encoding="utf-8")
    mark = (SITE / "assets" / "mark.svg").read_text(encoding="utf-8")
    mark = re.sub(r"<title>.*?</title>\s*", "", mark).strip()
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
