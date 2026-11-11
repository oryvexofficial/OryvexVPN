import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// How a session ended.
enum SessionEnd { disconnected, dropped, appClosed }

/// One connected stretch: from "Connected" to the moment it ended.
class SessionRecord {
  SessionRecord({
    required this.start,
    required this.route,
    this.gateway,
    this.end,
    this.upBytes = 0,
    this.downBytes = 0,
    this.ended = SessionEnd.disconnected,
  });

  final DateTime start;

  /// "WireGuard", "Auto · MASQUE over HTTP/2", "Tor · fastest exit".
  final String route;
  final String? gateway;
  DateTime? end;
  double upBytes;
  double downBytes;
  SessionEnd ended;

  Duration get duration => (end ?? DateTime.now()).difference(start);

  Map<String, dynamic> toJson() => {
        'start': start.millisecondsSinceEpoch,
        'end': end?.millisecondsSinceEpoch,
        'route': route,
        'gateway': gateway,
        'up': upBytes,
        'down': downBytes,
        'ended': ended.name,
      };

  static SessionRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final start = raw['start'];
    final route = raw['route'];
    if (start is! int || route is! String) return null;
    final end = raw['end'];
    final gateway = raw['gateway'];
    double number(Object? v) => v is num && v >= 0 ? v.toDouble() : 0;
    return SessionRecord(
      start: DateTime.fromMillisecondsSinceEpoch(start),
      end: end is int ? DateTime.fromMillisecondsSinceEpoch(end) : null,
      route: route,
      gateway: gateway is String ? gateway : null,
      upBytes: number(raw['up']),
      downBytes: number(raw['down']),
      ended: SessionEnd.values.firstWhere((e) => e.name == raw['ended'], orElse: () => SessionEnd.disconnected),
    );
  }
}

/// Past sessions and lifetime totals, kept on the device only.
class SessionHistory {
  SessionHistory();

  static const _key = 'oryvexcore.history.v1';
  static const maxRecords = 60;

  final List<SessionRecord> records = <SessionRecord>[];
  int sessions = 0;
  double totalUp = 0;
  double totalDown = 0;
  int totalSeconds = 0;

  /// Adds a finished session, newest first, and folds it into the totals.
  void add(SessionRecord r) {
    records.insert(0, r);
    if (records.length > maxRecords) records.removeRange(maxRecords, records.length);
    sessions++;
    totalUp += r.upBytes;
    totalDown += r.downBytes;
    totalSeconds += r.duration.inSeconds;
  }

  void clear() {
    records.clear();
    sessions = 0;
    totalUp = 0;
    totalDown = 0;
    totalSeconds = 0;
  }

  String encode() => jsonEncode({
        'sessions': sessions,
        'up': totalUp,
        'down': totalDown,
        'seconds': totalSeconds,
        'records': [for (final r in records) r.toJson()],
      });

  static SessionHistory decode(String raw) {
    final h = SessionHistory();
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return h;
      final list = j['records'];
      if (list is List) {
        for (final e in list) {
          final r = SessionRecord.fromJson(e);
          if (r != null && h.records.length < maxRecords) h.records.add(r);
        }
      }
      double number(Object? v) => v is num && v >= 0 ? v.toDouble() : 0;
      h.sessions = number(j['sessions']).toInt();
      h.totalUp = number(j['up']);
      h.totalDown = number(j['down']);
      h.totalSeconds = number(j['seconds']).toInt();
      if (h.sessions < h.records.length) h.sessions = h.records.length;
    } catch (_) {
      // A broken store starts a fresh history.
    }
    return h;
  }

  static Future<SessionHistory> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) return decode(raw);
    } catch (_) {}
    return SessionHistory();
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, encode());
    } catch (_) {}
  }
}

/// "1.4 GB", "820 KB", "0 B".
String formatBytes(double bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes < 0 ? 0.0 : bytes;
  var u = 0;
  while (v >= 1000 && u < units.length - 1) {
    v /= 1024;
    u++;
  }
  final text = u == 0 || v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '$text ${units[u]}';
}

/// "2 h 14 min", "6 min", "40 s".
String formatSpan(Duration d) {
  if (d.inDays > 0) return '${d.inDays} d ${d.inHours % 24} h';
  if (d.inHours > 0) return '${d.inHours} h ${d.inMinutes % 60} min';
  if (d.inMinutes > 0) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}
