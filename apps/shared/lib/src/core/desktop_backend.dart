import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'args.dart';
import 'backend.dart';
import 'settings.dart';
import 'win_proxy.dart';

/// One run of the core process. Everything a run owns lives here, so a late callback from an
/// old run can never touch the state of the next one (the bug behind "connect, disconnect,
/// connect again fails until the app is restarted").
class _Session {
  _Session(this.run, this.proc, {this.systemProxyHostPort});

  final int run;
  final Process proc;
  final String? systemProxyHostPort;
  final exited = Completer<int?>();
  final subs = <StreamSubscription<String>>[];
  int openStreams = 2;
  bool proxyApplied = false;
  bool stopRequested = false;
  bool restoreWarningEmitted = false;

  bool get alive => !exited.isCompleted;
}

/// Runs the bundled core as a child process: `<app dir>/core/oryvexcore(.exe)`.
///
/// On Windows the child is started detached-with-stdio: DETACHED_PROCESS keeps a console window
/// from popping up for a console program started by a GUI one, while its output still comes back
/// over pipes. The runner (windows/runner/main.cpp) puts the app in a kill-on-close job object, so
/// the core can never outlive the window, even after a crash.
class DesktopBackend implements CoreBackend {
  final _events = StreamController<BackendEvent>.broadcast();
  final _recent = <String>[];
  _Session? _current;
  Process? _foxProcess;
  String? _foxDataPath;
  String? _foxToken;
  int _foxDashboardPort = 10820;
  int _foxRun = 0;
  bool _foxReadySent = false;
  bool _foxPolling = false;
  Timer? _foxPoll;
  Future<void>? _foxStarting;
  final _foxRecent = <String>[];

  @override
  Stream<BackendEvent> get events => _events.stream;

  @override
  bool get isAndroid => false;

  @override
  bool get supportsVpn => false;

  @override
  bool get supportsPsiphon => true;

  @override
  bool get supportsSystemProxy => Platform.isWindows;

  @override
  String get platformLabel => switch (Platform.operatingSystem) {
        'windows' => 'Windows',
        'linux' => 'Linux',
        'macos' => 'macOS',
        final other => other,
      };

  String get _sep => Platform.pathSeparator;

  String get coreDir => '${File(Platform.resolvedExecutable).parent.path}${_sep}core';

  String get coreExe => '$coreDir$_sep${Platform.isWindows ? 'oryvexcore.exe' : 'oryvexcore'}';

  String get dataDir {
    final env = Platform.environment;
    if (Platform.isWindows) {
      final base = env['APPDATA'] ?? env['USERPROFILE'] ?? coreDir;
      return '$base${_sep}OryvexCore';
    }
    final home = env['HOME'] ?? coreDir;
    return '$home$_sep.config${_sep}oryvexcore';
  }

