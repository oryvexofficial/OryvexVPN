import 'dart:async';

import 'package:flutter/services.dart';

import 'args.dart';
import 'backend.dart';
import 'settings.dart';

/// Talks to OryvexVpnService (apps/android-src/android/.../OryvexVpnService.kt), which runs the
/// core binary from the APK's native library dir and, in VPN mode, feeds a tun device into it
/// through hev-socks5-tunnel.
///
/// Lines reach the UI two ways, and both are needed:
///  * pushed over the `oryvexcore/events` stream as they are written, and
///  * pulled every [_pollEvery] with `since(seq)` while a session is live.
/// Each line carries a sequence number from the service, so a line that arrives both ways is
/// shown once. The pull is what keeps Activity and the Connect page moving if the stream is ever
/// late or silent.
///
/// 2.4.1 subscribed to the stream in this class's constructor, which ran before Flutter's
/// bindings existed (`runOryvex(AndroidBackend())` evaluates the argument first). The subscribe
/// failed silently, no line ever arrived, and the Connect page sat on "Identity" with an empty
/// log. The stream is now attached lazily, after `WidgetsFlutterBinding.ensureInitialized()`.
class AndroidBackend implements CoreBackend {
  AndroidBackend();

  static const _method = MethodChannel('oryvexcore/core');
  static const _eventChannel = EventChannel('oryvexcore/events');
  static const _pollEvery = Duration(milliseconds: 1200);

  final _events = StreamController<BackendEvent>.broadcast();
  StreamSubscription<dynamic>? _native;
  bool _attached = false;

  /// Highest line sequence number already handed to the UI.
  int _seq = 0;

  /// The session we are following, and what we last told the UI about it.
  int _run = 0;
  bool _vpnUp = false;
  final Set<int> _exited = <int>{};

  Timer? _poll;
  bool _polling = false;
  bool _askedNotifications = false;

  /// The run whose exit we are waiting for in [stop].
  Completer<void>? _stopped;
  int _stoppingRun = 0;

  @override
  Stream<BackendEvent> get events {
    _attach();
    return _events.stream;
  }

  @override
  bool get isAndroid => true;

  @override
  bool get supportsVpn => true;

  @override
  bool get supportsPsiphon => false;

  @override
  bool get supportsSystemProxy => false;

  @override
  String get platformLabel => 'Android';

  static int _int(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);

  void _attach() {
    if (_attached) return;
    _attached = true;
    try {
      _native = _eventChannel.receiveBroadcastStream().listen(
        _onNative,
        onError: (Object _) {},
        cancelOnError: false,
      );
    } catch (_) {
      // No stream at all: the pull below still carries every line.
      _native = null;
    }
  }

  void _onNative(dynamic event) {
    if (event is! Map) return;
    final run = _int(event['run']);
    switch (event['type']) {
      case 'line':
        final line = event['line'];
        if (line is String) _line(run, _int(event['seq']), line);
      case 'exit':
        final code = event['code'];
        _exit(run, code is int ? code : null);
      case 'vpn':
        final error = event['error'];
        _vpn(run, event['up'] == true, error is String ? error : null);
    }
  }

  void _line(int run, int seq, String line) {
    if (seq > 0) {
      if (seq <= _seq) return; // Already delivered by the other path.
      _seq = seq;
    }
    _events.add(LineEvent(run, line));
  }

  void _vpn(int run, bool up, String? error) {
    _vpnUp = up;
    _events.add(VpnEvent(run, up, error));
  }

  void _exit(int run, int? code) {
    if (run != 0 && !_exited.add(run)) return; // Exit already reported for this session.
    _events.add(ExitEvent(run, code));
    final waiting = _stopped;
    if (waiting != null && !waiting.isCompleted && (run == _stoppingRun || _stoppingRun == 0)) {
      waiting.complete();
    }
    if (run == _run) _stopPolling();
  }

  // --- pull ---------------------------------------------------------------------------------

