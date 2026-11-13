import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Every choice the GUI makes for the core. Each field maps onto CLI flags in `args.dart`.
class CoreSettings {
  CoreSettings();

  /// auto | wg | masque | mim | gool | tor | bypass | mitm | fox.
  ///
  /// auto tries WireGuard, then MASQUE, then MASQUE², then Gool, and keeps the first one that
  /// connects. tor skips the tunnel: the proxy (and on Android the device VPN) is plain Tor.
  /// bypass skips it too: traffic leaves directly, with the first packets of each connection
  /// reshaped so a filter cannot read the site name (no change of exit address).
  String protocol = 'auto';

  /// mitm skips it as well: oryvexcore itself re-sends Google, Meta and Fastly sites with another
  /// name in the TLS handshake (domain fronting), using a certificate authority made on this
  /// device. No v2ray, no outside server.

  /// Bypass: resolve names with the engine's own anti-poisoning resolver.
  bool bypassDoh = true;

  /// Bypass: drop QUIC so browsers fall back to TCP, which the techniques cover.
  bool bypassDropQuic = true;

  /// Where Tor leaves from, for the Tor route and for "Tor via tunnel": auto (Tor picks by
  /// bandwidth), fastest (the core measures the best-served countries) or a lowercase country
  /// code such as de.
  String torExit = 'auto';

  /// Fail instead of leaving from another country when the chosen exit country does not answer.
  bool torExitStrict = false;

  /// With a country picked: measure several exit relays in that country and keep the quickest
  /// circuit, instead of the first one Tor builds there.
  bool torExitBest = true;

  /// h2 | h3. Only the MASQUE carriers (masque, gool, mim) read it. HTTP/2 is the default: it
  /// rides TCP and looks like ordinary HTTPS, so it gets through where QUIC/UDP is filtered.
  String transport = 'h2';

  /// turbo | balanced | thorough | verified | ironclad
  String scan = 'balanced';

  /// auto (core default) | off | light | firewall | balanced | gfw | aggressive
  String noize = 'auto';

  /// v4 | v6 | both
  String ip = 'v4';

  int socksPort = 1819;
  bool shareLan = false;

  bool httpProxy = false;
  int httpPort = 1820;

  bool fragment = false;
  bool quickReconnect = true;

  /// off | tor (Tor through the tunnel) | psiphon (desktop). Plain Tor is the `tor` protocol.
  String chain = 'off';

  /// Where the extra Tor proxy listens with chain == tor. Kept clear of the HTTP port.
  int torPort = 1822;

  /// Where the extra Psiphon proxy listens with chain == psiphon.
  int psiphonPort = 1821;

  String dns = '';
  String peer = '';

  /// Dark appearance is the first-launch default.
  bool darkTheme = true;

  /// Android: route the whole phone through the core with a VpnService.
  bool vpnMode = true;

  /// Android: answer DNS inside the VPN with mapped addresses (no UDP needed for lookups).
  bool fakeDns = true;

  /// Android: also tunnel IPv6 in VPN mode.
  bool vpnIpv6 = true;

  /// Windows: point the system (WinINet) proxy at the core's HTTP proxy while connected.
  /// Bypass enables this automatically, even when this preference is off.
  bool systemProxy = false;

  bool verbose = false;
  String extraArgs = '';

  // --- App behaviour --------------------------------------------------------------------------

  /// Connect as soon as the app opens.
  bool autoConnect = false;

  /// Bring the tunnel back by itself when it drops after it was connected.
  bool autoReconnect = true;

  /// Windows: start OryvexVPN when you sign in (HKCU Run, shared with the installer).
  bool launchAtStartup = false;

  /// Windows: when started at sign-in, stay in the tray instead of opening the window.
  bool startInTray = true;

  /// Windows: what the close button does: ask | tray | quit.
  String closeAction = 'ask';

  // --- Updates and history --------------------------------------------------------------------

  /// Look for a newer release on launch and every few hours after.
  bool checkUpdates = true;

  /// A release the user chose to skip: no badge or banner for it (Updates still lists it).
  String skippedVersion = '';

  /// Keep a short local list of past sessions (time, route, data). Never leaves the device.
  bool keepHistory = true;

  static const _key = 'oryvexcore.settings.v1';

  /// Bumped when the default protocol changed. Settings saved before 2 kept MASQUE only because
  /// it used to be the default, so they move to Auto once. 3 removed SSTP and made Tor a route.
  static const _protocolVersion = 3;

  /// Bumped when the default carrier changed. Settings saved before 1 kept HTTP/3 only because
  /// it used to be the default, so they move to HTTP/2 once.
  static const _carrierVersion = 1;

  /// No tunnel: the main proxy is plain Tor.
  bool get torOnly => protocol == 'tor';