  @override
  Future<String> installMitmCertificate() async {
    final dir = Directory(dataDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final config = '${dir.path}${_sep}oryvexcore.toml';
    final crt = File('${dir.path}${_sep}oryvexcore-mitm$_sep' 'oryvex-mitm-ca.crt');
    if (!crt.existsSync()) {
      if (!File(coreExe).existsSync()) return 'The core is missing; reinstall OryvexVPN.';
      await Process.run(coreExe, ['--config', config, '--mitm-make-ca'], workingDirectory: dir.path);
    }
    if (!crt.existsSync()) return 'Could not make the certificate. Connect once with MITM, then try again.';
    if (Platform.isWindows) {
      // The current user's trusted roots: no administrator needed. Windows asks to confirm.
      final r = await Process.run('certutil', ['-user', '-addstore', 'Root', crt.path]);
      return r.exitCode == 0
          ? 'Installed. Restart your browser, then connect. (Firefox: Settings > Privacy > View Certificates > Import.)'
          : 'Windows did not install it (you may have pressed No). The file is ${crt.path}; double-click it, choose Install Certificate > Current User > Trusted Root Certification Authorities.';
    }
    return 'Certificate saved at ${crt.path}. Add it to your system or browser as a trusted authority '
        '(Linux: copy to /usr/local/share/ca-certificates and run update-ca-certificates; macOS: Keychain Access > System > Always Trust).';
  }

  @override
  Future<BackendStatus> status() async {
    if (_foxRun != 0 && _foxProcess != null) {
      return BackendStatus(running: true, run: _foxRun, lines: List.of(_foxRecent));
    }
    final s = _current;
    return BackendStatus(
      running: s != null && s.alive,
      run: s?.run ?? 0,
      lines: List.of(_recent),
    );
  }

  void _emit(_Session s, String line) {
    if (!identical(_current, s)) return; // A line from a run that was already replaced.
    _recent.add(line);
    if (_recent.length > 600) _recent.removeRange(0, _recent.length - 600);
    _events.add(LineEvent(s.run, line));

    // Wait until the HTTP listener is actually bound before pointing Windows at it. Applying
    // WinINet's proxy as soon as the child process starts creates a short dead-proxy window and
    // can leave browsers broken if core startup fails.
    final hostPort = s.systemProxyHostPort;
    if (hostPort != null &&
        !s.proxyApplied &&
        !s.stopRequested &&
        line.contains('http proxy listening on $hostPort')) {
      s.proxyApplied = WinProxy.enable(hostPort);
      final proxyLine = s.proxyApplied
          ? '[gui] system proxy set to $hostPort'
          : '[gui] could not set the system proxy';
      _recent.add(proxyLine);
      if (_recent.length > 600) _recent.removeRange(0, _recent.length - 600);
      _events.add(LineEvent(s.run, proxyLine));
    }
  }

  @override
  Future<void> start(CoreSettings settings, int run) async {
    if (settings.foxOnly) {
      final old = _current;
      if (old != null && old.alive) await _stopSession(old);
      if (_foxRun != 0) await _stopFoxConnection();
      await _startFox(settings, run);
      return;
    }
    if (_foxProcess != null) await _stopFoxDaemon();
    final old = _current;
    if (old != null && old.alive) await _stopSession(old);

    if (!File(coreExe).existsSync()) {
      throw BackendException(
          'The core is missing ($coreExe). Reinstall OryvexVPN, keeping the core folder beside the app.');
    }
    final dir = Directory(dataDir);
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
    } on FileSystemException catch (e) {
      throw BackendException('Cannot create the settings folder ${dir.path}: ${e.message}');
    }

    final args = buildCoreArgs(
      settings,
      configPath: '${dir.path}${_sep}oryvexcore.toml',
      android: false,
    );

    final Process proc;
    try {
      proc = await Process.start(
        coreExe,
        args,
        workingDirectory: dir.path,
        environment: const {'RUST_LOG_STYLE': 'never', 'NO_COLOR': '1'},
        mode: Platform.isWindows ? ProcessStartMode.detachedWithStdio : ProcessStartMode.normal,
      );
    } on ProcessException catch (e) {
      throw BackendException('Could not start the core: ${e.message}');
    }

    final proxyHostPort = Platform.isWindows && (settings.systemProxy || settings.directOnly)
        ? '127.0.0.1:${settings.httpPort}'
        : null;
    final s = _Session(run, proc, systemProxyHostPort: proxyHostPort);
    _current = s;
    _recent.clear();
    // Nothing is ever typed into the core: a closed stdin keeps it from waiting on a question.
    unawaited(proc.stdin.close().catchError((_) {}));
    _emit(s, '[gui] started core (pid ${proc.pid}): oryvexcore ${args.join(' ')}');

    for (final stream in [proc.stdout, proc.stderr]) {
      s.subs.add(stream
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen(
            (line) => _emit(s, line),
            onDone: () => _streamDone(s),
            onError: (_) {},
            cancelOnError: false,
          ));
    }

    if (!Platform.isWindows) {
      unawaited(proc.exitCode.then((code) => _finish(s, code), onError: (_) => _finish(s, null)));
    }
  }

  void _streamDone(_Session s) {
    s.openStreams--;
    if (s.openStreams <= 0 && Platform.isWindows) {
      // A detached process has no exit code to wait on; both pipes closing means it is gone.
      _finish(s, null);
    }
  }

