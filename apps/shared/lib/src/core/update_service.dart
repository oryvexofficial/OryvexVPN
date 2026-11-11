import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'controller.dart';
import 'https_client.dart';
import 'platform_links.dart';
import 'version.dart';

enum UpdateStatus { idle, checking, upToDate, available, failed }

class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, required this.size});

  final String name;
  final String url;
  final int size;

  Map<String, dynamic> toJson() => {'name': name, 'url': url, 'size': size};

  static ReleaseAsset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final url = raw['url'] ?? raw['browser_download_url'];
    final size = raw['size'];
    if (name is! String || url is! String || !url.startsWith('https://')) return null;
    return ReleaseAsset(name: name, url: url, size: size is int ? size : 0);
  }
}

/// The newest published release, as GitHub describes it.
class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.title,
    required this.notes,
    required this.pageUrl,
    required this.published,
    required this.assets,
  });

  /// "1.2.0", without the tag's leading v.
  final String version;
  final String title;
  final String notes;
  final String pageUrl;
  final DateTime? published;
  final List<ReleaseAsset> assets;

  Map<String, dynamic> toJson() => {
        'version': version,
        'title': title,
        'notes': notes,
        'pageUrl': pageUrl,
        'published': published?.millisecondsSinceEpoch,
        'assets': [for (final a in assets) a.toJson()],
      };

  static ReleaseInfo? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final version = raw['version'];
    final pageUrl = raw['pageUrl'];
    if (version is! String || version.isEmpty || pageUrl is! String) return null;
    final published = raw['published'];
    final assets = raw['assets'];
    return ReleaseInfo(
      version: version,
      title: raw['title'] is String ? raw['title'] as String : 'OryvexVPN $version',
      notes: raw['notes'] is String ? raw['notes'] as String : '',
      pageUrl: pageUrl,
      published: published is int ? DateTime.fromMillisecondsSinceEpoch(published) : null,
      assets: [
        if (assets is List)
          for (final a in assets)
            if (ReleaseAsset.fromJson(a) case final asset?) asset,
      ],
    );
  }

  /// Reads GitHub's `/releases/latest` answer. Null for drafts, pre-releases or a broken body.
  static ReleaseInfo? fromGitHub(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map) return null;
      if (j['draft'] == true || j['prerelease'] == true) return null;
      final tag = j['tag_name'];
      if (tag is! String) return null;
      final version = tag.trim().replaceFirst(RegExp(r'^[vV]'), '');
      if (!RegExp(r'^\d+(\.\d+){0,3}$').hasMatch(version)) return null;
      final name = j['name'];
      final notes = j['body'];
      final page = j['html_url'];
      final published = j['published_at'];
      final assets = j['assets'];
      return ReleaseInfo(
        version: version,
        title: name is String && name.trim().isNotEmpty ? name.trim() : 'OryvexVPN $version',
        notes: notes is String ? notes.trim() : '',
        pageUrl: page is String && page.startsWith('https://') ? page : 'https://github.com/$kReleasesRepo/releases',
        published: published is String ? DateTime.tryParse(published)?.toLocal() : null,
        assets: [
          if (assets is List)
            for (final a in assets)
              if (ReleaseAsset.fromJson(a) case final asset?)
                if (!asset.name.endsWith('.sha256') && asset.name != 'SHA256SUMS.txt') asset,
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// Whether dotted version [latest] is newer than [current]: 1.2.10 beats 1.2.9, and "+build" or
/// "-suffix" parts are ignored.
bool isNewerVersion(String latest, String current) {
  List<int> parts(String v) => v
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[-+ ]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final a = parts(latest);
  final b = parts(current);
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// The download that fits this device best, from a release's files.
ReleaseAsset? pickAsset(List<ReleaseAsset> assets, {required String platform, List<String> abis = const []}) {
  ReleaseAsset? first(bool Function(String n) test) {
    for (final a in assets) {
      if (test(a.name.toLowerCase())) return a;
    }
    return null;
  }

  switch (platform) {
    case 'android':
      for (final abi in abis) {
        final hit = first((n) => n.endsWith('.apk') && n.contains(abi.toLowerCase()));
        if (hit != null) return hit;
      }
      return first((n) => n.endsWith('.apk') && n.contains('universal')) ?? first((n) => n.endsWith('.apk'));
    case 'windows':
      return first((n) => n.endsWith('.exe') && n.contains('setup')) ??
          first((n) => n.contains('windows-x64') && n.endsWith('.zip') && !n.contains('legacy'));
    default:
      return null;
  }
}

/// Looks for a newer release on launch and every few hours, and remembers what it found, so the
/// Updates badge shows at once on the next start, even offline.
///
/// While the tunnel is up the check rides the core's SOCKS5 port: GitHub is often blocked on
/// exactly the networks OryvexVPN is for, and the app's own traffic does not use the VPN.
class UpdateService extends ChangeNotifier {
  UpdateService(this.controller);

  final CoreController controller;

  static const interval = Duration(hours: 6);
  static const _cacheKey = 'oryvexcore.updates.v1';

  UpdateStatus status = UpdateStatus.idle;
  ReleaseInfo? latest;
  DateTime? checkedAt;
  String? error;

  /// The last check went through the tunnel.
  bool checkedViaTunnel = false;

  List<String> _abis = const [];
  Timer? _timer;
  Timer? _firstCheck;
  CoreState? _lastState;
  bool _disposed = false;

  String get currentVersion => kAppVersion;

  bool get updateAvailable => latest != null && isNewerVersion(latest!.version, currentVersion);

  bool get isSkipped => latest != null && controller.settings.skippedVersion == latest!.version;

  /// A newer release the user has not skipped: drives the badge and the Connect banner.
  bool get shouldNotify => updateAvailable && !isSkipped;

  String get platform => Platform.isAndroid ? 'android' : (Platform.isWindows ? 'windows' : Platform.operatingSystem);

  /// The file to download for this device, when the release has one.
  ReleaseAsset? get bestAsset {
    final r = latest;
    if (r == null) return null;
    return pickAsset(r.assets, platform: platform, abis: _abis);
  }

  Future<void> init() async {
    await _loadCache();
    _abis = await androidAbis();
    _lastState = controller.state;
    controller.addListener(_onController);
    _armTimer();
    if (controller.settings.checkUpdates) {
      // Let the first frames and the offline check settle before going out.
      _firstCheck = Timer(const Duration(seconds: 5), () => unawaited(check()));
    }
    _notify();
  }

  void _armTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 30), (_) {
      if (!controller.settings.checkUpdates) return;
      final at = checkedAt;
      if (at == null || DateTime.now().difference(at) >= interval) unawaited(check());
    });
  }

  void _onController() {
    final now = controller.state;
    if (now == _lastState) return;
    _lastState = now;
    // A check that failed on the open network gets another go once the tunnel is up.
    if (now == CoreState.connected && controller.settings.checkUpdates && status == UpdateStatus.failed) {
      unawaited(check());
    }
  }

  Future<void> check() async {
    if (_disposed || status == UpdateStatus.checking) return;
    status = UpdateStatus.checking;
    error = null;
    _notify();

    final viaTunnel = controller.state == CoreState.connected;
    ReleaseInfo? found;
    String? problem;
    try {
      final reply = await HttpsGet.fetch(
        'api.github.com',
        '/repos/$kReleasesRepo/releases/latest',
        socksPort: viaTunnel ? controller.settings.socksPort : null,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'OryvexVPN-update-check',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      );
      if (reply.statusCode == 404) {
        problem = 'No release has been published yet.';
      } else if (reply.statusCode == 403 || reply.statusCode == 429) {
        problem = 'GitHub asked to slow down. Try again in a while.';
      } else if (!reply.ok) {
        problem = 'GitHub answered ${reply.statusCode}.';
      } else {
        found = ReleaseInfo.fromGitHub(reply.body);
        if (found == null) problem = 'The release information could not be read.';
      }
    } on TimeoutException {
      problem = viaTunnel ? 'GitHub did not answer through the tunnel.' : 'GitHub did not answer. Connect and try again.';
    } on Object {
      problem = viaTunnel ? 'Could not reach GitHub through the tunnel.' : 'Could not reach GitHub. Connect and try again.';
    }
    if (_disposed) return;

    checkedViaTunnel = viaTunnel;
    if (found != null) {
      latest = found;
      checkedAt = DateTime.now();
      status = updateAvailable ? UpdateStatus.available : UpdateStatus.upToDate;
      unawaited(_saveCache());
    } else {
      error = problem;
      // A cached newer release still counts: keep saying so instead of hiding it on a failure.
      status = updateAvailable ? UpdateStatus.available : UpdateStatus.failed;
    }
    _notify();
  }

  Future<void> skipLatest() async {
    final r = latest;
    if (r == null) return;
    await controller.updateSettings((s) => s.skippedVersion = r.version);
    _notify();
  }

  Future<void> unskip() async {
    await controller.updateSettings((s) => s.skippedVersion = '');
    _notify();
  }

  Future<void> setAutoCheck(bool on) async {
    await controller.updateSettings((s) => s.checkUpdates = on);
    if (on && checkedAt == null) unawaited(check());
    _notify();
  }

  Future<bool> openDownload() => openExternal(bestAsset?.url ?? latest?.pageUrl ?? 'https://github.com/$kReleasesRepo/releases/latest');

  Future<bool> openReleasePage() => openExternal(latest?.pageUrl ?? 'https://github.com/$kReleasesRepo/releases/latest');

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      latest = ReleaseInfo.fromJson(j['release']);
      final at = j['checkedAt'];
      checkedAt = at is int ? DateTime.fromMillisecondsSinceEpoch(at) : null;
      if (latest != null) status = updateAvailable ? UpdateStatus.available : UpdateStatus.upToDate;
    } catch (_) {}
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, jsonEncode({
        'checkedAt': checkedAt?.millisecondsSinceEpoch,
        'release': latest?.toJson(),
      }));
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _firstCheck?.cancel();
    controller.removeListener(_onController);
    super.dispose();
  }
}
