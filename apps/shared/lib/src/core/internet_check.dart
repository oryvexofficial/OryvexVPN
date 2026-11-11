import 'dart:async';
import 'dart:io';

/// Returns true only when at least one connectivity probe answers the way it should.
///
/// Both probes are "generate_204" endpoints: they answer with an empty 204 and carry nothing
/// about the device, so this check never learns (or reveals) an IP address or a country. A
/// captive portal answers them with a 200 sign-in page, which does not count.
Future<bool> hasInternetAccess() async {
  final results = await Future.wait<bool>([
    _probe(Uri.https('connectivitycheck.gstatic.com', '/generate_204')),
    _probe(Uri.https('cp.cloudflare.com', '/generate_204')),
  ]);
  return results.any((reachable) => reachable);
}

Future<bool> _probe(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 4));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close().timeout(const Duration(seconds: 4));
    await response.drain<void>().timeout(const Duration(seconds: 2));
    return response.statusCode == HttpStatus.noContent;
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}
