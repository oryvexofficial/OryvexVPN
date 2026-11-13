import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vexostream_app/api/provider_embed.dart';
import 'package:vexostream_app/api/vexo_api.dart';
import 'package:vexostream_app/pages/embedded_player_page.dart';
import 'package:vexostream_app/widgets/provider_embed_view.dart';

class _LoginRequiredConfigClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final payload = request.url.path.endsWith('/config')
        ? {'access': {'requireLogin': true}}
        : {'videos': <dynamic>[]};
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(payload))),
      200,
      headers: const {'content-type': 'application/json'},
      request: request,
    );
  }
}

void main() {
  group('VexoStream embed URL validation', () {
    test('builds VexoStream /embed links for supported provider page formats', () {
      final sources = <String>[
        'https://www.pornhub.com/view_video.php?viewkey=ph123456',
        'https://www.xvideos.com/video123456/example',
        'https://www.xnxx.com/video-12345678/example',
        'https://www.youporn.com/watch/505835/a-video-title/',
        'https://www.redtube.com/1795463',
      ];

      for (final source in sources) {
        final embed = providerEmbedForVideo({'url': source});
        expect(embed, isNotNull, reason: source);
        final resolvedEmbed = embed!;
        expect(
          resolvedEmbed.embedUri.scheme,
          'https',
          reason: source,
        );
        expect(resolvedEmbed.embedUri.host, 'vexostream.bond', reason: source);
        expect(resolvedEmbed.embedUri.path, startsWith('/embed/'), reason: source);
        expect(resolvedEmbed.appEmbedUri.path, startsWith('/embed/for/app/'), reason: source);
        final encoded = resolvedEmbed.embedUri.pathSegments.last;
        final decoded = utf8.decode(base64Url.decode(base64Url.normalize(encoded)));
        expect(decoded, source, reason: source);
      }
    });

    test('recognizes provider subdomains but generates only a VexoStream URL', () {
      final embed = providerEmbedForVideo({
        'url': 'https://fr.pornhub.com/view_video.php?viewkey=abc12345',
      })!;
      expect(embed?.provider, 'pornhub');
      expect(embed?.embedUri.host, 'vexostream.bond');
      expect(embed?.embedUri.path, startsWith('/embed/'));
    });

    test('generic compatibility URL preserves app parameters and app grants', () {
      final embed = providerEmbedForVideo({
        'url': 'https://www.xvideos.com/video123456/example',
      })!;
      final appUrl = embed.appEmbedUri.replace(queryParameters: {
        'app_thumb': 'https://thumb.example.test/video.jpg',
        'app_grant': '12345.signature',
      });
      final fallback = embed.embedUri.replace(
        queryParameters: appUrl.queryParameters,
      );

      expect(appUrl.path, startsWith('/embed/for/app/'));
      expect(fallback.path, startsWith('/embed/'));
      expect(
        fallback.queryParameters['app_thumb'],
        'https://thumb.example.test/video.jpg',
      );
      expect(
        fallback.queryParameters['app_grant'],
        '12345.signature',
      );
      expect(isAllowedProviderEmbedNavigation(appUrl.toString()), isTrue);
      expect(isAllowedProviderEmbedNavigation(fallback.toString()), isTrue);
    });

    test('rejects arbitrary hosts, credentials, ports, and malformed video pages', () {
      for (final url in [
        'https://www.pornhub.com.attacker.example/view_video.php?viewkey=abc12345',
        'https://attacker.example@www.pornhub.com/view_video.php?viewkey=abc12345',
        'https://www.pornhub.com:8443/view_video.php?viewkey=abc12345',
        'https://www.pornhub.com/view_video.php?viewkey=<script>',
        'https://www.pornhub.com/?viewkey=abc12345',
        'javascript:alert(1)',
      ]) {
        expect(providerEmbedForVideo({'url': url}), isNull, reason: url);
      }
    });
  });

  group('VexoStream WebView navigation allowlist', () {
    test('allows the first-party VexoStream embedded-player route only', () {
      expect(
        isAllowedProviderEmbedNavigation(
          'https://vexostream.bond/embed/YWJjMTIz',
        ),
        isTrue,
      );
      expect(
        isAllowedProviderEmbedNavigation(
          'https://www.vexostream.bond/embed/YWJjMTIz',
        ),
        isTrue,
      );
      expect(
        isAllowedProviderEmbedNavigation(
          'https://vexostream.bond/embed/for/app/YWJjMTIz',
        ),
        isTrue,
      );
    });

    test('blocks provider URLs, arbitrary domains, and non-embed routes', () {
      for (final url in [
        'http://vexostream.bond/embed/YWJjMTIz',
        'https://vexostream.bond.attacker.example/embed/YWJjMTIz',
        'https://attacker.example@vexostream.bond/embed/YWJjMTIz',
        'https://vexostream.bond/video/YWJjMTIz',
        'https://vexostream.bond:8443/embed/YWJjMTIz',
        'https://vexostream.bond/embed/for/other/YWJjMTIz',
        'https://vexostream.bond/embed/for/app',
        'https://www.pornhub.com/embed/abc12345',
      ]) {
        expect(isAllowedProviderEmbedNavigation(url), isFalse, reason: url);
      }
    });
  });

  group('app playback quality controls', () {
    test('reads available qualities and the current Auto/manual selection', () {
      final state = EmbeddedQualityState.parseScriptResult(jsonEncode({
        'auto': false,
        'current': 1,
        'title': 'A real provider title',
        'provider': 'pornhub',
        'thumbnail': 'https://thumb.example.test/video.jpg',
        'qualities': [
          {'index': 0, 'label': '1080p', 'format': 'HLS', 'visible': true},
          {'index': 1, 'label': '720p', 'format': 'MP4', 'visible': true},
          {'index': 2, 'label': 'fallback', 'format': 'MP4', 'visible': false},
        ],
      }));

      expect(state, isNotNull);
      expect(state!.isAuto, isFalse);
      expect(state.currentIndex, 1);
      expect(state.currentLabel, '720p');
      expect(state.title, 'A real provider title');
      expect(state.provider, 'pornhub');
      expect(state.thumbnail, 'https://thumb.example.test/video.jpg');
      expect(state.options.map((quality) => quality.label), ['1080p', '720p']);
      expect(state.options.map((quality) => quality.format), ['HLS', 'MP4']);
    });

    test('returns null until the embedded player exposes its stream queue', () {
      expect(EmbeddedQualityState.parseScriptResult(null), isNull);
      expect(EmbeddedQualityState.parseScriptResult('not-json'), isNull);
    });

    test('parses playback time for device-local continue watching history', () {
      final progress = EmbeddedPlaybackProgress.parseScriptResult(
        jsonEncode({'position': 37.8, 'duration': 120}),
      );

      expect(progress, isNotNull);
      expect(progress!.positionSeconds, 37.8);
      expect(progress.durationSeconds, 120);
      expect(
        EmbeddedPlaybackProgress.parseScriptResult(
          jsonEncode({'position': 0, 'duration': 120}),
        ),
        isNull,
      );
    });
  });

  testWidgets('app player never sends unsupported sources to the WebView', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = VexoApi();
    await tester.pumpWidget(MaterialApp(
      home: PlayerPage(
        api: api,
        video: {'url': 'https://unlisted.example/video/123'},
        onSignIn: () async {},
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('Unsupported video link'), findsOneWidget);
    expect(
      find.text(
        'This link does not match a supported provider video page, so it cannot be opened in the VexoStream player.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open embedded player'), findsNothing);
    expect(tester.takeException(), isNull);
    api.close();
  });

  testWidgets('anonymous app viewer sees the login gate when members-only playback is enabled', (tester) async {
    final api = VexoApi(client: _LoginRequiredConfigClient());
    var signInOpened = false;
    await tester.pumpWidget(MaterialApp(
      home: PlayerPage(
        api: api,
        video: {'url': 'https://www.xvideos.com/video123456/example'},
        onSignIn: () async { signInOpened = true; },
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('You must log in to continue'), findsOneWidget);
    expect(find.text('Log in'), findsOneWidget);
    await tester.tap(find.text('Log in'));
    await tester.pump();
    expect(signInOpened, isTrue);
    api.close();
  });
}
