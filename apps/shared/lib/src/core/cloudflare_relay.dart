import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'backend.dart';

class CloudflareAccount {
  const CloudflareAccount({required this.id, required this.name});
  final String id;
  final String name;
}

class CloudflareRelayDeployment {
  const CloudflareRelayDeployment({required this.scriptName, required this.publicUrl});
  final String scriptName;
  final String publicUrl;
}

class CloudflareRelayException implements Exception {
  const CloudflareRelayException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// The Worker was created, but its private URL could not be saved in Fox.
/// Keep the URL only in memory so the UI can retry without creating another Worker.
class CloudflareRelayUnlinkedException extends CloudflareRelayException {
  const CloudflareRelayUnlinkedException(this.relayUrl, this.publicUrl)
      : super('Worker created, but Fox settings could not be saved. Retry linking.');
  final String relayUrl;
  final String publicUrl;
}

/// Calls Cloudflare directly from the native Flutter app. The token is never
/// persisted and is only sent in an Authorization header to api.cloudflare.com.
class CloudflareRelayClient {
  CloudflareRelayClient() : _http = HttpClient()..connectionTimeout = const Duration(seconds: 12);

  static const _apiRoot = 'https://api.cloudflare.com/client/v4';
  static const tokenTemplateUrl =
      'https://dash.cloudflare.com/profile/api-tokens?permissionGroupKeys=%5B%7B%22key%22%3A%22account_settings%22%2C%22type%22%3A%22read%22%7D%2C%7B%22key%22%3A%22workers_scripts%22%2C%22type%22%3A%22edit%22%7D%5D&accountId=*&zoneId=all&name=OryvexVPN%20Fox%20Relay';

  final HttpClient _http;
  bool _disposed = false;

  Future<List<CloudflareAccount>> listAccounts(String token) async {
    final accounts = <CloudflareAccount>[];
    for (var page = 1; page <= 10; page++) {
      final data = await _request(token, 'GET', '/accounts', query: {'page': '$page', 'per_page': '50'});
      final raw = data['result'];
      if (raw is! List) throw const CloudflareRelayException('Cloudflare returned an unexpected account list.');
      for (final item in raw) {
        if (item is Map) {
          final id = item['id'];
          final name = item['name'];
          if (id is String && id.isNotEmpty && name is String && name.isNotEmpty) {
            accounts.add(CloudflareAccount(id: id, name: name));
          }
        }
      }
      if (raw.length < 50) break;
    }
    if (accounts.isEmpty) throw const CloudflareRelayException('This token did not return any Cloudflare accounts. Check its account scope.');
    return accounts;
  }

  Future<CloudflareRelayDeployment> deployAndConfigureFox({
    required String token,
    required CloudflareAccount account,
    required CoreBackend backend,
  }) async {
    final suffix = _randomHex(6);
    final workerName = 'oryvex-fox-$suffix';
    final secret = _randomSecret();
    final accountSubdomain = await _ensureAccountSubdomain(token, account.id);
    final workerSource = await rootBundle.loadString('packages/oryvex_shared/assets/cloudflare/worker.js');

    await _uploadWorker(token, account.id, workerName, workerSource);
    await _request(token, 'PUT', '/accounts/${_path(account.id)}/workers/scripts/${_path(workerName)}/secrets',
        jsonBody: {'name': 'SECRET', 'text': secret, 'type': 'secret_text'});
    await _request(token, 'POST', '/accounts/${_path(account.id)}/workers/scripts/${_path(workerName)}/subdomain',
        jsonBody: {'enabled': true, 'previews_enabled': false});

    final host = '$workerName.$accountSubdomain.workers.dev';
    final publicUri = Uri.https(host, '/');
    final relayUri = Uri.https(host, '/', {'secret': secret});
    try {
      await configureFoxRelay(backend, relayUri.toString());
    } catch (_) {
      throw CloudflareRelayUnlinkedException(relayUri.toString(), publicUri.toString());
    }
    return CloudflareRelayDeployment(scriptName: workerName, publicUrl: publicUri.toString());
  }

  Future<String> _ensureAccountSubdomain(String token, String accountId) async {
    final path = '/accounts/${_path(accountId)}/workers/subdomain';
    try {
      final response = await _request(token, 'GET', path);
      final result = response['result'];
      final value = result is Map ? result['subdomain'] : null;
      if (value is String && value.trim().isNotEmpty) return value.trim();
    } on CloudflareRelayException catch (e) {
      if (e.statusCode != 404) rethrow;
    }

    // Some accounts have not claimed a workers.dev hostname yet. Claim a unique
    // Oryvex-prefixed one instead of asking the user to leave the setup flow.
    for (var attempt = 0; attempt < 3; attempt++) {
      final candidate = 'oryvex-${_randomHex(5)}';
      try {
        final created = await _request(token, 'PUT', path, jsonBody: {'subdomain': candidate});
        final result = created['result'];
        final value = result is Map ? result['subdomain'] : null;
        if (value is String && value.trim().isNotEmpty) return value.trim();
        return candidate;
      } on CloudflareRelayException catch (e) {
        final text = e.message.toLowerCase();
        if (e.statusCode == 409 || text.contains('already') || text.contains('taken') || text.contains('available')) {
          continue;
        }
        rethrow;
      }
    }
    throw const CloudflareRelayException('Could not claim a workers.dev subdomain. Choose one in Cloudflare and try again.');
  }

