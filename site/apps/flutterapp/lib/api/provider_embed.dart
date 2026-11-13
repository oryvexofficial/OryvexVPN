import 'dart:convert';

class ProviderEmbedInfo {
  const ProviderEmbedInfo({
    required this.provider,
    required this.sourceUri,
    required this.embedUri,
  });

  final String provider;
  final Uri sourceUri;
  final Uri embedUri;
}

const Map<String, String> _providerDomains = {
  'pornhub': 'pornhub.com',
  'xvideos': 'xvideos.com',
  'xnxx': 'xnxx.com',
  'youporn': 'youporn.com',
  'redtube': 'redtube.com',
};

String _firstText(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = (source[key] ?? '').toString().trim();
    if (value.isNotEmpty) return value;
  }
  return '';
}

String? _providerForHost(String host) {
  for (final entry in _providerDomains.entries) {
    if (host == entry.value || host.endsWith('.${entry.value}')) {
      return entry.key;
    }
  }
  return null;
}

Uri? _safeProviderPageUri(String raw) {
  final value = raw.trim();
  if (value.isEmpty || value != raw) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  if (uri.hasPort && uri.port != (uri.scheme == 'https' ? 443 : 80)) {
    return null;
  }
  return uri;
}

bool _isSupportedVideoPage(String provider, Uri uri) {
  switch (provider) {
    case 'pornhub':
      final key = uri.queryParameters['viewkey'] ?? '';
      return uri.path == '/view_video.php' &&
          RegExp(r'^[A-Za-z0-9_-]{6,32}$').hasMatch(key);
    case 'xvideos':
      return RegExp(r'^/video\.?[A-Za-z0-9]{6,32}(?:/|$)')
          .hasMatch(uri.path);
    case 'xnxx':
      return RegExp(r'^/video-[A-Za-z0-9]{6,32}(?:/|$)')
          .hasMatch(uri.path);
    case 'youporn':
      return RegExp(r'^/watch/\d{4,15}(?:/[^/]*)?/?$')
          .hasMatch(uri.path);
    case 'redtube':
      return RegExp(r'^/(?:video/)?\d{4,12}(?:/[^/]*)?/?$')
          .hasMatch(uri.path);
    default:
      return false;
  }
}

/// Builds a link to VexoStream's own embedded player for a supported provider
/// page. The source URL is validated, then encoded into VexoStream's route.
ProviderEmbedInfo? providerEmbedForVideo(Map<String, dynamic> video) {
  final rawSource = _firstText(video, const ['url', 'video_url', 'link', 'href']);
  final sourceUri = _safeProviderPageUri(rawSource);
  if (sourceUri == null) return null;

  final host = sourceUri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  final provider = _providerForHost(host);
  if (provider == null || !_isSupportedVideoPage(provider, sourceUri)) return null;
  final encodedSource =
      base64Url.encode(utf8.encode(sourceUri.toString())).replaceAll('=', '');
  return ProviderEmbedInfo(
    provider: provider,
    sourceUri: sourceUri,
    embedUri: Uri.https('vexostream.bond', '/embed/$encodedSource'),
  );
}

/// Restricts top-level WebView navigations to VexoStream's own embed route.
bool isAllowedProviderEmbedNavigation(String rawUrl) {
  final uri = Uri.tryParse(rawUrl);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return false;
  }
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  return (host == 'vexostream.bond' || host == 'www.vexostream.bond') &&
      uri.path.startsWith('/embed/');
}
