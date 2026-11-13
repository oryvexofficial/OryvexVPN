enum LogLevel { error, warn, info, debug, trace, plain }

/// What a line is about, from the core's own `[+]` / `[-]` / `[*]` / `[!]` / `[=]` markers.
enum LogKind { success, failure, progress, notice, stats, gui, other }

/// One line of core output. env_logger writes `[2026-10-29T18:00:00.123Z INFO  oryvexcore::x] msg`.
class LogLine {
  LogLine(this.time, this.level, this.message, {this.module = '', this.repeat = 1})
      : kind = _kindOf(message);

  final DateTime time;
  final LogLevel level;
  final String message;
  final String module;
  final LogKind kind;

  /// How many identical lines in a row this one stands for (the logs view folds repeats).
  int repeat;

  static final _envLogger = RegExp(
    r'^\[(\S+)\s+(ERROR|WARN|INFO|DEBUG|TRACE)\s*([^\]]*)\]\s?(.*)$',
  );
  static final _ansi = RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]');

  static LogLine parse(String raw) {
    final clean = raw.replaceAll(_ansi, '').replaceAll('\r', '').trimRight();
    final m = _envLogger.firstMatch(clean);
    if (m == null) {
      return LogLine(DateTime.now(), _guess(clean), clean);
    }
    final ts = DateTime.tryParse(m.group(1)!)?.toLocal() ?? DateTime.now();
    final level = switch (m.group(2)) {
      'ERROR' => LogLevel.error,
      'WARN' => LogLevel.warn,
      'INFO' => LogLevel.info,
      'DEBUG' => LogLevel.debug,
      _ => LogLevel.trace,
    };
    final module = (m.group(3) ?? '').trim().replaceFirst('oryvexcore::', '');
    return LogLine(ts, level, m.group(4) ?? '', module: module);
  }

  static LogLevel _guess(String line) {
    final lower = line.toLowerCase();
    if (line.startsWith('[-]') || lower.startsWith('error')) return LogLevel.error;
    if (line.startsWith('[!]') || lower.startsWith('warning')) return LogLevel.warn;
    return LogLevel.plain;
  }

  static LogKind _kindOf(String m) {
    if (m.startsWith('[+]')) return LogKind.success;
    if (m.startsWith('[-]')) return LogKind.failure;
    if (m.startsWith('[*]')) return LogKind.progress;
    if (m.startsWith('[!]')) return LogKind.notice;
    if (m.startsWith('[=]')) return LogKind.stats;
    if (m.startsWith('[gui]')) return LogKind.gui;
    return LogKind.other;
  }

  /// The message without its `[+]`-style marker, for display.
  String get text {
    if (message.length > 3 && message[0] == '[' && message[2] == ']') {
      return message.substring(3).trimLeft();
    }
    if (message.startsWith('[gui]')) return message.substring(5).trimLeft();
    return message;
  }

  bool get isNoise => level == LogLevel.debug || level == LogLevel.trace;

  bool get isProblem =>
      level == LogLevel.error || level == LogLevel.warn || kind == LogKind.failure;

  bool sameAs(LogLine o) => o.message == message && o.level == level;

  String get clock {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  String get levelTag => switch (level) {
        LogLevel.error => 'ERROR',
        LogLevel.warn => 'WARN',
        LogLevel.info => 'INFO',
        LogLevel.debug => 'DEBUG',
        LogLevel.trace => 'TRACE',
        LogLevel.plain => kind == LogKind.gui ? 'APP' : 'CORE',
      };

  @override
  String toString() {
    final times = repeat > 1 ? ' (x$repeat)' : '';
    return '$clock ${levelTag.padRight(5)} $message$times';
  }
}
