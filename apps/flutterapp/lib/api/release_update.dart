import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum ReleasePlatform { windows, android, other }

enum UpdateCheckStatus { upToDate, updateAvailable, notConfigured, failed }

class AppRelease {
  const AppRelease({
    required this.version,
    required this.tag,
    required this.downloadUrl,
    required this.releaseUrl,
  });

  final String version;
  final String tag;
  final Uri downloadUrl;
  final Uri releaseUrl;
}

class UpdateCheckResult {
  const UpdateCheckResult._({
    required this.status,
    this.latestVersion,
    this.release,
    this.message,
  });

  const UpdateCheckResult.upToDate({String? latestVersion})
      : this._(status: UpdateCheckStatus.upToDate, latestVersion: latestVersion);

  UpdateCheckResult.updateAvailable(AppRelease release)
      : this._(
          status: UpdateCheckStatus.updateAvailable,
          latestVersion: release.version,
          release: release,
        );

  const UpdateCheckResult.notConfigured(String message)
      : this._(status: UpdateCheckStatus.notConfigured, message: message);

  const UpdateCheckResult.failed(String message)
      : this._(status: UpdateCheckStatus.failed, message: message);

  final UpdateCheckStatus status;
  final String? latestVersion;
  final AppRelease? release;
  final String? message;
}

/// Reads stable releases only. The repository value is supplied at build time
/// by CI from GITHUB_REPOSITORY, never from a remote configuration response.
class ReleaseUpdateChecker {
  ReleaseUpdateChecker({
    http.Client? client,
    String? repository,
    String? currentVersion,
  })  : _client = client ?? http.Client(),
        repository = repository ?? configuredRepository,
        currentVersion = currentVersion ?? appVersion;

  static const configuredRepository =
      String.fromEnvironment('VEXOSTREAM_GITHUB_REPOSITORY');
  static const appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.2');

  final http.Client _client;
  final String repository;
  final String currentVersion;

  bool get isConfigured => _repositoryParts(repository) != null;

