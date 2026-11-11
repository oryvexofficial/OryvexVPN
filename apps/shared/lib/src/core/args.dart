import 'settings.dart';

bool usesMasqueCarrier(String protocol) =>
    protocol == 'masque' || protocol == 'gool' || protocol == 'mim';

/// Builds the oryvexcore command line for [s]. Every question the core could ask is answered
/// here, and stdin is never a terminal under the GUI, so the core never stops to prompt.
List<String> buildCoreArgs(
  CoreSettings s, {
  required String configPath,
  required bool android,
}) {
  final host = s.shareLan ? '0.0.0.0' : '127.0.0.1';
  final args = <String>[
    '--config', configPath,
    '--bind', '$host:${s.socksPort}',
  ];

  if (s.mitmOnly) {
    // No tunnel, no identity, no engine process: the core itself fronts the listed sites.
    args.add('--mitm');
  } else if (s.bypassOnly) {
    // No tunnel and no WARP identity: the core runs its bypass engine on the SOCKS5 port.
    args.add('--bypass');
    switch (s.ip) {
      case 'v6':
        args.add('-6');
      case 'both':
        args.add('--dual');
      default:
        args.add('-4');
    }
    args.add(s.bypassDoh ? '--bypass-doh' : '--bypass-no-doh');
    args.add(s.bypassDropQuic ? '--bypass-drop-quic' : '--bypass-keep-quic');
  } else if (s.torOnly) {
    // No tunnel: protocol, scan and carrier mean nothing, and Tor needs no WARP identity.
    args.add('--tor-only');
  } else {
    // auto is the app's own choice: the controller swaps in the protocol each Auto attempt
    // uses. WireGuard is the safe answer if one slips by.
    final protocol = Choices.autoOrder.contains(s.protocol) ? s.protocol : Choices.autoOrder.first;
    args.addAll(['--protocol', protocol, '--scan', s.scan]);
    switch (s.ip) {
      case 'v6':
        args.add('-6');
      case 'both':
        args.add('--dual');
      default:
        args.add('-4');
    }
    if (usesMasqueCarrier(protocol)) {
      args.add(s.transport == 'h2' ? '--h2' : '--h3');
    }
    if (s.fragment) args.add('--fragment');
    if (s.noize != 'auto') args.addAll(['--noize', s.noize]);
    args.add(s.quickReconnect ? '--quick-reconnect' : '--no-quick-reconnect');

    if (s.chain == 'tor') {
      args.addAll(['--tor', '--tor-bind', '$host:${s.torPort}']);
    } else if (s.chain == 'psiphon' && !android) {
      args.addAll(['--psiphon', '--psiphon-bind', '$host:${s.psiphonPort}']);
    }

    final peer = s.peer.trim();
    if (peer.isNotEmpty) args.addAll(['--peer', peer]);
    final dns = s.dns.trim();
    if (dns.isNotEmpty) args.addAll(['--dns', dns]);
  }

  if (s.usesTorExit && s.torExit != 'auto') {
    args.addAll(['--tor-exit', s.torExit]);
    if (s.torExitStrict) args.add('--tor-exit-strict');
    // A single country: measure a few of its exits and keep the quickest circuit.
    if (s.torExitBest && Choices.torExitMode(s.torExit) == 'country') args.add('--tor-exit-best');
  }

  // On Windows, Bypass can route the system proxy directly to its local HTTP forwarder.
  // Android's whole-device VPN handles traffic below the app proxy layer, so it does not need
  // this extra listener unless the user explicitly asked for one.
  final wantHttp = s.httpProxy || (!android && (s.systemProxy || s.directOnly));
  if (wantHttp) args.addAll(['--http-proxy', '$host:${s.httpPort}']);

  // Live traffic counters for the dashboard.
  args.addAll(['--stats', '--stats-secs', '2']);
  if (s.verbose) args.add('--verbose');

  args.addAll(splitArgs(s.extraArgs));
  return args;
}

/// Splits a user-typed argument string, honouring "double" and 'single' quotes.
List<String> splitArgs(String input) {
  final out = <String>[];
  final buf = StringBuffer();
  String? quote;
  var has = false;
  for (final ch in input.split('')) {
    if (quote != null) {
      if (ch == quote) {
        quote = null;
      } else {
        buf.write(ch);
      }
      continue;
    }
    if (ch == '"' || ch == "'") {
      quote = ch;
      has = true;
    } else if (ch.trim().isEmpty) {
      if (has || buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
        has = false;
      }
    } else {
      buf.write(ch);
    }
  }
  if (has || buf.isNotEmpty) out.add(buf.toString());
  return out;
}
