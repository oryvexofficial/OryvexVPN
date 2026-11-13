import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.code});
  final String message;
  final int? statusCode;
  final String? code;

  bool get needsLogin => code == 'auth_required' || code == 'login' || (statusCode == 401 && code == null);

  @override
  String toString() => message;
}

/// Playback link failures tied to an expired or rejected signed session.
/// Refreshing the extraction first is important because every quality returned
/// together shares the same signed-link expiry.
bool isExpiredMediaFailure(String message) {
  final text = message.toLowerCase();
  if (RegExp(r'\b(?:401|403|410)\b').hasMatch(text)) return true;
  return text.contains('expired media token') ||
      text.contains('invalid or expired') ||
      text.contains('expired stream') ||
      text.contains('stream expired') ||
      text.contains('session expired') ||
      text.contains('expired session') ||
      text.contains('unauthorized') ||
      text.contains('forbidden');
}

/// Talks to the VexoStream Worker API.
///
/// Uses the main site API route first, then falls back to api.vexostream.bond.
/// Both hostnames serve the same Worker API under /api/v1.
class VexoApi {
  VexoApi({http.Client? client}) : _client = client ?? http.Client();

  static const _override = String.fromEnvironment('VEXOSTREAM_API_BASE');
  static const appKey = String.fromEnvironment('APP_KEY');
  static const appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '1.0.2');
  static const primaryBase = 'https://api.vexostream.bond/api/v1';
  static const fallbackBase = 'https://vexostream.bond/api/v1';
  static String get userAgent => Platform.isAndroid
      ? 'Mozilla/5.0 (Linux; Android) VexoStream-Android/$appVersion'
      : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) VexoStream-Windows/$appVersion';
  static const _tokenKey = 'vexostream.api.bearer.v1';
  static const _secureStorage = FlutterSecureStorage();

  static List<String> get _bases {
    final bases = _override.isNotEmpty ? [_override, fallbackBase, primaryBase] : [fallbackBase, primaryBase];
    return bases.toSet().toList();
  }

  final http.Client _client;
  final ValueNotifier<bool> maintenanceMode = ValueNotifier(false);
  String? _token;
  int _baseIndex = 0;

  String get activeBase => _bases[_baseIndex.clamp(0, _bases.length - 1)];
  bool get hasToken => (_token ?? '').isNotEmpty;

  Future<String?> loadToken() async {
    try {
      _token ??= await _secureStorage.read(key: _tokenKey);
    } catch (_) {
      _token = null;
    }
    return _token;
  }

  Future<void> saveToken(String token) async {
    _token = token;
    try {
      await _secureStorage.write(key: _tokenKey, value: token);
    } catch (_) {}
  }

  Future<void> clearToken() async {
    _token = null;
    try {
      await _secureStorage.delete(key: _tokenKey);
    } catch (_) {}
  }

  Uri _uri(String base, String path, [Map<String, Object?>? query]) {
    final parsed = Uri.parse(base);
    final basePath = parsed.path.endsWith('/') ? parsed.path.substring(0, parsed.path.length - 1) : parsed.path;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final parameters = <String, dynamic>{};
    query?.forEach((key, value) {
      if (value == null) return;
      if (value is Iterable) {
        final list = value.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
        if (list.isNotEmpty) parameters[key] = list;
      } else if (value.toString().isNotEmpty) {
        parameters[key] = value.toString();
      }
    });
    return parsed.replace(path: '$basePath$normalizedPath', queryParameters: parameters.isEmpty ? null : parameters);
  }

  /// Origin (scheme + host) of the host currently in use, for media/image proxies.
  Uri get _origin {
    final parsed = Uri.parse(activeBase);
    return Uri(scheme: parsed.scheme, host: parsed.host, port: parsed.hasPort ? parsed.port : null);
  }

  Map<String, String> _headers({bool authenticated = false, bool json = false}) {
    final headers = <String, String>{
      'Accept': 'application/json',
      'User-Agent': userAgent,
      'Accept-Language': 'en-US,en;q=0.9',
      'X-App-Key': appKey,
    };
    if (json) headers['Content-Type'] = 'application/json';
    final token = _token;
    // Public app API calls also need the session for the maintenance bypass.
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }

  static bool _isNetworkError(Object e) =>
      e is SocketException || e is http.ClientException || e is TimeoutException || e is HandshakeException || e is HttpException;

  Future<http.Response> _send(Future<http.Response> Function(String base) run) async {
    Object? lastError;
    final attempted = <String>[];
    for (var offset = 0; offset < _bases.length; offset++) {
      final i = (_baseIndex + offset) % _bases.length;
      final base = _bases[i];
      final host = Uri.tryParse(base)?.host ?? base;
      attempted.add(host);
      try {
        final response = await run(base);
        _baseIndex = i;
        return response;
      } catch (e) {
        if (!_isNetworkError(e)) rethrow;
        lastError = e;
      }
    }
    // Each API origin was tried; prefer the reachable website host next time.
    _baseIndex = 0;
    final rawDetail = lastError?.toString() ?? 'unknown network error';
    final normalizedDetail = rawDetail.replaceAll(RegExp(r'\s+'), ' ').trim();
    final detail = normalizedDetail.length > 180
        ? normalizedDetail.substring(0, 180)
        : normalizedDetail;
    throw ApiException(
      'The app could not open an HTTPS connection to the VexoStream API (${attempted.join(', ')}). This is an app-to-API connection failure, not proof that your whole internet is down. Details: $detail',
      code: 'offline',
      statusCode: lastError is SocketException ? 0 : null,
    );
  }

  Future<dynamic> get(String path, {Map<String, Object?>? query, bool authenticated = false, Duration timeout = const Duration(seconds: 25)}) async {
    final response = await _send((base) => _client.get(_uri(base, path, query), headers: _headers(authenticated: authenticated)).timeout(timeout));
    return _decode(response);
  }

  Future<dynamic> post(String path, {Map<String, Object?>? body, bool authenticated = false, Duration timeout = const Duration(seconds: 25)}) async {
    final payload = jsonEncode(body ?? const {});
    final response = await _send((base) => _client.post(_uri(base, path), headers: _headers(authenticated: authenticated, json: true), body: payload).timeout(timeout));
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    dynamic data;
    var rawBody = '';
    try {
      rawBody = utf8.decode(response.bodyBytes).trim();
      data = jsonDecode(rawBody);
    } catch (_) {
      data = <String, dynamic>{};
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Diagnostics and media bypass the maintenance gate and cannot prove it is open.
      final path = response.request?.url.path ?? '';
      if (path.endsWith('/account') || path.endsWith('/config') || path.endsWith('/providers')) {
        maintenanceMode.value = false;
      }
      return data;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final map = data is Map ? data : const <String, dynamic>{};
      var message = (map['error'] ?? map['message'] ?? map['detail'] ?? '').toString();
      final code = (map['code'] ?? '').toString();
      if (response.statusCode == 503 && code == 'maintenance') maintenanceMode.value = true;
      if (message.isEmpty && rawBody.isNotEmpty && !rawBody.toLowerCase().contains('<html')) {
        final normalizedBody = rawBody.replaceAll(RegExp(r'\s+'), ' ').trim();
        message = normalizedBody.length > 240
            ? normalizedBody.substring(0, 240)
            : normalizedBody;
      }
      if (message.isEmpty) {
        message = switch (response.statusCode) {
          401 => 'Please log in first.',
          403 => 'Access was blocked by the server.',
          404 => 'Not found.',
          423 => 'This library is currently unavailable.',
          429 => 'Too many requests. Wait a moment and try again.',
          503 => 'VexoStream is under maintenance. Try again soon.',
          _ => response.statusCode == 400 ? 'The upstream service rejected this request (400). Check the VexoStream Core endpoint and logs.' : 'The server answered ${response.statusCode}.',
        };
      }
      throw ApiException(message, statusCode: response.statusCode, code: map['code']?.toString());
    }
    return data;
  }

  /// Proxied image URL (thumbnails, posters, performer photos).
  String imageUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    if (value.startsWith('//')) value = 'https:$value';
    final parsed = Uri.tryParse(value);
    if (parsed == null || (parsed.scheme != 'http' && parsed.scheme != 'https') || parsed.host.isEmpty) return '';
    final params = <String, String>{'url': value};
    if (appKey.isNotEmpty) params['key'] = appKey;
    return _origin.replace(path: '/api/v1/image', queryParameters: params).toString();
  }

  // Prefer formats decoded consistently by Flutter's Windows image codec.
  Map<String, String> get imageHeaders => {'User-Agent': userAgent, 'Accept': 'image/webp,image/png,image/jpeg,image/gif,*/*;q=0.8', 'X-App-Key': appKey};
  Map<String, String> get mediaHeaders => {'User-Agent': userAgent};

  /// Real posters (og:image of each video page), like the site cards use.
  Future<Map<String, String>> posters(List<String> pageUrls) async {
    final wanted = pageUrls.where((u) => u.startsWith('https://')).toSet().take(24).toList();
    if (wanted.isEmpty) return const {};
    try {
      final data = asMap(await get('/posters', query: {'u': wanted}));
      final out = <String, String>{};
      asMap(data['posters']).forEach((key, value) {
        final poster = (value ?? '').toString().trim();
        if (poster.isNotEmpty) out[key] = poster;
      });
      return out;
    } catch (_) {
      return const {};
    }
  }

  Uri streamUri(Map<String, dynamic> quality) {
    final encoded = (quality['x_url'] ?? '').toString();
    if (encoded.isEmpty) throw const ApiException('The stream link is missing.');
    try {
      final rawUrl = Uri.decodeComponent(utf8.decode(base64.decode(base64.normalize(encoded))));
      final source = Uri.parse(rawUrl);
      // Some providers serve HLS from extensionless endpoints. Use the extractor's
      // stream metadata as well as URL hints so playlists are rewritten by the Worker.
      final typeHints = ['type', 'mime_type', 'mime', 'format']
          .map((key) => (quality[key] ?? '').toString().toLowerCase())
          .join(' ');
      final urlHints = '${source.path} ${source.query}'.toLowerCase();
      final isHls = typeHints.contains('hls') ||
          typeHints.contains('m3u8') ||
          typeHints.contains('mpegurl') ||
          urlHints.contains('.m3u8') ||
          urlHints.contains('format=m3u8');
      final pathExtension = RegExp(r'\.([a-z0-9]{2,5})$', caseSensitive: false).firstMatch(source.path)?.group(1)?.toLowerCase();
      const nativeExtensions = {'mp4', 'm4v', 'webm', 'mov', 'mkv', 'mpg', 'mpeg', '3gp', 'avi'};
      final hintedExtension = nativeExtensions.firstWhere(typeHints.contains, orElse: () => 'mp4');
      final extension = nativeExtensions.contains(pathExtension) ? pathExtension : hintedExtension;
      // Give native demuxers a real playlist extension. Browsers identify HLS
      // from the response body, but mpv/FFmpeg can leave extensionless proxy
      // URLs in a loading state even when the Worker returns a valid playlist.
      return _origin.replace(
        path: isHls ? '/proxy-m3u8.m3u8' : '/proxy-video.$extension',
        queryParameters: {
          'url': rawUrl,
          'sig': (quality['x_sig'] ?? '').toString(),
          'exp': (quality['x_exp'] ?? '').toString(),
        },
      );
    } catch (_) {
      throw const ApiException('Could not decode the stream link.');
    }
  }

  void close() {
    _client.close();
    maintenanceMode.dispose();
  }
}