  /// No tunnel: the main proxy is the Bypass engine, going out directly.
  bool get bypassOnly => protocol == 'bypass';

  /// No tunnel: the main proxy is oryvexcore's own domain-fronting proxy (MITM).
  bool get mitmOnly => protocol == 'mitm';

  /// The Firefox Account based Mozilla VPN connection.
  bool get foxOnly => protocol == 'fox';

  /// Goes out directly, with an engine of its own on the SOCKS5 port (Bypass or MITM).
  bool get directOnly => bypassOnly || mitmOnly;

  /// The route has no WARP tunnel under it (Tor, Bypass or MITM), so tunnel settings do not apply.
  bool get noTunnel => torOnly || bypassOnly || mitmOnly || foxOnly;

  /// Tor's exit choice is in play for this configuration.
  bool get usesTorExit => !foxOnly && (torOnly || chain == 'tor');

  /// Whether the core starts its HTTP listener for the selected platform.
  bool hasHttpProxyListener({required bool android}) =>
      !foxOnly && (httpProxy || (!android && (systemProxy || directOnly)));

  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'protocolVersion': _protocolVersion,
        'bypassDoh': bypassDoh,
        'bypassDropQuic': bypassDropQuic,
        'torExit': torExit,
        'torExitStrict': torExitStrict,
        'torExitBest': torExitBest,
        'transport': transport,
        'carrierVersion': _carrierVersion,
        'scan': scan,
        'noize': noize,
        'ip': ip,
        'socksPort': socksPort,
        'shareLan': shareLan,
        'httpProxy': httpProxy,
        'httpPort': httpPort,
        'fragment': fragment,
        'quickReconnect': quickReconnect,
        'chain': chain,
        'torPort': torPort,
        'psiphonPort': psiphonPort,
        'dns': dns,
        'peer': peer,
        'darkTheme': darkTheme,
        'vpnMode': vpnMode,
        'fakeDns': fakeDns,
        'vpnIpv6': vpnIpv6,
        'systemProxy': systemProxy,
        'verbose': verbose,
        'extraArgs': extraArgs,
        'autoConnect': autoConnect,
        'autoReconnect': autoReconnect,
        'launchAtStartup': launchAtStartup,
        'startInTray': startInTray,
        'closeAction': closeAction,
        'checkUpdates': checkUpdates,
        'skippedVersion': skippedVersion,
        'keepHistory': keepHistory,
      };

  static CoreSettings fromJson(Map<String, dynamic> j) {
    final s = CoreSettings();
    String str(String k, String d, [Map<String, String>? allowed]) {
      final v = j[k];
      if (v is! String) return d;
      if (allowed != null && !allowed.containsKey(v)) return d;
      return v;
    }

    bool flag(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    int port(String k, int d) {
      final v = j[k];
      return v is int && v > 0 && v < 65536 ? v : d;
    }

    // Unknown protocols (SSTP, removed in 3) fall back on Auto through the allowed list.
    s.protocol = str('protocol', s.protocol, Choices.protocols);
    final version = j['protocolVersion'];
    if ((version is! int || version < 2) && s.protocol == 'masque') s.protocol = 'auto';
    s.bypassDoh = flag('bypassDoh', s.bypassDoh);
    s.bypassDropQuic = flag('bypassDropQuic', s.bypassDropQuic);
    final exit = j['torExit'];
    if (exit is String && Choices.isTorExit(exit)) s.torExit = exit;
    s.torExitStrict = flag('torExitStrict', s.torExitStrict);
    s.torExitBest = flag('torExitBest', s.torExitBest);
    s.transport = str('transport', s.transport, Choices.transports);
    final carrier = j['carrierVersion'];
    if (carrier is! int || carrier < 1) s.transport = 'h2';
    s.scan = str('scan', s.scan, Choices.scans);
    s.noize = str('noize', s.noize, Choices.noizes);
    s.ip = str('ip', s.ip, Choices.ips);
    s.socksPort = port('socksPort', s.socksPort);
    s.shareLan = flag('shareLan', s.shareLan);
    s.httpProxy = flag('httpProxy', s.httpProxy);
    s.httpPort = port('httpPort', s.httpPort);
    s.fragment = flag('fragment', s.fragment);
    s.quickReconnect = flag('quickReconnect', s.quickReconnect);
    s.torPort = port('torPort', s.torPort);
    s.psiphonPort = port('psiphonPort', s.psiphonPort);

    final chain = j['chain'];
    if (chain == 'tor-only') {
      // Before 3, plain Tor was an "extra exit"; it is a route of its own now.
      s.protocol = 'tor';
    } else if (chain is String && Choices.chains.containsKey(chain)) {
      s.chain = chain;
    } else {
      // Settings saved by 2.4.0 kept Tor and Psiphon apart; fold them into one choice.
      final tor = j['tor'];
      final psiphon = j['psiphon'];
      if (tor == 'only') {
        s.protocol = 'tor';
      } else if (tor == 'chain') {
        s.chain = 'tor';
      } else if (psiphon == 'chain') {
        s.chain = 'psiphon';
      }
    }

    s.dns = str('dns', s.dns);
    // 'exitLoc' (the exit-country check) is gone with the IP / country lookup: ignored if saved.
    s.peer = str('peer', s.peer);
    s.darkTheme = flag('darkTheme', s.darkTheme);
    s.vpnMode = flag('vpnMode', s.vpnMode);
    s.fakeDns = flag('fakeDns', s.fakeDns);
    s.vpnIpv6 = flag('vpnIpv6', s.vpnIpv6);
    s.systemProxy = flag('systemProxy', s.systemProxy);
    s.verbose = flag('verbose', s.verbose);
    s.extraArgs = str('extraArgs', s.extraArgs);
    s.autoConnect = flag('autoConnect', s.autoConnect);
    s.autoReconnect = flag('autoReconnect', s.autoReconnect);
    s.launchAtStartup = flag('launchAtStartup', s.launchAtStartup);
    s.startInTray = flag('startInTray', s.startInTray);
    s.closeAction = str('closeAction', s.closeAction, Choices.closeActions);
    s.checkUpdates = flag('checkUpdates', s.checkUpdates);
    s.skippedVersion = str('skippedVersion', s.skippedVersion);
    s.keepHistory = flag('keepHistory', s.keepHistory);
    return s;
  }

  CoreSettings copy() => fromJson(toJson());

  /// Every local port this configuration will bind, with what it is for.
  Map<String, int> portsInUse({required bool android}) {
    final ports = <String, int>{'SOCKS5': socksPort};
    if (hasHttpProxyListener(android: android)) ports['HTTP'] = httpPort;
    if (!noTunnel && chain == 'tor') ports['Tor'] = torPort;
    if (!noTunnel && chain == 'psiphon' && !android) ports['Psiphon'] = psiphonPort;
    return ports;
  }

  /// A human-readable reason this configuration cannot start, or null when it can.
  String? problem({required bool android}) {
    final seen = <int, String>{};
    for (final e in portsInUse(android: android).entries) {
      final other = seen[e.value];
      if (other != null) {
        return 'The $other and ${e.key} proxies both want port ${e.value}. Give each its own port in Settings.';
      }
      seen[e.value] = e.key;
    }
    final p = peer.trim();
    if (!foxOnly && p.isNotEmpty && !RegExp(r'^(\[[0-9a-fA-F:.]+\]|[0-9a-zA-Z.\-:]+):\d{1,5}$').hasMatch(p)) {
      return 'The forced peer must look like ip:port, for example 162.159.198.1:443.';
    }
    return null;
  }

  static Future<CoreSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return CoreSettings();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return fromJson(decoded);
    } catch (_) {
      // A broken store must never keep the app from opening.
    }
    return CoreSettings();
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(toJson()));
    } catch (_) {}
  }
}

