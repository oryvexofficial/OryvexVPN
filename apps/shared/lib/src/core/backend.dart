import 'settings.dart';

/// Something the running core (or its host) reports. [run] names the session it belongs to, so
/// late events from a session that was already stopped can be told apart and dropped.
sealed class BackendEvent {
  const BackendEvent(this.run);
  final int run;
}

class LineEvent extends BackendEvent {
  const LineEvent(super.run, this.line);
  final String line;
}

class ExitEvent extends BackendEvent {
  const ExitEvent(super.run, this.code);
  final int? code;
}

class VpnEvent extends BackendEvent {
  const VpnEvent(super.run, this.up, [this.error]);
  final bool up;
  final String? error;
}

class BackendStatus {
  const BackendStatus({
    required this.running,
    this.run = 0,
    this.lines = const [],
    this.vpnUp = false,
  });
  final bool running;
  final int run;
  final List<String> lines;
  final bool vpnUp;
}

class BackendException implements Exception {
  BackendException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where the core runs: a child process on desktop, a foreground VpnService on Android.
abstract class CoreBackend {
  Stream<BackendEvent> get events;

  bool get isAndroid;
  bool get supportsVpn;
  bool get supportsPsiphon;
  bool get supportsSystemProxy;
  String get platformLabel;

  Future<BackendStatus> status();

  /// Starts session [run]. Returns once the core process has been launched (not connected).
  Future<void> start(CoreSettings settings, int run);

  /// Stops whatever runs. Completes once the core is confirmed gone, or after a hard timeout.
  Future<void> stop();

  /// Called when the app is closing; must leave nothing running behind on desktop.
  Future<void> shutdown();
}