  Future<void> _uploadWorker(String token, String accountId, String workerName, String source) async {
    final boundary = 'oryvex_${_randomHex(18)}';
    final bytes = BytesBuilder(copy: false);
    void text(String value) => bytes.add(utf8.encode(value));
    text('--$boundary\r\nContent-Disposition: form-data; name="metadata"\r\nContent-Type: application/json\r\n\r\n');
    text(jsonEncode({'main_module': 'worker.js', 'compatibility_date': '2025-01-01'}));
    text('\r\n--$boundary\r\nContent-Disposition: form-data; name="worker.js"; filename="worker.js"\r\nContent-Type: application/javascript+module\r\n\r\n');
    bytes.add(utf8.encode(source));
    text('\r\n--$boundary--\r\n');
    await _request(
      token,
      'PUT',
      '/accounts/${_path(accountId)}/workers/scripts/${_path(workerName)}',
      rawBody: bytes.takeBytes(),
      contentType: 'multipart/form-data; boundary=$boundary',
    );
  }

  Future<void> configureFoxRelay(CoreBackend backend, String relayUrl) async {
    final view = await backend.foxRequest('GET', '/api/settings');
    final rawConfig = view['config'];
    if (rawConfig is! Map) throw const CloudflareRelayException('Fox returned an unexpected settings response.');
    final config = Map<String, dynamic>.from(rawConfig);
    final rawNetwork = config['network'];
    if (rawNetwork is! Map) throw const CloudflareRelayException('Fox settings did not include network settings.');
    final network = Map<String, dynamic>.from(rawNetwork);
    network['api_relay'] = relayUrl;
    network['api_relay_enabled'] = true;
    config['network'] = network;
    final saved = await backend.foxRequest('PUT', '/api/settings', {'config': config});
    if (saved['saved'] != true) throw const CloudflareRelayException('Fox did not confirm that the relay was saved.');
  }

  Future<Map<String, dynamic>> _request(
    String token,
    String method,
    String path, {
    Map<String, String>? query,
    Object? jsonBody,
    Uint8List? rawBody,
    String? contentType,
  }) async {
    if (_disposed) throw const CloudflareRelayException('Cloudflare setup has already closed.');
    final uri = Uri.parse('$_apiRoot$path').replace(queryParameters: query);
    try {
      final request = await _http.openUrl(method, uri).timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (jsonBody != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(jsonBody));
      } else if (rawBody != null) {
        request.headers.set(HttpHeaders.contentTypeHeader, contentType ?? 'application/octet-stream');
        request.add(rawBody);
      }
      final response = await request.close().timeout(const Duration(seconds: 30));
      final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 30));
      Map<String, dynamic> decoded;
      try {
        final value = jsonDecode(body);
        if (value is! Map<String, dynamic>) throw const FormatException();
        decoded = value;
      } on FormatException {
        throw CloudflareRelayException('Cloudflare returned an unreadable response (HTTP ${response.statusCode}).', statusCode: response.statusCode);
      }
      if (response.statusCode < 200 || response.statusCode >= 300 || decoded['success'] == false) {
        final errors = decoded['errors'];
        var message = 'Cloudflare rejected the request (HTTP ${response.statusCode}).';
        if (errors is List && errors.isNotEmpty && errors.first is Map) {
          final candidate = (errors.first as Map)['message'];
          if (candidate is String && candidate.trim().isNotEmpty) message = candidate.trim();
        }
        message = message.replaceAll(token, '[hidden]');
        if (jsonBody is Map && jsonBody['text'] is String) {
          final secret = jsonBody['text'] as String;
          if (secret.isNotEmpty) message = message.replaceAll(secret, '[hidden]');
        }
        if (message.length > 240) message = '${message.substring(0, 240)}…';
        throw CloudflareRelayException(message, statusCode: response.statusCode);
      }
      return decoded;
    } on CloudflareRelayException {
      rethrow;
    } on SocketException {
      throw const CloudflareRelayException('Could not reach Cloudflare. Check your connection and try again.');
    } on HttpException {
      throw const CloudflareRelayException('Cloudflare closed the connection before deployment finished.');
    } on HandshakeException {
      throw const CloudflareRelayException('Cloudflare TLS verification failed. Check your device date and network.');
    } on FormatException {
      throw const CloudflareRelayException('Cloudflare returned an unreadable response.');
    } catch (_) {
      throw const CloudflareRelayException('Cloudflare deployment failed. No token was saved.');
    }
  }

  static String _path(String value) => Uri.encodeComponent(value);

  static String _randomHex(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  static String _randomSecret() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  void close() {
    _disposed = true;
    _http.close(force: true);
  }
}