  void _finish(_Session s, int? code) {
    if (!s.alive) return;
    _restoreProxy(s);
    s.exited.complete(code);
    _events.add(ExitEvent(s.run, code));
  }

  void _restoreProxy(_Session s) {
    if (!Platform.isWindows) return;
    final wasApplied = s.proxyApplied;
    final restored = (!wasApplied || WinProxy.hasBackup) && WinProxy.restore();
    if (restored) {
      s.proxyApplied = false;
      if (wasApplied) _emit(s, '[gui] restored the previous Windows system proxy');
    } else if (!s.restoreWarningEmitted) {
      s.restoreWarningEmitted = true;
      _emit(s, '[gui] could not restore the Windows system proxy; recovery settings were kept for retry');
    }
  }

  Future<void> _stopSession(_Session s) async {
    if (!s.alive) return;
    s.stopRequested = true;
    _restoreProxy(s);
    final pid = s.proc.pid;
    if (Platform.isWindows) {
      // /T takes Tor's transports and Psiphon down with the core. Wait for taskkill itself to
      // finish (its pipe closes when it exits) instead of guessing with a fixed delay.
      try {
        final killer = await Process.start('taskkill', ['/PID', '$pid', '/T', '/F'],
            mode: ProcessStartMode.detachedWithStdio);
        await killer.stdout.drain<void>().timeout(const Duration(seconds: 4), onTimeout: () {});
      } catch (_) {}
    } else {
      s.proc.kill(ProcessSignal.sigterm);
    }

    await s.exited.future.timeout(const Duration(seconds: 3), onTimeout: () {
      if (Platform.isWindows) {
        Process.killPid(pid);
      } else {
        s.proc.kill(ProcessSignal.sigkill);
      }
      return null;
    });

    if (s.alive) {
      await s.exited.future.timeout(const Duration(seconds: 2), onTimeout: () => null);
    }
    if (s.alive) {
      // Its pipes are held open by something else: stop listening and call it gone.
      for (final sub in s.subs) {
        unawaited(sub.cancel());
      }
      _finish(s, null);
    }
  }

  @override
  Future<void> stop() async {
    if (_foxRun != 0) {
      await _stopFoxConnection();
      return;
    }
    final s = _current;
    if (s == null) return;
    await _stopSession(s);
  }

  @override
  Future<void> shutdown() async {
    await stop();
    await _stopFoxDaemon();
    WinProxy.restore();
  }

  @override
  Future<bool> openFoxDashboard() async {
    try {
      await _ensureFoxDaemon();
      final result = await _foxApi('POST', '/api/session/link', const <String, Object?>{});
      final path = result['path'];
      if (path is! String || !path.startsWith('/')) return false;
      final url = 'http://127.0.0.1:$_foxDashboardPort$path';
      final opened = switch (Platform.operatingSystem) {
        'windows' => await Process.start('cmd', ['/c', 'start', '', url], mode: ProcessStartMode.detached),
        'macos' => await Process.start('open', [url], mode: ProcessStartMode.detached),
        _ => await Process.start('xdg-open', [url], mode: ProcessStartMode.detached),
      };
      return opened.pid > 0;
    } catch (_) {
      return false;
    }
  }

  String get _foxExecutable =>
      '$coreDir$_sep${Platform.isWindows ? 'fox-core.exe' : 'fox-core'}';

  String get _foxDataDir {
    if (_foxDataPath != null) return _foxDataPath!;
    final base = Platform.isWindows
        ? (Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? coreDir)
        : (Platform.environment['HOME'] ?? coreDir);
    _foxDataPath = Platform.isWindows
        ? '$base${_sep}OryvexVPN${_sep}Fox'
        : '$base${_sep}.config${_sep}OryvexVPN${_sep}Fox';
    return _foxDataPath!;
  }

  Future<int> _availableDashboardPort() async {
    for (final port in [10820, ...List<int>.generate(64, (i) => 18220 + i)]) {
      try {
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
        await socket.close();
        return port;
      } on SocketException {
        // Try the next private loopback port.
      }
    }
    throw BackendException('No free local port is available for the Fox dashboard.');
  }

