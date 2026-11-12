import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'country_names.dart';
import 'flag_codes.dart';

export 'flag_codes.dart';

/// One exit relay in a country: the strongest few per country travel with the directory, so
/// the app can show what "best exit node" will choose between.
class TorExitRelay {
  const TorExitRelay({required this.nickname, this.fingerprint = '', this.bandwidth = 0});

  final String nickname;

  /// Upper-case hex, 40 characters, or "" when the directory did not carry it.
  final String fingerprint;

  /// Advertised bandwidth in bytes per second.
  final int bandwidth;

  /// "ABCD 1234 …" for display: the first eight hex digits in two groups.
  String get shortFingerprint {
    if (fingerprint.length < 8) return fingerprint;
    return '${fingerprint.substring(0, 4)} ${fingerprint.substring(4, 8)}';
  }

  static TorExitRelay? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final nick = raw['nick'] ?? raw['nickname'];
    if (nick is! String || nick.trim().isEmpty) return null;
    final fp = raw['fp'] ?? raw['fingerprint'];
    final bw = raw['bw'] ?? raw['bandwidth'];
    return TorExitRelay(
      nickname: nick.trim(),
      fingerprint: fp is String ? fp.trim().toUpperCase() : '',
      bandwidth: bw is num ? bw.toInt() : 0,
    );
  }

  Map<String, dynamic> toJson() => {'nick': nickname, 'fp': fingerprint, 'bw': bandwidth};
}

/// One country Tor can leave from, as the core's exit directory lists it.
class TorExitCountry {
  const TorExitCountry({
    required this.code,
    required this.name,
    this.relays = 0,
    this.bandwidth = 0,
    this.probability = 0,
    this.top = const <TorExitRelay>[],
  });

  /// Lowercase ISO 3166-1 alpha-2.
  final String code;
  final String name;

  /// Running exit relays there (0 when unknown, for the bundled list).
  final int relays;

  /// Their advertised bandwidth together, in bytes per second.
  final int bandwidth;

  /// The share of exit traffic Tor would send there by itself, 0..1.
  final double probability;

  /// Its strongest exit relays, best first (empty for the bundled list).
  final List<TorExitRelay> top;

  String get flag => flagOf(code);

  /// The flag picture inside the package, or null when none ships for this code.
  String? get flagImage => hasFlagAsset(code) ? flagAsset(code) : null;

  /// "412 exits · 18.4 Gbit/s", or "" when the bundled list has no numbers.
  String get detail {
    if (relays <= 0) return '';
    final rate = bandwidth > 0 ? ' · ${formatBandwidth(bandwidth)}' : '';
    return '$relays exit${relays == 1 ? '' : 's'}$rate';
  }

  static TorExitCountry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final cc = raw['cc'];
    if (cc is! String || !isCountryCode(cc.toLowerCase())) return null;
    final code = cc.toLowerCase();
    final name = raw['name'];
    int number(Object? v) => v is num ? v.toInt() : 0;
    final p = raw['probability'];
    final rawTop = raw['top'];
    final top = <TorExitRelay>[];
    if (rawTop is List) {
      for (final r in rawTop) {
        final relay = TorExitRelay.fromJson(r);
        if (relay != null) top.add(relay);
      }
    }
    return TorExitCountry(
      code: code,
      name: name is String && name.trim().isNotEmpty ? name.trim() : countryName(code),
      relays: number(raw['relays']),
      bandwidth: number(raw['bandwidth']),
      probability: p is num ? p.toDouble() : 0,
      top: top,
    );
  }

  Map<String, dynamic> toJson() => {
        'cc': code,
        'name': name,
        'relays': relays,
        'bandwidth': bandwidth,
        'probability': probability,
        'top': [for (final r in top) r.toJson()],
      };
}

bool isCountryCode(String s) => RegExp(r'^[a-z]{2}$').hasMatch(s);

/// The regional-indicator flag for a two-letter code, or "" when it is not one.
String flagOf(String code) {
  final cc = code.toUpperCase();
  if (cc.length != 2) return '';
  final a = cc.codeUnitAt(0), b = cc.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return '';
  return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
}

/// Bytes per second, as people read link speeds: "940 Mbit/s", "18.4 Gbit/s".
String formatBandwidth(int bytesPerSecond) {
  final bits = bytesPerSecond * 8.0;
  if (bits >= 1e9) return '${(bits / 1e9).toStringAsFixed(1)} Gbit/s';
  if (bits >= 1e6) return '${(bits / 1e6).toStringAsFixed(0)} Mbit/s';
  return '${(bits / 1e3).toStringAsFixed(0)} kbit/s';
}