Map<String, dynamic> asMap(dynamic value) => value is Map<String, dynamic>
    ? value
    : value is Map
        ? value.map((key, item) => MapEntry(key.toString(), item))
        : <String, dynamic>{};

bool canAccessDeveloperTools(Map<String, dynamic> account) {
  final role = account['role']?.toString().trim().toLowerCase();
  return account['isOwner'] == true || role == 'owner' || role == 'admin';
}

List<dynamic> asList(dynamic value) => value is List ? value : <dynamic>[];

String defaultSearchQuery(dynamic config) {
  final value = firstText(asMap(config), const ['defaultQuery']).trim();
  return value.isEmpty ? 'trending' : value;
}

String firstText(Map<String, dynamic> map, List<String> keys, {String fallback = ''}) {
  for (final key in keys) {
    final value = map[key];
    if (value != null && value is! Map && value is! List && value.toString().trim().isNotEmpty) return value.toString();
  }
  return fallback;
}

/// Thumbnail aliases returned by the different catalogue backends.
String videoThumbnail(Map<String, dynamic> item) {
  const aliases = [
    'thumbnail', 'thumbnail_url', 'thumb', 'thumb_url', 'poster', 'poster_url',
    'image', 'image_url', 'preview', 'preview_url', 'cover', 'cover_url',
    'default_thumb', 'medialist', 'thumb_image', 'flv_thumbnail',
    'images', 'photos', 'thumbnails', 'thumbs',
  ];
  for (final key in aliases) {
    final value = _thumbnailCandidate(item[key]);
    if (value.isNotEmpty) return value;
  }
  return '';
}