  Future<UpdateCheckResult> check({
    required ReleasePlatform platform,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final parts = _repositoryParts(repository);
    if (parts == null) {
      return const UpdateCheckResult.notConfigured(
        'This build has no GitHub release repository configured.',
      );
    }
    final installed = _SemanticVersion.tryParse(currentVersion);
    if (installed == null) {
      return const UpdateCheckResult.failed(
        'This build has an invalid version setting. Updates could not be checked.',
      );
    }

    try {
      final endpoint = Uri.https(
        'api.github.com',
        '/repos/${parts.$1}/${parts.$2}/releases',
        {'per_page': '100'},
      );
      final response = await _client.get(
        endpoint,
        headers: const {
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'User-Agent': 'VexoStream',
        },
      ).timeout(timeout);
      if (response.statusCode != 200) {
        return UpdateCheckResult.failed(
          'GitHub returned HTTP ${response.statusCode}. Your installed version has not been verified.',
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return const UpdateCheckResult.failed(
          'GitHub returned an unreadable release list. Your installed version has not been verified.',
        );
      }

      final stableReleases = <_ReleaseRecord>[];
      for (final item in decoded) {
        if (item is! Map || item['draft'] == true || item['prerelease'] == true) {
          continue;
        }
        final tag = (item['tag_name'] ?? '').toString();
        final version = _SemanticVersion.tryParse(tag);
        if (version == null || version.isPrerelease) continue;
        stableReleases.add(_ReleaseRecord(
          tag: tag,
          version: version,
          assets: item['assets'] is List ? item['assets'] as List : const [],
          htmlUrl: (item['html_url'] ?? '').toString(),
        ));
      }
      if (stableReleases.isEmpty) {
        return const UpdateCheckResult.failed(
          'No stable GitHub release is available yet. Your installed version has not been verified.',
        );
      }
      stableReleases.sort((a, b) => b.version.compareTo(a.version));
      final latest = stableReleases.first;
      if (latest.version.compareTo(installed) <= 0) {
        return UpdateCheckResult.upToDate(latestVersion: latest.version.toString());
      }

      final assetName = _assetName(latest.tag, platform);
      if (assetName == null) {
        return const UpdateCheckResult.failed(
          'A newer release exists, but this platform does not have a supported download.',
        );
      }
      final asset = latest.assets.whereType<Map>().firstWhere(
            (item) => (item['name'] ?? '').toString() == assetName,
            orElse: () => const {},
          );
      final downloadUrl = _safeAssetUrl(
        (asset['browser_download_url'] ?? '').toString(),
        parts,
        latest.tag,
        assetName,
      );
      final releaseUrl = _safeReleaseUrl(latest.htmlUrl, parts, latest.tag);
      if (downloadUrl == null || releaseUrl == null) {
        return const UpdateCheckResult.failed(
          'A newer release was found, but its download link could not be verified.',
        );
      }

      return UpdateCheckResult.updateAvailable(AppRelease(
        version: latest.version.toString(),
        tag: latest.tag,
        downloadUrl: downloadUrl,
        releaseUrl: releaseUrl,
      ));
    } on TimeoutException {
      return const UpdateCheckResult.failed(
        'GitHub did not respond in time. Your installed version has not been verified.',
      );
    } on FormatException {
      return const UpdateCheckResult.failed(
        'GitHub returned invalid release data. Your installed version has not been verified.',
      );
    } catch (_) {
      return const UpdateCheckResult.failed(
        'Could not reach GitHub. Your installed version has not been verified.',
      );
    }
  }

  void close() => _client.close();

  static String? _assetName(String tag, ReleasePlatform platform) {
    final version = tag;
    return switch (platform) {
      ReleasePlatform.windows => 'VexoStream-$version-Windows-Setup.exe',
      ReleasePlatform.android => 'VexoStream-$version-Android-universal.apk',
      ReleasePlatform.other => null,
    };
  }

  static Uri? _safeAssetUrl(
    String raw,
    (String, String) repository,
    String tag,
    String name,
  ) {
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final expectedPath =
        '/${repository.$1}/${repository.$2}/releases/download/$tag/$name';
    return uri.path == expectedPath ? uri : null;
  }

  static Uri? _safeReleaseUrl(
    String raw,
    (String, String) repository,
    String tag,
  ) {
    final uri = Uri.tryParse(raw);
    final expectedPath =
        '/${repository.$1}/${repository.$2}/releases/tag/$tag';
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != expectedPath) {
      return null;
    }
    return uri;
  }

  static (String, String)? _repositoryParts(String value) {
    final match = RegExp(r'^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$')
        .firstMatch(value.trim());
    if (match == null) return null;
    return (match.group(1)!, match.group(2)!);
  }
}

class _ReleaseRecord {
  const _ReleaseRecord({
    required this.tag,
    required this.version,
    required this.assets,
    required this.htmlUrl,
  });

  final String tag;
  final _SemanticVersion version;
  final List assets;
  final String htmlUrl;
}

class _SemanticVersion implements Comparable<_SemanticVersion> {
  const _SemanticVersion(
    this.major,
    this.minor,
    this.patch,
    this.prerelease,
  );

  final int major;
  final int minor;
  final int patch;
  final String? prerelease;

  bool get isPrerelease => prerelease != null;

  static _SemanticVersion? tryParse(String source) {
    final match = RegExp(
      r'^[vV]?(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?(?:\+[0-9A-Za-z.-]+)?$',
    ).firstMatch(source.trim());
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3)!);
    if (major == null || minor == null || patch == null) return null;
    return _SemanticVersion(
      major,
      minor,
      patch,
      match.group(4),
    );
  }

  @override
  int compareTo(_SemanticVersion other) {
    final majorOrder = major.compareTo(other.major);
    if (majorOrder != 0) return majorOrder;
    final minorOrder = minor.compareTo(other.minor);
    if (minorOrder != 0) return minorOrder;
    final patchOrder = patch.compareTo(other.patch);
    if (patchOrder != 0) return patchOrder;
    if (prerelease == null && other.prerelease == null) return 0;
    if (prerelease == null) return 1;
    if (other.prerelease == null) return -1;

    final left = prerelease!.split('.');
    final right = other.prerelease!.split('.');
    for (var i = 0; i < left.length && i < right.length; i++) {
      final a = left[i];
      final b = right[i];
      final aNumber = int.tryParse(a);
      final bNumber = int.tryParse(b);
      final order = aNumber != null && bNumber != null
          ? aNumber.compareTo(bNumber)
          : aNumber != null
              ? -1
              : bNumber != null
                  ? 1
                  : a.compareTo(b);
      if (order != 0) return order;
    }
    return left.length.compareTo(right.length);
  }

  @override
  String toString() => '$major.$minor.$patch${prerelease == null ? '' : '-$prerelease'}';
}