/// Every country Tor can leave from, best served first.
///
/// The core fetches it from Onionoo *through Tor* (torproject.org is filtered on many networks,
/// so it is never asked over the plain connection), prints it as one `[=] tor-exits {...}` line,
/// and the app keeps the last one it saw. Before that, a bundled list of long-standing exit
/// countries stands in.
class TorExitDirectory {
  const TorExitDirectory({required this.updated, required this.source, required this.countries});

  /// When the core fetched it; null for the bundled list.
  final DateTime? updated;

  /// `onionoo` or `bundled`.
  final String source;
  final List<TorExitCountry> countries;

  static const _cacheKey = 'oryvexcore.tor.exits.v1';
  static const _marker = '[=] tor-exits ';

  bool get isBundled => source == 'bundled';

  int get totalRelays => countries.fold(0, (sum, c) => sum + c.relays);

  TorExitCountry? find(String code) {
    for (final c in countries) {
      if (c.code == code) return c;
    }
    return null;
  }

  String nameOf(String code) => find(code)?.name ?? countryName(code);

  factory TorExitDirectory.bundled() => TorExitDirectory(
        updated: null,
        source: 'bundled',
        countries: [
          for (final cc in bundledTorExitCodes) TorExitCountry(code: cc, name: countryName(cc)),
        ],
      );

  static TorExitDirectory? decode(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final list = j['countries'];
      if (list is! List) return null;
      final countries = <TorExitCountry>[];
      final seen = <String>{};
      for (final e in list) {
        final c = TorExitCountry.fromJson(e);
        if (c != null && seen.add(c.code)) countries.add(c);
      }
      if (countries.isEmpty) return null;
      final at = j['updated'];
      final source = j['source'];
      return TorExitDirectory(
        updated: at is num && at > 0 ? DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000) : null,
        source: source is String && source.isNotEmpty ? source : 'onionoo',
        countries: countries,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
        'updated': updated == null ? 0 : updated!.millisecondsSinceEpoch ~/ 1000,
        'source': source,
        'countries': [for (final c in countries) c.toJson()],
      });

  /// The directory a core log message carries, or null when it carries none.
  static TorExitDirectory? fromLogLine(String message) {
    final at = message.indexOf(_marker);
    if (at < 0) return null;
    return decode(message.substring(at + _marker.length).trim());
  }

  static final _using = RegExp(r'tor exit: using (auto|[a-z]{2})\b(?:.*?(\d+) ms)?', caseSensitive: false);

  /// The exit the core settled on, from its "tor exit: using de (Germany), ... 842 ms" line:
  /// the code ('auto' or lowercase ISO) and the milliseconds it took, when measured.
  static (String, int?)? exitInUse(String message) {
    final m = _using.firstMatch(message);
    if (m == null) return null;
    return (m.group(1)!.toLowerCase(), int.tryParse(m.group(2) ?? ''));
  }

  static Future<TorExitDirectory> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        final d = decode(raw);
        if (d != null) return d;
      }
    } catch (_) {
      // A broken store falls back on the bundled list.
    }
    return TorExitDirectory.bundled();
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, encode());
    } catch (_) {}
  }
}

/// Every country that has hosted Tor exit relays in recent years, best served first, so the
/// picker is complete before the live directory arrives. Same order as the core's bundled list
/// (oryvexcore/src/tor_exits.rs). The live list replaces it after the first Tor connect.
const bundledTorExitCodes = <String>[
  'de', 'nl', 'us', 'fr', 'se', 'ch', 'fi', 'ro', 'at', 'lu', 'no', 'gb', 'ca', 'pl', 'cz', 'is',
  'md', 'bg', 'dk', 'es', 'it', 'lt', 'lv', 'ee', 'ua', 'hu', 'sg', 'jp', 'hk', 'au', 'br', 'in',
  'za', 'tr', 'rs', 'tw', 'vn', 'pe', 'az', 'be', 'ie', 'pt', 'gr', 'sk', 'si', 'hr', 'il', 'kr',
  'nz', 'ar', 'cl', 'mx', 'cr', 'pa', 'ru', 'kz', 'th', 'my', 'id', 'ph', 'ae', 'cy', 'mt', 'li',
  'sc', 'bz', 'gi', 'ge', 'am', 'al', 'mk', 'ba', 'ec', 'co', 'uy', 'by',
];