  void _startPolling(int run) {
    _run = run;
    _poll ??= Timer.periodic(_pollEvery, (_) => _pull());
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> _pull() async {
    if (_polling) return;
    _polling = true;
    try {
      final r = await _method.invokeMapMethod<String, dynamic>('since', {'seq': _seq});
      if (r == null) return;
      final run = _int(r['run']);
      final lines = (r['lines'] as List?) ?? const [];
      final seqs = (r['seqs'] as List?) ?? const [];
      for (var i = 0; i < lines.length; i++) {
        final text = lines[i];
        if (text is String) _line(run, i < seqs.length ? _int(seqs[i]) : 0, text);
      }
      // A newer live session than the one we follow (the system's always-on VPN started one):
      // follow it from now on. Older sessions are never adopted; their state is history.
      if (r['running'] == true && run > _run) _run = run;
      final up = r['vpn'] == true;
      if (up != _vpnUp && run == _run) {
        final err = r['vpnError'];
        _vpn(run, up, !up && err is String ? err : null);
      }
      if (r['running'] != true && run == _run && run != 0) {
        final code = r['exitCode'];
        _exit(run, code is int ? code : null);
      }
    } catch (_) {
      // The service is between states; the next tick asks again.
    } finally {
      _polling = false;
    }
  }

  // --- CoreBackend --------------------------------------------------------------------------

  /// The service's state. The controller calls this once, on launch, and shows the returned
  /// lines itself, so they count as delivered: the pull will not hand them over a second time.
  @override
  Future<BackendStatus> status() => _snapshot(adopt: true);

  Future<BackendStatus> _snapshot({required bool adopt}) async {
    _attach();
    try {
      final r = await _method.invokeMapMethod<String, dynamic>('status');
      if (r == null) return const BackendStatus(running: false);
      final lines = (r['lines'] as List?)?.whereType<String>().toList() ?? const <String>[];
      final seq = _int(r['seq']);
      if (adopt && seq > _seq) _seq = seq;
      final run = _int(r['run']);
      final running = r['running'] == true;
      _vpnUp = r['vpn'] == true;
      if (running) _startPolling(run);
      return BackendStatus(
        running: running,
        run: run,
        lines: lines,
        vpnUp: _vpnUp,
      );
    } catch (_) {
      return const BackendStatus(running: false);
    }
  }

  @override
  Future<void> start(CoreSettings settings, int run) async {
    _attach();
    final String dir;
    try {
      dir = await _method.invokeMethod<String>('configDir') ?? '';
    } on PlatformException catch (e) {
      throw BackendException(e.message ?? e.code);
    } on MissingPluginException {
      throw BackendException('The Android service is not available in this build.');
    }
    final args = buildCoreArgs(settings, configPath: '$dir/oryvexcore.toml', android: true);
    _exited.remove(run);
    _vpnUp = false;
    _startPolling(run);
    try {
      await _method.invokeMethod('start', {
        'args': args,
        'vpn': settings.vpnMode,
        'protocol': settings.protocol,
        'socksPort': settings.socksPort,
        'fakeDns': settings.fakeDns,
        'ipv6': settings.vpnIpv6,
        'runId': run,
      });
    } on PlatformException catch (e) {
      _stopPolling();
      if (e.code == 'VPN_DENIED') {
        throw BackendException('VPN permission was not granted. Allow it, or turn off Whole-device VPN.');
      }
      throw BackendException(e.message ?? e.code);
    } on MissingPluginException {
      _stopPolling();
      throw BackendException('The Android service is not available in this build.');
    }
    // Asked after the VPN consent dialog, never on top of it: two system dialogs at once could
    // cancel the VPN consent on some phones.
    if (!_askedNotifications) {
      _askedNotifications = true;
      try {
        await _method.invokeMethod('requestNotifications');
      } catch (_) {}
    }
  }

  @override
  Future<void> stop() async {
    final st = await _snapshot(adopt: false);
    if (!st.running) return;
    final waiting = Completer<void>();
    _stopped = waiting;
    _stoppingRun = st.run;
    _startPolling(st.run);
    try {
      await _method.invokeMethod('stop');
    } catch (_) {}
    // The service kills a stubborn core after 3 s and gives up on it after 6 s.
    await waiting.future.timeout(const Duration(seconds: 8), onTimeout: () {});
    _stopped = null;
    _stoppingRun = 0;
  }

  /// On Android the service keeps running when the UI closes; that is the point of it.
  @override
  Future<void> shutdown() async {}

  /// Not part of [CoreBackend]: lets tests and hot restarts drop the native subscription.
  Future<void> detach() async {
    _stopPolling();
    await _native?.cancel();
    _native = null;
    _attached = false;
  }
}
