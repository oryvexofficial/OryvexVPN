import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vexostream_app/api/provider_embed.dart';
import 'package:vexostream_app/api/vexo_api.dart';
import 'package:vexostream_app/pages/embedded_player_page.dart';

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
    });

    test('blocks provider URLs, arbitrary domains, and non-embed routes', () {
      for (final url in [
        'http://vexostream.bond/embed/YWJjMTIz',
        'https://vexostream.bond.attacker.example/embed/YWJjMTIz',
        'https://attacker.example@vexostream.bond/embed/YWJjMTIz',
        'https://vexostream.bond/video/YWJjMTIz',
        'https://vexostream.bond:8443/embed/YWJjMTIz',
        'https://www.pornhub.com/embed/abc12345',
      ]) {
        expect(isAllowedProviderEmbedNavigation(url), isFalse, reason: url);
      }
    });
  });

  testWidgets('app player never sends unsupported sources to the WebView', (tester) async {
    final api = VexoApi();
    await tester.pumpWidget(MaterialApp(
      home: PlayerPage(
        api: api,
        video: {'url': 'https://unlisted.example/video/123'},
        onSignIn: () async {},
      ),
    ));

    expect(find.text('Unsupported video link'), findsOneWidget);
    expect(
      find.text(
        'This link does not match a supported provider video page, so it cannot be opened in the VexoStream player.',
      ),
      findsOneWidget,
    );
    expect(find.text('Open embedded player'), findsNothing);
    api.close();
  });
}
