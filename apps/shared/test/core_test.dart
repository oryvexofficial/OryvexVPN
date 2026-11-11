import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oryvex_shared/src/core/args.dart';
import 'package:oryvex_shared/src/core/bypass_services.dart';
import 'package:oryvex_shared/src/core/log_line.dart';
import 'package:oryvex_shared/src/core/route_about.dart';
import 'package:oryvex_shared/src/core/settings.dart';
import 'package:oryvex_shared/src/core/update_service.dart';
import 'package:oryvex_shared/src/core/steps.dart';
import 'package:oryvex_shared/src/core/tor_exits.dart';
import 'package:oryvex_shared/src/core/win_startup.dart';
import 'package:oryvex_shared/src/ui/theme.dart';

void main() {
  test('default settings build a prompt-free command line', () {
    final args = buildCoreArgs(CoreSettings()..protocol = 'masque', configPath: '/tmp/o.toml', android: true);
    expect(args, containsAllInOrder(['--config', '/tmp/o.toml', '--bind', '127.0.0.1:1819']));
    expect(args, containsAll(['--protocol', 'masque', '--scan', 'balanced', '-4', '--h2']));
    expect(args, contains('--quick-reconnect'));
  });

  test('HTTP/2 is the default carrier, and old HTTP/3 defaults move to it once', () {
    expect(CoreSettings().transport, 'h2');
    expect(Choices.transports.keys.first, 'h2');
    expect(CoreSettings.fromJson({'transport': 'h3'}).transport, 'h2');
    final kept = CoreSettings()..transport = 'h3';
    expect(CoreSettings.fromJson(kept.toJson()).transport, 'h3');
  });

  test('best exit node is asked for with a single country only', () {
    final country = buildCoreArgs(CoreSettings()
      ..protocol = 'tor'
      ..torExit = 'de', configPath: 'x', android: false);
    expect(country, containsAllInOrder(['--tor-exit', 'de', '--tor-exit-best']));
    final off = buildCoreArgs(CoreSettings()
      ..protocol = 'tor'
      ..torExit = 'de'
      ..torExitBest = false, configPath: 'x', android: false);
    expect(off, isNot(contains('--tor-exit-best')));
    final fastest = buildCoreArgs(CoreSettings()
      ..protocol = 'tor'
      ..torExit = 'fastest', configPath: 'x', android: false);
    expect(fastest, isNot(contains('--tor-exit-best')));
  });

  test('every bundled exit country has a flag picture', () {
    expect(bundledTorExitCodes.length, greaterThanOrEqualTo(60));
    for (final cc in bundledTorExitCodes) {
      expect(flagAsset(cc), 'assets/flags/$cc.png');
      expect(hasFlagAsset(cc), isTrue, reason: cc);
    }
  });

  test('wireguard never gets a MASQUE carrier flag', () {
    final s = CoreSettings()..protocol = 'wg';
    final args = buildCoreArgs(s, configPath: 'x', android: false);
    expect(args, isNot(contains('--h3')));
    expect(args, isNot(contains('--h2')));
  });

  test('auto is the default and starts with WireGuard', () {
    expect(CoreSettings().protocol, 'auto');
    expect(Choices.autoOrder, ['wg', 'masque', 'mim', 'gool']);
    final args = buildCoreArgs(CoreSettings(), configPath: 'x', android: false);
    expect(args, containsAllInOrder(['--protocol', 'wg']));
  });

  test('settings saved with the old MASQUE default move to auto once', () {
    expect(CoreSettings.fromJson({'protocol': 'masque'}).protocol, 'auto');
    final kept = CoreSettings()..protocol = 'masque';
    expect(CoreSettings.fromJson(kept.toJson()).protocol, 'masque');
  });

  test('SSTP is gone: old SSTP settings move to Auto', () {
    expect(Choices.protocols.containsKey('sstp'), isFalse);
    final s = CoreSettings.fromJson({'protocol': 'sstp', 'protocolVersion': 2, 'sstpServer': 'x.opengw.net'});
    expect(s.protocol, 'auto');
    expect(s.toJson().containsKey('sstpServer'), isFalse);
  });

  test('Tor is a route of its own, and the old "Tor only" exit becomes it', () {
    expect(Choices.protocols['tor'], 'Tor');
    expect((CoreSettings()..protocol = 'tor').torOnly, isTrue);
    final old = CoreSettings.fromJson({'protocol': 'wg', 'protocolVersion': 2, 'chain': 'tor-only'});
    expect(old.protocol, 'tor');
    expect(old.chain, 'off');
    expect(CoreSettings.fromJson({'tor': 'only'}).protocol, 'tor');
  });

  test('the Tor route asks for no tunnel and passes the exit choice', () {
    final auto = buildCoreArgs(CoreSettings()..protocol = 'tor', configPath: 'x', android: true);
    expect(auto, contains('--tor-only'));
    expect(auto, isNot(contains('--protocol')));
    expect(auto, isNot(contains('--tor-exit')));

    final fastest = buildCoreArgs(CoreSettings()
      ..protocol = 'tor'
      ..torExit = 'fastest', configPath: 'x', android: false);
    expect(fastest, containsAllInOrder(['--tor-exit', 'fastest']));

    final strict = buildCoreArgs(CoreSettings()
      ..protocol = 'wg'
      ..chain = 'tor'
      ..torExit = 'de'
      ..torExitStrict = true, configPath: 'x', android: false);
    expect(strict, containsAllInOrder(['--tor', '--tor-bind']));
    expect(strict, containsAllInOrder(['--tor-exit', 'de', '--tor-exit-strict']));

    // Without Tor in play the exit choice is not passed.
    final none = buildCoreArgs(CoreSettings()
      ..protocol = 'wg'
      ..torExit = 'de', configPath: 'x', android: false);
    expect(none, isNot(contains('--tor-exit')));
  });

  test('Bypass asks for no tunnel, no scan and no WARP identity', () {
    final s = CoreSettings()..protocol = 'bypass';
    expect(s.bypassOnly, isTrue);
    expect(s.noTunnel, isTrue);
    expect(s.torOnly, isFalse);
    final args = buildCoreArgs(s, configPath: '/tmp/o.toml', android: false);
    expect(args, containsAll(['--bypass', '-4', '--bypass-doh', '--bypass-drop-quic']));
    expect(args, isNot(contains('--protocol')));
    expect(args, isNot(contains('--scan')));
    expect(args, isNot(contains('--tor-only')));
  });

  test('MITM asks the core for its own fronting proxy and nothing else', () {
    final s = CoreSettings()..protocol = 'mitm';
    expect(s.mitmOnly, isTrue);
    expect(s.directOnly, isTrue);
    expect(s.noTunnel, isTrue);
    final args = buildCoreArgs(s, configPath: '/tmp/o.toml', android: false);
    expect(args, contains('--mitm'));
    expect(args, containsAll(['--http-proxy', '127.0.0.1:1820']));
    expect(args, isNot(contains('--bypass')));
    expect(args, isNot(contains('--protocol')));
    expect(Choices.protocols.containsKey('mitm'), isTrue);
    expect(Choices.autoOrder, isNot(contains('mitm')));
  });

  test('MITM closes its stages from the core\'s lines', () {
    final plan = ConnectionPlan.of(CoreSettings()..protocol = 'mitm', android: false)..begin();
    expect(plan.steps.map((x) => x.id), ['start', 'mitm', 'ready']);
    plan.ingest('[*] starting the mitm engine');
    plan.ingest('[+] mitm certificate: /x/oryvex-mitm-ca.crt');
    plan.ingest('[+] socks5 server listening on 127.0.0.1:1819');
    expect(plan.steps.every((x) => x.status == StepStatus.done), isTrue);
  });

  test('every connection has an About text', () {
    for (final id in Choices.protocols.keys) {
      expect(routeAbout[id], isNotNull, reason: id);
      expect(routeAbout[id]!.how, isNotEmpty, reason: id);
    }
  });

  test('Windows Bypass automatically gets an HTTP listener for the system proxy', () {
    final s = CoreSettings()..protocol = 'bypass';
    final windows = buildCoreArgs(s, configPath: 'x', android: false);
    expect(windows, containsAll(['--http-proxy', '127.0.0.1:1820']));
    expect(s.portsInUse(android: false), {'SOCKS5': 1819, 'HTTP': 1820});

    // Android routes traffic through VpnService and must not bind the extra Windows listener.
    final android = buildCoreArgs(s, configPath: 'x', android: true);
    expect(android, isNot(contains('--http-proxy')));
    expect(s.portsInUse(android: true), {'SOCKS5': 1819});
  });

  test('an automatic Windows Bypass HTTP-port collision is caught before launch', () {
    final s = CoreSettings()
      ..protocol = 'bypass'
      ..socksPort = 1820;
    expect(s.problem(android: false), contains('both want port 1820'));
    expect(s.problem(android: true), isNull);
  });

  test('the optional Windows system proxy still adds HTTP support to other routes', () {
    final s = CoreSettings()
      ..protocol = 'wg'
      ..systemProxy = true;
    final windows = buildCoreArgs(s, configPath: 'x', android: false);
    expect(windows, containsAll(['--http-proxy', '127.0.0.1:1820']));
    final android = buildCoreArgs(s, configPath: 'x', android: true);
    expect(android, isNot(contains('--http-proxy')));
  });

  test('Bypass options reach the core and survive a save/load round trip', () {
    final s = CoreSettings()
      ..protocol = 'bypass'
      ..bypassDoh = false
      ..bypassDropQuic = false
      ..ip = 'both';
    final args = buildCoreArgs(s, configPath: '', android: true);
    expect(args, containsAll(['--bypass-no-doh', '--bypass-keep-quic', '--dual']));
    final back = CoreSettings.fromJson(s.toJson());
    expect(back.protocol, 'bypass');
    expect(back.bypassDoh, isFalse);
    expect(back.bypassDropQuic, isFalse);
    expect(Choices.protocols.containsKey('bypass'), isTrue);
    expect(Choices.autoOrder, isNot(contains('bypass')));
  });

  test('the Bypass route has its own stages and closes them from the core\'s lines', () {
    final plan = ConnectionPlan.of(CoreSettings()..protocol = 'bypass', android: false)..begin();
    expect(plan.steps.map((x) => x.id), ['start', 'bypass', 'ready']);
    plan.ingest('[*] starting the bypass engine from /x/oryvex-bypass');
    plan.ingest('[+] socks5 server listening on 127.0.0.1:1819');
    plan.ingest('[+] bypass is ready; 127.0.0.1:1819 reaches the internet directly');
    expect(plan.steps.every((x) => x.status == StepStatus.done), isTrue);
  });

  test('tor exit choices are validated on load', () {
    expect(CoreSettings.fromJson({'torExit': 'nl'}).torExit, 'nl');
    expect(CoreSettings.fromJson({'torExit': 'fastest'}).torExit, 'fastest');
    expect(CoreSettings.fromJson({'torExit': 'Germany'}).torExit, 'auto');
    expect(Choices.torExitMode('de'), 'country');
    expect(Choices.torExitMode('auto'), 'auto');
  });

  test('the core\'s exit directory line is read', () {
    const line = '[=] tor-exits {"updated":1793000000,"source":"onionoo","countries":['
        '{"cc":"de","name":"Germany","relays":412,"bandwidth":2300000000,"probability":0.31},'
        '{"cc":"nl","name":"Netherlands","relays":190,"bandwidth":900000000,"probability":0.12},'
        '{"cc":"XX1","name":"broken"}]}';
    final dir = TorExitDirectory.fromLogLine(line);
    expect(dir, isNotNull);
    expect(dir!.source, 'onionoo');
    expect(dir.countries.map((c) => c.code), ['de', 'nl']);
    expect(dir.totalRelays, 602);
    expect(dir.countries.first.detail, '412 exits · 18.4 Gbit/s');
    expect(TorExitDirectory.decode(dir.encode())!.countries.length, 2);
    expect(TorExitDirectory.fromLogLine('[+] tor is ready'), isNull);
  });

  test('the bundled exit list stands in before the first fetch', () {
    final dir = TorExitDirectory.bundled();
    expect(dir.isBundled, isTrue);
    expect(dir.countries.length, bundledTorExitCodes.length);
    expect(dir.countries.every((c) => isCountryCode(c.code)), isTrue);
    expect(dir.nameOf('de'), 'Germany');
  });

  test('the exit the core settled on is read', () {
    expect(TorExitDirectory.exitInUse('[+] tor exit: using de (Germany), the fastest at 842 ms'), ('de', 842));
    expect(TorExitDirectory.exitInUse('[+] tor exit: using auto (tor picks a fast exit, weighted by bandwidth)'),
        ('auto', null));
    expect(TorExitDirectory.exitInUse('[*] tor exit: trying DE (Germany)'), isNull);
  });

  test('the Tor route shows a Tor exit stage that the core closes', () {
    final s = CoreSettings()
      ..protocol = 'tor'
      ..torExit = 'fastest';
    final plan = ConnectionPlan.of(s, android: false)..begin();
    expect(plan.steps.map((x) => x.id), ['start', 'tor', 'exit', 'ready']);
    plan.ingest('[*] bootstrapping tor with no tunnel underneath it');
    plan.ingest('[+] tor is ready; 127.0.0.1:1819 leaves through tor');
    plan.ingest('[*] tor exit: trying NL (Netherlands)');
    expect(plan.steps[2].detail, 'Trying NL');
    plan.ingest('[+] tor exit: using nl (Netherlands), the fastest at 610 ms');
    expect(plan.steps[2].status, StepStatus.done);
    expect(plan.steps[2].detail, 'NL · 610 ms');
  });

  test('dark mode is the default and old settings retain the default', () {
    expect(CoreSettings().darkTheme, isTrue);
    expect(CoreSettings.fromJson({'protocol': 'wg'}).darkTheme, isTrue);
    expect(CoreSettings.fromJson({'darkTheme': false}).darkTheme, isFalse);
    expect((CoreSettings()..darkTheme = false).toJson()['darkTheme'], isFalse);
  });

  test('theme choice survives a settings save/load round trip', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = CoreSettings()..darkTheme = false;
    await settings.save();
    expect((await CoreSettings.load()).darkTheme, isFalse);
  });

  test('selected theme builds the matching full palette', () {
    final light = buildOxTheme(dark: false);
    expect(light.brightness, Brightness.light);
    expect(Ox.darkMode, isFalse);
    expect(Ox.canvas, const Color(0xFFF2F3F7));
    expect(Ox.text, const Color(0xFF111318));

    final dark = buildOxTheme(dark: true);
    expect(dark.brightness, Brightness.dark);
    expect(Ox.darkMode, isTrue);
    expect(Ox.canvas, const Color(0xFF06080C));
    expect(Ox.text, const Color(0xFFF4F6FA));
  });

  test('update versions compare numerically', () {
    expect(isNewerVersion('1.2.10', '1.2.9'), isTrue);
    expect(isNewerVersion('v1.1.0', '1.1.0'), isFalse);
    expect(isNewerVersion('2.0', '1.9.9+300'), isTrue);
  });

  test('app behaviour options round-trip and validate', () {
    final d = CoreSettings();
    expect(d.autoConnect, isFalse);
    expect(d.autoReconnect, isTrue);
    expect(d.launchAtStartup, isFalse);
    expect(d.startInTray, isTrue);
    expect(d.closeAction, 'ask');
    final s = CoreSettings()
      ..autoConnect = true
      ..autoReconnect = false
      ..launchAtStartup = true
      ..startInTray = false
      ..closeAction = 'tray';
    final back = CoreSettings.fromJson(s.toJson());
    expect(back.autoConnect, isTrue);
    expect(back.autoReconnect, isFalse);
    expect(back.launchAtStartup, isTrue);
    expect(back.startInTray, isFalse);
    expect(back.closeAction, 'tray');
    expect(CoreSettings.fromJson({'closeAction': 'explode'}).closeAction, 'ask');
  });

  test('sign-in command quotes the exe and adds the tray flag', () {
    const exe = r'C:\Program Files\OryvexVPN\OryvexVPN.exe';
    expect(WinStartup.commandFor(exe, inTray: true), '"$exe" --background');
    expect(WinStartup.commandFor(exe, inTray: false), '"$exe"');
  });

  test('extra args honour quotes', () {
    expect(splitArgs('--a "b c" \'d\''), ['--a', 'b c', 'd']);
  });

  test('env_logger lines parse', () {
    final l = LogLine.parse('[2026-10-29T18:00:00.123Z INFO  oryvexcore::socks] [+] socks5 server listening on 127.0.0.1:1819');
    expect(l.level, LogLevel.info);
    expect(l.message, '[+] socks5 server listening on 127.0.0.1:1819');
  });

  test('every Bypass list service has its icon and a note', () {
    expect(bypassServices, isNotEmpty);
    expect(bypassServices.map((s) => s.id).toSet().length, bypassServices.length);
    for (final s in bypassServices) {
      expect(File(s.icon).existsSync(), isTrue, reason: s.icon);
      expect(s.note.trim(), isNotEmpty, reason: s.id);
    }
  });
}

