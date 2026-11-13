import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.url,
    required this.title,
    required this.provider,
    required this.thumbnail,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final String url;
  final String title;
  final String provider;
  final String thumbnail;
  final int position;
  final int duration;
  final int updatedAt;

  double get progress => duration > 0
      ? (position / duration).clamp(0.0, 1.0).toDouble()
      : 0.0;

  bool get canResume =>
      position > 5 && (duration <= 0 || position < duration - 8);

  Map<String, dynamic> toVideo() => {
        'url': url,
        'title': title,
        'provider': provider,
        'thumbnail': thumbnail,
        'duration': duration,
        'resumeAt': position,
      };

  Map<String, Object> toJson() => {
        'url': url,
        'title': title,
        'provider': provider,
        'thumbnail': thumbnail,
        'position': position,
        'duration': duration,
        'updatedAt': updatedAt,
      };

  static WatchHistoryEntry? fromJson(String source) {
    try {
      final value = jsonDecode(source);
      if (value is! Map) return null;
      final url = (value['url'] ?? '').toString().trim();
      final parsed = Uri.tryParse(url);
      if (parsed == null ||
          (parsed.scheme != 'https' && parsed.scheme != 'http') ||
          parsed.host.isEmpty) {
        return null;
      }
      return WatchHistoryEntry(
        url: url,
        title: (value['title'] ?? 'Untitled video').toString(),
        provider: (value['provider'] ?? '').toString(),
        thumbnail: (value['thumbnail'] ?? '').toString(),
        position: _asNonNegativeInt(value['position']),
        duration: _asNonNegativeInt(value['duration']),
        updatedAt: _asNonNegativeInt(value['updatedAt']),
      );
    } catch (_) {
      return null;
    }
  }

  static int _asNonNegativeInt(dynamic value) {
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed == null || parsed < 0 ? 0 : parsed;
  }
}

/// Device-local history, intentionally separate from the website's browser
/// localStorage and from the user's account data.
class WatchHistoryStore {
  WatchHistoryStore._();

  static const _key = 'vexostream.watch-history.v1';
  static const _maxEntries = 40;

  static Future<List<WatchHistoryEntry>> list() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = prefs.getStringList(_key) ?? const [];
      return values
          .map(WatchHistoryEntry.fromJson)
          .whereType<WatchHistoryEntry>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(WatchHistoryEntry entry) async {
    if (entry.url.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = (prefs.getStringList(_key) ?? const [])
          .map(WatchHistoryEntry.fromJson)
          .whereType<WatchHistoryEntry>()
          .where((item) => item.url != entry.url)
          .toList();
      current.insert(0, entry);
      await prefs.setStringList(
        _key,
        current
            .take(_maxEntries)
            .map((item) => jsonEncode(item.toJson()))
            .toList(),
      );
    } catch (_) {
      // History is optional. Playback should never depend on local storage.
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