  Future<void> _writeFoxConfig(CoreSettings? settings) async {
    final dir = Directory(_foxDataDir);
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}${_sep}config.json');
    Map<String, dynamic> root = <String, dynamic>{};
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) root = decoded;
      } catch (_) {
        throw BackendException('Fox settings are not valid JSON. Back up and repair ${file.path}.');
      }
    }
    final proxy = root['proxy'] is Map
        ? Map<String, dynamic>.from(root['proxy'] as Map)
        : <String, dynamic>{};
    if (settings != null) {
      final host = settings.shareLan ? '0.0.0.0' : '127.0.0.1';
      proxy['listen'] = '$host:${settings.socksPort}';
    } else {
      proxy.putIfAbsent('listen', () => '127.0.0.1:1819');
    }
    root['proxy'] = proxy;
    final dashboard = root['dashboard'] is Map
        ? Map<String, dynamic>.from(root['dashboard'] as Map)
        : <String, dynamic>{};
    var port = 0;
    final listen = dashboard['listen'];
    if (listen is String) port = int.tryParse(listen.split(':').last) ?? 0;
    if (port < 1 || port > 65535 || !await _foxPortIsFree(port)) {
      port = await _availableDashboardPort();
    }
    dashboard['listen'] = '127.0.0.1:$port';
    root['dashboard'] = dashboard;
    _foxDashboardPort = port;
    await file.writeAsString('${const JsonEncoder.withIndent('  ').convert(root)}\n', flush: true);
  }

  Future<void> _ensureFoxDaemon({CoreSettings? settings}) async {
    final running = _foxProcess;
    if (running != null) {
      if (settings != null) {
        final response = await _foxApi('GET', '/api/settings');
        final currentConfig = response['config'];
        final proxy = currentConfig is Map ? currentConfig['proxy'] : null;
        if (currentConfig is Map && proxy is Map) {
          final wanted = '${settings.shareLan ? '0.0.0.0' : '127.0.0.1'}:${settings.socksPort}';
          if (proxy['listen'] != wanted) {
            final nextConfig = Map<String, dynamic>.from(currentConfig);
            nextConfig['proxy'] = Map<String, dynamic>.from(proxy)..['listen'] = wanted;
            await _foxApi('PUT', '/api/settings', <String, Object?>{'config': nextConfig});
          }
        }
      }
      return;
    }
    final pending = _foxStarting;
    if (pending != null) {
      await pending;
      return _ensureFoxDaemon(settings: settings);
    }
    final completer = Completer<void>();
    _foxStarting = completer.future;
    try {
      final exe = File(_foxExecutable);
      if (!await exe.exists()) {
        throw BackendException('Fox core is missing (${exe.path}). Reinstall the Windows setup package.');
      }
      await _writeFoxConfig(settings);
      final proc = await Process.start(
        exe.path,
        ['-app', '-data-dir', _foxDataDir],
        workingDirectory: _foxDataDir,
        mode: Platform.isWindows ? ProcessStartMode.detachedWithStdio : ProcessStartMode.normal,
      );
      _foxProcess = proc;
      _foxToken = null;
      for (final stream in [proc.stdout, proc.stderr]) {
        stream
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .listen((line) {
          if (_foxRun != 0) _emitFox(_foxRun, line);
        }, onError: (_) {}, cancelOnError: false);
      }
      unawaited(proc.exitCode.then((code) {
        if (!identical(_foxProcess, proc)) return;
        final run = _foxRun;
        _foxPoll?.cancel();
        _foxPoll = null;
        _foxProcess = null;
        _foxToken = null;
        _foxRun = 0;
        if (run != 0) _events.add(ExitEvent(run, code));
      }, onError: (_) {}));

      // The -app process intentionally keeps running while stdin remains open.
      final tokenFile = File('${_foxDataDir}${_sep}local-api.token');
      for (var i = 0; i < 60; i++) {
        if (_foxProcess == null) throw BackendException('Fox core stopped during startup.');
        if (await tokenFile.exists()) {
          final token = (await tokenFile.readAsString()).trim();
          if (token.isNotEmpty) {
            _foxToken = token;
            try {
              await _foxApi('GET', '/api/status');
              completer.complete();
              return;
            } catch (_) {}
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      throw BackendException('Fox core did not start its local dashboard. Check its log in ${_foxDataDir}${_sep}logs.');
    } catch (e) {
      if (!completer.isCompleted) completer.completeError(e);
      rethrow;
    } finally {
      _foxStarting = null;
    }
  }

  Future<Map<String, dynamic>> _foxApi(String method, String path, [Object? body]) async {
    final token = _foxToken;
    if (token == null || token.isEmpty) throw BackendException('Fox dashboard token is not ready yet.');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client.openUrl(method, Uri.parse('http://127.0.0.1:$_foxDashboardPort$path'));
      req.headers.set('X-Local-Token', token);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final text = await utf8.decoder.bind(resp).join();
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw BackendException('Fox dashboard returned HTTP ${resp.statusCode}.');
      }
      if (text.isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      throw BackendException('Fox dashboard returned an unexpected response.');
    } finally {
      client.close(force: true);
    }
  }

  void _emitFox(int run, String line) {
    if (run != _foxRun) return;
    _foxRecent.add(line);
    if (_foxRecent.length > 600) _foxRecent.removeRange(0, _foxRecent.length - 600);
    _events.add(LineEvent(run, line));
  }

  Future<void> _startFox(CoreSettings settings, int run) async {
    _foxRun = run;
    _foxReadySent = false;
    _foxRecent.clear();
    try {
      await _ensureFoxDaemon(settings: settings);
    } catch (e) {
      _foxRun = 0;
      rethrow;
    }
    _emitFox(run, '[*] Fox service starting');
    try {
      await _foxApi('POST', '/api/power', const <String, Object?>{'on': true});
    } catch (e) {
      _foxRun = 0;
      throw BackendException('Could not start Fox: $e');
    }
    _foxPoll?.cancel();
    _foxPoll = Timer.periodic(const Duration(seconds: 2), (_) => _pollFox(settings, run));
    unawaited(_pollFox(settings, run));
  }

  Future<void> _pollFox(CoreSettings settings, int run) async {
    if (_foxPolling || _foxRun != run || _foxProcess == null) return;
    _foxPolling = true;
    try {
      final status = await _foxApi('GET', '/api/status');
      if (_foxRun != run) return;
      final state = status['state'] is Map ? Map<String, dynamic>.from(status['state'] as Map) : const <String, dynamic>{};
      final phase = state['phase'];
      if (phase == 'running' && status['proxy'] != null && status['connect_pending'] != true) {
        if (!_foxReadySent) {
          _foxReadySent = true;
          _emitFox(run, '[+] socks5 server listening on 127.0.0.1:${settings.socksPort}');
        }
      } else if ((phase == 'error' || phase == 'waiting') && status['connect_pending'] != true) {
        final message = state['message'] is String ? state['message'] as String : 'Fox could not establish a connection.';
        _emitFox(run, '[-] Fox: $message');
        _foxPoll?.cancel();
        _foxPoll = null;
        _foxRun = 0;
        _events.add(ExitEvent(run, 1));
      }
    } catch (e) {
      // The service can be between restarts; keep polling, but don't spam Activity.
    } finally {
      _foxPolling = false;
    }
  }

  Future<void> _stopFoxConnection() async {
    final run = _foxRun;
    _foxPoll?.cancel();
    _foxPoll = null;
    if (run == 0) return;
    try {
      await _foxApi('POST', '/api/power', const <String, Object?>{'on': false});
    } catch (_) {}
    _foxRun = 0;
    _foxReadySent = false;
    _events.add(ExitEvent(run, 0));
  }

  Future<void> _stopFoxDaemon() async {
    final proc = _foxProcess;
    if (proc == null) return;
    await _stopFoxConnection();
    try {
      await _foxApi('POST', '/api/app/exit');
    } catch (_) {}
    try {
      await proc.stdin.close();
    } catch (_) {}
    try {
      await proc.exitCode.timeout(const Duration(seconds: 4));
    } catch (_) {
      proc.kill(ProcessSignal.sigkill);
    }
    if (identical(_foxProcess, proc)) _foxProcess = null;
    _foxToken = null;
  }

  Future<bool> _foxPortIsFree(int port) async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }
}
