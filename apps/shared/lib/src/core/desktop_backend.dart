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
  _Session(this.run, this.proc);

  final int run;
  final Process proc;
  final exited = Completer<int?>();
  final subs = <StreamSubscription<String>>[];
  int openStreams = 2;
  bool proxyApplied = false;

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
  Future<BackendStatus> status() async {
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
  }

  @override
  Future<void> start(CoreSettings settings, int run) async {
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

    final s = _Session(run, proc);
    _current = s;
    _recent.clear();
    // Nothing is ever typed into the core: a closed stdin keeps it from waiting on a question.
    unawaited(proc.stdin.close().catchError((_) {}));
    _emit(s, '[gui] started core (pid ${proc.pid}): oryvexcore ${args.join(' ')}');

    if (settings.systemProxy && supportsSystemProxy) {
      final host = '127.0.0.1:${settings.httpPort}';
      s.proxyApplied = WinProxy.enable(host);
      _emit(s, s.proxyApplied ? '[gui] system proxy set to $host' : '[gui] could not set the system proxy');
    }

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
    if (s.proxyApplied) {
      WinProxy.restore();
      s.proxyApplied = false;
    }
  }

  Future<void> _stopSession(_Session s) async {
    if (!s.alive) return;
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
    final s = _current;
    if (s == null) return;
    await _stopSession(s);
  }

  @override
  Future<void> shutdown() async {
    await stop();
    WinProxy.restore();
  }
}
