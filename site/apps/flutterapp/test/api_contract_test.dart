import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vexostream_app/api/vexo_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('JSON helpers accept maps and lists', () {
    expect(asMap({'title': 'Demo'})['title'], 'Demo');
    expect(asMap(null), isEmpty);
    expect(asList([1, 2]), [1, 2]);
    expect(asList(null), isEmpty);
  });

  test('app uses the admin-saved default search and has a safe fallback', () {
    expect(defaultSearchQuery({'defaultQuery': 'Brazzers'}), 'Brazzers');
    expect(defaultSearchQuery({'defaultQuery': '  '}), 'trending');
    expect(defaultSearchQuery(null), 'trending');
  });

  test('catalogue normalizes thumbnail aliases and allows poster enrichment', () {
    final items = videoItems([
      {'url': 'https://www.xvideos.com/video1', 'thumbnail_url': 'https://img.example.test/a.jpg'},
      {'url': 'https://www.xvideos.com/video2', 'images': [{'url': 'https://img.example.test/b.jpg'}]},
      {'url': 'https://www.xvideos.com/video3'},
      {'url': 'https://www.xvideos.com/video4', 'thumbnail': 'https://img.example.test/blank.gif'},
      {'url': '', 'thumbnail': 'https://img.example.test/c.jpg'},
    ]);
    expect(items.length, 3);
    expect(videoThumbnail(items[0]), 'https://img.example.test/a.jpg');
    expect(items[1]['thumbnail'], 'https://img.example.test/b.jpg');
  });

  test('durations render like the site', () {
    expect(formatDuration(75), '1:15');
    expect(formatDuration('3725'), '1:02:05');
    expect(formatDuration('12:30'), '12:30');
  });

  test('expired stream sessions are refreshed before trying other qualities', () {
    expect(isExpiredMediaFailure('Invalid or expired media token.'), isTrue);
    expect(isExpiredMediaFailure('Upstream refused the stream (403)'), isTrue);
    expect(isExpiredMediaFailure('The stream session expired.'), isTrue);
    expect(isExpiredMediaFailure('SocketException: connection refused'), isFalse);
  });

  test('signed HLS URLs use the Worker media proxy', () {
    final original = Uri.encodeComponent('https://cdn.example.test/playlist.m3u8?key=abc');
    final encoded = base64.encode(utf8.encode(original));
    final uri = VexoApi().streamUri({'x_url': encoded, 'x_sig': 'signed', 'x_exp': '123'});
    expect(uri.host, 'vexostream.bond');
    expect(uri.path, '/proxy-m3u8.m3u8');
    expect(uri.queryParameters['url'], 'https://cdn.example.test/playlist.m3u8?key=abc');
    expect(uri.queryParameters['sig'], 'signed');
  });

  test('extensionless HLS URLs use the playlist proxy when metadata says HLS', () {
    const cdn = 'https://cdn.example.test/live?id=abc123';
    final encoded = base64.encode(utf8.encode(Uri.encodeComponent(cdn)));
    final api = VexoApi();
    final proxy = api.streamUri({
      'x_url': encoded,
      'x_sig': 'worker-signature',
      'x_exp': '1794551833',
      'type': 'hls',
    });
    expect(proxy.path, '/proxy-m3u8.m3u8');
    expect(proxy.queryParameters['url'], cdn);
    api.close();
  });

  test('HLS URLs hinted in query parameters use the playlist proxy', () {
    const cdn = 'https://cdn.example.test/live?format=m3u8&token=abc';
    final encoded = base64.encode(utf8.encode(Uri.encodeComponent(cdn)));
    final api = VexoApi();
    final proxy = api.streamUri({'x_url': encoded, 'x_sig': 'worker-signature', 'x_exp': '1794551833'});
    expect(proxy.path, '/proxy-m3u8.m3u8');
    expect(proxy.queryParameters['url'], cdn);
    api.close();
  });

  test('signed HLS proxy keeps nested CDN query parameters intact', () {
    const cdn = 'https://cdn.example.test/hls/master.m3u8?token=a%2Bb%3D&exp=9999999999&sig=abc123';
    final encoded = base64.encode(utf8.encode(Uri.encodeComponent(cdn)));
    final api = VexoApi();
    final proxy = api.streamUri({'x_url': encoded, 'x_sig': 'worker-signature', 'x_exp': '1794551833'});
    expect(proxy.path, '/proxy-m3u8.m3u8');
    expect(proxy.queryParameters['url'], cdn);
    expect(proxy.queryParameters['sig'], 'worker-signature');
    expect(proxy.queryParameters['exp'], '1794551833');
    api.close();
  });

  test('images go through the Worker image proxy and attach APP_KEY', () {
    final api = VexoApi();
    final url = Uri.parse(api.imageUrl('//img.example.test/a.jpg'));
    expect(url.path, '/api/v1/image');
    expect(url.queryParameters['url'], 'https://img.example.test/a.jpg');
    expect(api.imageUrl('/relative/thumb.jpg'), isEmpty);
    expect(api.imageHeaders['X-App-Key'], VexoApi.appKey);
    expect(api.imageHeaders['Accept'], isNot(contains('avif')));
    expect(api.mediaHeaders.containsKey('X-App-Key'), isFalse);
    api.close();
  });

  test('extensionless direct streams get a native-friendly video suffix', () {
    const cdn = 'https://cdn.example.test/play?id=abc123';
    final encoded = base64.encode(utf8.encode(Uri.encodeComponent(cdn)));
    final api = VexoApi();
    final proxy = api.streamUri({
      'x_url': encoded,
      'x_sig': 'worker-signature',
      'x_exp': '1794551833',
      'type': 'mp4',
    });
    expect(proxy.path, '/proxy-video.mp4');
    expect(proxy.queryParameters['url'], cdn);
    api.close();
  });

  test('API requests attach APP_KEY', () async {
    final client = MockClient((request) async {
      expect(request.headers['x-app-key'], VexoApi.appKey);
      return http.Response('{"ok":true}', 200);
    });
    final api = VexoApi(client: client);
    await api.get('/health');
    api.close();
  });

  test('public API requests carry the current session for admin maintenance bypass', () async {
    final client = MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer ${'a' * 64}');
      return http.Response('{"ok":true}', 200, request: request);
    });
    final api = VexoApi(client: client);
    await api.saveToken('a' * 64);
    await api.get('/config');
    api.close();
  });

  test('embed grant requests send the signed-in app session in Authorization', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/embed/grant');
      expect(request.headers['authorization'], 'Bearer ${'b' * 64}');
      expect(request.headers['x-app-key'], VexoApi.appKey);
      expect(jsonDecode(request.body), {
        'url': 'https://www.pornhub.com/view_video.php?viewkey=abc12345',
      });
      return http.Response('{"grant":"short-lived-ticket","expiresAt":2000000000}', 200, request: request);
    });
    final api = VexoApi(client: client);
    await api.saveToken('b' * 64);
    final result = asMap(await api.post(
      '/embed/grant',
      body: {'url': 'https://www.pornhub.com/view_video.php?viewkey=abc12345'},
      authenticated: true,
    ));
    expect(result['grant'], 'short-lived-ticket');
    api.close();
  });

  test('diagnostics success does not clear a typed maintenance response', () async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/config')) {
        return http.Response('{"code":"maintenance","error":"Maintenance"}', 503, request: request);
      }
      return http.Response('{"ok":true}', 200, request: request);
    });
    final api = VexoApi(client: client);
    await expectLater(api.get('/config'), throwsA(isA<ApiException>()));
    expect(api.maintenanceMode.value, isTrue);
    await api.get('/check-host/result');
    expect(api.maintenanceMode.value, isTrue);
    await api.get('/account');
    expect(api.maintenanceMode.value, isFalse);
    api.close();
  });

  test('network failure reports actual API hosts and fallback does not claim all internet is down', () async {
    final hosts = <String>[];
    final client = MockClient((request) async {
      hosts.add(request.url.host);
      throw http.ClientException('SocketException: connection refused', request.url);
    });
    final api = VexoApi(client: client);
    try {
      await api.get('/health');
      fail('Expected the API connection to fail.');
    } on ApiException catch (e) {
      expect(e.code, 'offline');
      expect(e.message, contains('vexostream.bond'));
      expect(e.message, contains('api.vexostream.bond'));
      expect(e.message, contains('connection refused'));
      expect(e.message, isNot(contains('Check your internet connection')));
    } finally {
      api.close();
    }
    expect(hosts.first, 'vexostream.bond');
    expect(hosts.last, 'api.vexostream.bond');
  });

  test('network error truncation uses normalized detail length', () async {
    final message = '${List.filled(115, 'x').join()}${List.filled(80, ' ').join()}y';
    final client = MockClient((request) async {
      throw http.ClientException(message, request.url);
    });
    final api = VexoApi(client: client);
    try {
      await expectLater(
        api.get('/health'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', 'offline')
            .having((e) => e.message, 'message', isNot(contains('RangeError')))),
      );
    } finally {
      api.close();
    }
  });

  test('HTTP error body truncation uses normalized body length', () async {
    final body = '{       "padding"       : "${List.filled(300, ' ').join()}"       }';
    final client = MockClient((request) async => http.Response(body, 400));
    final api = VexoApi(client: client);
    try {
      await expectLater(
        api.get('/models'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 400)
            .having((e) => e.message, 'message', isNot(contains('RangeError')))),
      );
    } finally {
      api.close();
    }
  });

  test('API shows the Core service detail instead of a generic HTTP 400', () async {
    final client = MockClient((request) async => http.Response('{"detail":"gender must be Female, Male, or Female,Male"}', 400));
    final api = VexoApi(client: client);
    await expectLater(api.get('/models'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('gender must be Female, Male, or Female,Male'))));
    api.close();
  });

  test('wrong APP_KEY is not misreported as a member-login failure', () {
    const error = ApiException('The app API key is missing or does not match the Worker key.', statusCode: 401, code: 'app_key_invalid');
    expect(error.needsLogin, isFalse);
  });
}
