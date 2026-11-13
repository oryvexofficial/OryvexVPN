import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vexostream_app/api/release_update.dart';

void main() {
  group('ReleaseUpdateChecker', () {
    test('selects the Windows NSIS installer for a newer stable release',
        () async {
      final checker = ReleaseUpdateChecker(
        repository: 'sample/vexostream',
        currentVersion: '1.0.0+1',
        client: _clientWith([_release('v1.2.0')]),
      );

      final result = await checker.check(platform: ReleasePlatform.windows);

      expect(result.status, UpdateCheckStatus.updateAvailable);
      expect(result.latestVersion, '1.2.0');
      expect(
        result.release?.downloadUrl.toString(),
        'https://github.com/sample/vexostream/releases/download/v1.2.0/'
        'VexoStream-v1.2.0-Windows-Setup.exe',
      );
    });

    test('selects the universal APK on Android', () async {
      final checker = ReleaseUpdateChecker(
        repository: 'sample/vexostream',
        currentVersion: '1.0.0',
        client: _clientWith([_release('v1.1.0')]),
      );

      final result = await checker.check(platform: ReleasePlatform.android);

      expect(result.status, UpdateCheckStatus.updateAvailable);
      expect(
        result.release?.downloadUrl.pathSegments.last,
        'VexoStream-v1.1.0-Android-universal.apk',
      );
    });

    test('uses the highest stable semantic version and ignores previews',
        () async {
      final checker = ReleaseUpdateChecker(
        repository: 'sample/vexostream',
        currentVersion: '1.4.0',
        client: _clientWith([
          _release('v1.2.0'),
          _release('v9.0.0-beta.1', prerelease: true),
          _release('v1.4.0'),
        ]),
      );

      final result = await checker.check(platform: ReleasePlatform.windows);

      expect(result.status, UpdateCheckStatus.upToDate);
      expect(result.latestVersion, '1.4.0');
    });

    test('reports an unconfigured repository without claiming success',
        () async {
      final checker = ReleaseUpdateChecker(
        repository: '',
        currentVersion: '1.0.0',
        client: MockClient((_) async => http.Response('[]', 200)),
      );

      final result = await checker.check(platform: ReleasePlatform.android);

      expect(result.status, UpdateCheckStatus.notConfigured);
    });

    test('reports network failures instead of treating them as current',
        () async {
      final checker = ReleaseUpdateChecker(
        repository: 'sample/vexostream',
        currentVersion: '1.0.0',
        client: MockClient((_) async => throw Exception('network failure')),
      );

      final result = await checker.check(platform: ReleasePlatform.android);

      expect(result.status, UpdateCheckStatus.failed);
      expect(result.message, contains('not been verified'));
    });

    test('rejects an asset URL outside the configured GitHub repository',
        () async {
      final data = _release('v1.1.0');
      final assets = data['assets'] as List;
      for (final asset in assets) {
        (asset as Map<String, Object?>)['browser_download_url'] =
            'https://attacker.example/VexoStream.apk';
      }
      final checker = ReleaseUpdateChecker(
        repository: 'sample/vexostream',
        currentVersion: '1.0.0',
        client: _clientWith([data]),
      );

      final result = await checker.check(platform: ReleasePlatform.android);

      expect(result.status, UpdateCheckStatus.failed);
      expect(result.message, contains('could not be verified'));
    });
  });
}

MockClient _clientWith(List<Map<String, Object?>> releases) {
  return MockClient((request) async {
    expect(request.url.host, 'api.github.com');
    expect(request.url.path, '/repos/sample/vexostream/releases');
    return http.Response(jsonEncode(releases), 200);
  });
}

Map<String, Object?> _release(
  String tag, {
  bool prerelease = false,
  bool draft = false,
}) {
  final windowsName = 'VexoStream-$tag-Windows-Setup.exe';
  final androidName = 'VexoStream-$tag-Android-universal.apk';
  return {
    'tag_name': tag,
    'draft': draft,
    'prerelease': prerelease,
    'html_url': 'https://github.com/sample/vexostream/releases/tag/$tag',
    'assets': [
      {
        'name': windowsName,
        'browser_download_url':
            'https://github.com/sample/vexostream/releases/download/$tag/$windowsName',
      },
      {
        'name': androidName,
        'browser_download_url':
            'https://github.com/sample/vexostream/releases/download/$tag/$androidName',
      },
    ],
  };
}