/// Labels for the choices, kept beside the values so the UI and the CLI never drift apart.
class Choices {
  Choices._();

  /// What the window's close button does (Windows).
  static const closeActions = <String, String>{'ask': 'Ask', 'tray': 'Tray', 'quit': 'Quit'};

  static const closeActionHints = <String, String>{
    'ask': 'Choose an action each time you close the window.',
    'tray': 'Hide the window and keep OryvexVPN running in the system tray.',
    'quit': 'Disconnect your VPN and exit OryvexVPN.',
  };

  static const protocols = <String, String>{
    'auto': 'Auto',
    'wg': 'WireGuard',
    'masque': 'MASQUE',
    'mim': 'MASQUE²',
    'gool': 'Gool',
    'tor': 'Tor',
    'bypass': 'Bypass',
    'mitm': 'MITM',
    'fox': 'Fox',
  };

  /// `auto`, `fastest` or a lowercase two-letter country code.
  static bool isTorExit(String v) => v == 'auto' || v == 'fastest' || RegExp(r'^[a-z]{2}$').hasMatch(v);

  /// The three ways to pick a Tor exit, for the segmented control.
  static const torExitModes = <String, String>{'auto': 'Auto', 'fastest': 'Fastest', 'country': 'Country'};

  static const torExitHints = <String, String>{
    'auto': 'Let Tor choose an exit, weighted by bandwidth, as Tor Browser does.',
    'fastest': 'Measure exits in the best-served countries each time you connect, then use the quickest.',
    'country': 'Choose the exit country. Tor identifies each relay using its built-in GeoIP data.',
  };

  /// How many exit relays "Best exit node" measures in the chosen country (the core's own
  /// number, kept here for the label).
  static const torExitBestProbes = 4;

