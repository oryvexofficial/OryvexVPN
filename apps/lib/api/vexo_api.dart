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

/// Talks to the VexoStream Worker API.
///
/// Uses the main site API route first, then falls back to api.vexostream.bond.
/// Both hostnames serve the same Worker API under /api/v1.
class VexoApi {
  VexoApi({http.Client? client}) : _client = client ?? http.Client();

  static const _override = String.fromEnvironment('VEXOSTREAM_API_BASE');
  static const appKey = String.fromEnvironment('APP_KEY');
  static const primaryBase = 'https://api.vexostream.bond/api/v1';
  static const fallbackBase = 'https://vexostream.bond/api/v1';
  static const userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) VexoStream-Windows/1.1';
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
    if (authenticated && token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
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
    final detail = rawDetail.replaceAll(RegExp(r'\s+'), ' ').substring(0, rawDetail.length > 180 ? 180 : rawDetail.length);
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
      if (maintenanceMode.value) maintenanceMode.value = false;
      return data;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final map = data is Map ? data : const <String, dynamic>{};
      var message = (map['error'] ?? map['message'] ?? '').toString();
      final code = (map['code'] ?? '').toString();
      maintenanceMode.value = response.statusCode == 503 && (code == 'maintenance' || message.toLowerCase().contains('maintenance'));
      if (message.isEmpty && rawBody.isNotEmpty && !rawBody.toLowerCase().contains('<html')) {
        message = rawBody.replaceAll(RegExp(r'\s+'), ' ').substring(0, rawBody.length > 240 ? 240 : rawBody.length);
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
    if (!value.startsWith('http')) return '';
    return _origin.replace(path: '/api/v1/image', queryParameters: {'url': value}).toString();
  }

  Map<String, String> get imageHeaders => {'User-Agent': userAgent, 'Accept': 'image/avif,image/webp,image/*,*/*;q=0.8', 'X-App-Key': appKey};
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
      final isHls = Uri.parse(rawUrl).path.toLowerCase().endsWith('.m3u8');
      return _origin.replace(
        path: isHls ? '/proxy-m3u8' : '/proxy-video',
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
  final direct = firstText(item, const [
    'thumbnail', 'thumbnail_url', 'thumb', 'thumb_url', 'poster', 'poster_url',
    'image', 'image_url', 'preview', 'preview_url', 'cover', 'cover_url'
  ]);
  if (direct.isNotEmpty) return direct;
  for (final key in const ['images', 'photos', 'thumbnails']) {
    final values = asList(item[key]);
    if (values.isEmpty) continue;
    final first = values.first;
    final url = first is Map ? firstText(asMap(first), const ['url', 'image_url', 'src']) : first.toString().trim();
    if (url.isNotEmpty) return url;
  }
  return '';
}

/// Catalogue responses are either a bare list or wrapped in a map.
List<Map<String, dynamic>> videoItems(dynamic value) {
  final map = asMap(value);
  final raw = value is List ? value : asList(map['videos'] ?? map['results'] ?? map['items'] ?? map['data']);
  return raw.map(asMap).where((it) {
    final url = firstText(it, const ['url', 'video_url', 'link', 'href']);
    final thumb = videoThumbnail(it).toLowerCase();
    return url.isNotEmpty && !thumb.contains('blank.gif');
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
