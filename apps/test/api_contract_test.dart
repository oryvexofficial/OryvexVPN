import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vexostream_app/api/vexo_api.dart';

void main() {
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

  test('signed HLS URLs use the Worker media proxy', () {
    final original = Uri.encodeComponent('https://cdn.example.test/playlist.m3u8?key=abc');
    final encoded = base64.encode(utf8.encode(original));
    final uri = VexoApi().streamUri({'x_url': encoded, 'x_sig': 'signed', 'x_exp': '123'});
    expect(uri.host, 'vexostream.bond');
    expect(uri.path, '/proxy-m3u8');
    expect(uri.queryParameters['url'], 'https://cdn.example.test/playlist.m3u8?key=abc');
    expect(uri.queryParameters['sig'], 'signed');
  });

  test('images go through the Worker image proxy and attach APP_KEY', () {
    final api = VexoApi();
    final url = Uri.parse(api.imageUrl('//img.example.test/a.jpg'));
    expect(url.path, '/api/v1/image');
    expect(url.queryParameters['url'], 'https://img.example.test/a.jpg');
    expect(api.imageHeaders['X-App-Key'], VexoApi.appKey);
    expect(api.mediaHeaders.containsKey('X-App-Key'), isFalse);
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

  test('wrong APP_KEY is not misreported as a member-login failure', () {
    const error = ApiException('The app API key is missing or does not match the Worker key.', statusCode: 401, code: 'app_key_invalid');
    expect(error.needsLogin, isFalse);
  });
}