  /// Which segment [torExit] belongs to.
  static String torExitMode(String torExit) =>
      torExit == 'auto' || torExit == 'fastest' ? torExit : 'country';

  /// What Auto tries, in order. The first one that connects wins.
  static const autoOrder = <String>['wg', 'masque', 'mim', 'gool'];

  /// How long Auto gives [protocol] to come up before it moves on, in seconds. The deep scans
  /// sweep whole ranges, so they get twice as long.
  static int autoTimeout(String protocol, String scan) {
    final base = switch (protocol) {
      'wg' => 30,
      'masque' => 40,
      'mim' => 50,
      _ => 60,
    };
    final deep = scan == 'thorough' || scan == 'ironclad';
    return deep ? base * 2 : base;
  }

  static const protocolHints = <String, String>{
    'auto': 'Try WireGuard, MASQUE, MASQUE², and Gool in order. Keep the first route that connects.',
    'masque': 'Use an HTTP/3 or HTTP/2 tunnel that blends in with regular HTTPS traffic.',
    'wg': 'Use WireGuard for speed when UDP traffic is allowed.',
    'gool': 'Carry WireGuard inside MASQUE to use a different exit address.',
    'mim': 'Carry MASQUE inside MASQUE to use a different exit address.',
    'tor': 'Connect directly to Tor, using bridges when needed. Choose an exit country below.',
    'bypass': 'Go out directly and reshape the first packets of each connection so filters cannot read the site name. Your address does not change. Beats packet-by-packet filters and DNS blocking, not filters that block by address.',
    'mitm': 'Go out directly and re-send YouTube, Google, Instagram, WhatsApp, Facebook, Reddit and similar sites with another site\'s name in the handshake. Needs the OryvexVPN certificate installed once, and a browser. Your address does not change.',
    'fox': 'Connect through Mozilla’s unofficial Firefox VPN service with a Firefox Account. Manage sign-in and locations in the Route card.',
  };

  /// One-line taglines for the route cards on the Connect page.
  static const protocolTaglines = <String, String>{
    'auto': 'Try each route and keep the first that connects',
    'wg': 'Fast when UDP traffic is allowed',
    'masque': 'Blends in with regular HTTPS traffic',
    'mim': 'MASQUE carried inside MASQUE',
    'gool': 'WireGuard carried inside MASQUE',
    'tor': 'Connect directly through Tor',
    'bypass': 'Direct route that slips past site-name filters',
    'mitm': 'Fronts Google, Meta and Fastly sites, no server needed',
    'fox': 'Mozilla Firefox Account connection',
  };

  /// HTTP/2 first: it is the default carrier.
  static const transports = <String, String>{'h2': 'HTTP/2', 'h3': 'HTTP/3'};

  static const transportHints = <String, String>{
    'h2': 'Uses TCP and resembles regular HTTPS. A good choice when QUIC is blocked.',
    'h3': 'Uses QUIC over UDP for a quick handshake when UDP traffic is available.',
  };

  static const scans = <String, String>{
    'turbo': 'Turbo',
    'balanced': 'Balanced',
    'thorough': 'Thorough',
    'verified': 'Verified',
    'ironclad': 'Ironclad',
  };

  static const scanHints = <String, String>{
    'turbo': 'Use the first gateway that responds.',
    'balanced': 'Compare several gateways and use the fastest one.',
    'thorough': 'Search wider address ranges when common routes are blocked.',
    'verified': 'Try only gateways that have already passed a connectivity check.',
    'ironclad': 'Verify each gateway with a real request before using it.',
  };

  static const noizes = <String, String>{
    'auto': 'Auto',
    'off': 'Off',
    'light': 'Light',
    'firewall': 'Firewall',
    'balanced': 'Balanced',
    'gfw': 'GFW',
    'aggressive': 'Aggressive',
  };

  static const ips = <String, String>{'v4': 'IPv4', 'v6': 'IPv6', 'both': 'Both'};

  static const chains = <String, String>{
    'off': 'Off',
    'tor': 'Tor via tunnel',
    'psiphon': 'Psiphon via tunnel',
  };

  static const chainHints = <String, String>{
    'off': 'Send traffic directly through the selected tunnel.',
    'tor': 'Add a second proxy inside the tunnel that exits through Tor.',
    'psiphon': 'Add a second proxy inside the tunnel that exits through Psiphon.',
  };

  static String protocolLong(String p) => switch (p) {
        'auto' => 'Auto',
        'tor' => 'Tor',
        'masque' => 'MASQUE',
        'wg' => 'WireGuard',
        'gool' => 'WireGuard in MASQUE',
        'mim' => 'MASQUE in MASQUE',
        'bypass' => 'Bypass',
        'mitm' => 'MITM (domain fronting)',
        'fox' => 'Fox (Firefox Account)',
        _ => p,
      };
}