String _thumbnailCandidate(dynamic value, [int depth = 0]) {
  if (depth > 3 || value == null) return '';
  if (value is Iterable) {
    for (final item in value.take(12)) {
      final candidate = _thumbnailCandidate(item, depth + 1);
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }
  if (value is Map) {
    for (final key in const [
      'url', 'src', 'image', 'image_url', 'thumbnail', 'thumbnail_url',
      'thumb', 'thumb_url', 'poster', 'poster_url', 'default_thumb',
      'cover_image', 'preview_image',
    ]) {
      final candidate = _thumbnailCandidate(value[key], depth + 1);
      if (candidate.isNotEmpty) return candidate;
    }
    return '';
  }
  var raw = value.toString().trim();
  if (raw.isEmpty || raw.length > 2048 ||
      RegExp(r'(?:blank|placeholder|default)\.gif(?:[?#]|$)', caseSensitive: false).hasMatch(raw)) {
    return '';
  }
  if (raw.startsWith('//')) raw = 'https:$raw';
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      RegExp(r'\.(?:mp4|m3u8|webm|m4s|ts)(?:$|[?#])', caseSensitive: false).hasMatch(uri.path)) {
    return '';
  }
  return uri.toString();
}

bool _hasPlaceholderThumbnail(dynamic value, [int depth = 0]) {
  if (depth > 3 || value == null) return false;
  if (value is Iterable) {
    return value.take(12).any((item) => _hasPlaceholderThumbnail(item, depth + 1));
  }
  if (value is Map) {
    const aliases = [
      'url', 'src', 'image', 'image_url', 'thumbnail', 'thumbnail_url',
      'thumb', 'thumb_url', 'poster', 'poster_url', 'default_thumb',
      'cover_image', 'preview_image',
    ];
    return aliases.any((key) => _hasPlaceholderThumbnail(value[key], depth + 1));
  }
  return RegExp(r'(?:blank|placeholder|default)\.gif(?:[?#]|$)', caseSensitive: false)
      .hasMatch(value.toString().trim());
}

/// Catalogue responses are either a bare list or wrapped in a map.
List<Map<String, dynamic>> videoItems(dynamic value) {
  final map = asMap(value);
  final raw = value is List ? value : asList(map['videos'] ?? map['results'] ?? map['items'] ?? map['data']);
  return raw.map(asMap).where((it) {
    final url = firstText(it, const ['url', 'video_url', 'link', 'href']);
    final thumb = videoThumbnail(it).toLowerCase();
    return url.isNotEmpty && !thumb.contains('blank.gif') &&
        (thumb.isNotEmpty || !_hasPlaceholderThumbnail(it));
  }).map((it) {
    final normalized = Map<String, dynamic>.from(it);
    final thumb = videoThumbnail(it);
    if (thumb.isNotEmpty) normalized['thumbnail'] = thumb;
    return normalized;
  }).toList();
}

String formatDuration(dynamic value) {
  if (value == null) return '';
  final text = value.toString().trim();
  if (text.isEmpty) return '';
  if (text.contains(':')) return text;
  final seconds = double.tryParse(text)?.round();
  if (seconds == null || seconds <= 0) return text;
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
  return '${h > 0 ? '$h:' : ''}$mm:${s.toString().padLeft(2, '0')}';
}
