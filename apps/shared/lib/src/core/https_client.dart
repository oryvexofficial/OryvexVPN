import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The answer to one [HttpsGet.fetch].
class HttpsReply {
  const HttpsReply(this.statusCode, this.headers, this.body);

  final int statusCode;

  /// Response headers, names lowercased.
  final Map<String, String> headers;
  final String body;

  bool get ok => statusCode >= 200 && statusCode < 300;
}

/// A tiny HTTPS GET that can ride the core's SOCKS5 port.
///
/// The Android app process bypasses its own VpnService and the desktop app ignores the system
/// proxy it sets, so anything the app itself fetches while connected (the update check) goes
/// through `127.0.0.1:<socks>` by hand. Certificates and host names are always verified: the
/// TLS session is opened on top of the SOCKS stream with the real host name.
class HttpsGet {
  HttpsGet._();

  static const _maxBody = 4 * 1024 * 1024;

  static Future<HttpsReply> fetch(
    String host,
    String path, {
    int? socksPort,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 15),
  }) async {
    Socket? raw;
    SecureSocket? tls;
    _Reader? proxyReader;
    Timer? watchdog;
    void kill() {
      tls?.destroy();
      raw?.destroy();
    }

    try {
      if (socksPort == null) {
        tls = await SecureSocket.connect(host, 443, timeout: timeout, supportedProtocols: const ['http/1.1']);
      } else {
        raw = await Socket.connect(InternetAddress.loopbackIPv4, socksPort, timeout: const Duration(seconds: 4));
        // A slow request is destroyed when its deadline passes, so retries never pile up sockets.
        watchdog = Timer(timeout, kill);
        proxyReader = _Reader(raw);
        await _socksConnect(raw, proxyReader, host, 443).timeout(const Duration(seconds: 8));
        await proxyReader.cancel();
        proxyReader = null;
        tls = await SecureSocket.secure(raw, host: host, supportedProtocols: const ['http/1.1']).timeout(timeout);
      }
      watchdog ??= Timer(timeout, kill);

      final head = StringBuffer()
        ..write('GET $path HTTP/1.1\r\n')
        ..write('Host: $host\r\n')
        ..write('Accept-Encoding: identity\r\n')
        ..write('Connection: close\r\n');
      headers.forEach((k, v) => head.write('$k: $v\r\n'));
      head.write('\r\n');
      tls.write(head.toString());
      await tls.flush();

      final reader = _Reader(tls);
      late final List<int> bytes;
      try {
        bytes = await reader.rest(limit: _maxBody).timeout(timeout);
      } finally {
        await reader.cancel();
      }
      return parse(utf8.decode(bytes, allowMalformed: true));
    } finally {
      watchdog?.cancel();
      await proxyReader?.cancel();
      kill();
    }
  }

  /// Splits a raw HTTP/1.x response. Public so the parser can be tested on its own.
  static HttpsReply parse(String response) {
    final split = response.indexOf('\r\n\r\n');
    if (split < 0) throw const FormatException('the response has no header boundary');
    final firstEnd = response.indexOf('\r\n');
    final status = RegExp(r'^HTTP/1\.[01] (\d{3})(?:\s|$)').firstMatch(response.substring(0, firstEnd));
    if (status == null) throw const FormatException('the response has no status line');
    final headers = <String, String>{};
    for (final line in response.substring(firstEnd + 2, split).split('\r\n')) {
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers[line.substring(0, colon).trim().toLowerCase()] = line.substring(colon + 1).trim();
    }
    var body = response.substring(split + 4);
    if ((headers['transfer-encoding'] ?? '').toLowerCase().contains('chunked')) body = unchunk(body);
    return HttpsReply(int.parse(status.group(1)!), headers, body);
  }

  static String unchunk(String body) {
    final out = StringBuffer();
    var offset = 0;
    while (offset < body.length) {
      final end = body.indexOf('\r\n', offset);
      if (end < 0) throw const FormatException('malformed chunk header');
      final size = int.tryParse(body.substring(offset, end).split(';').first.trim(), radix: 16);
      if (size == null || size < 0) throw const FormatException('malformed chunk size');
      if (size == 0) return out.toString();
      final from = end + 2;
      final to = from + size;
      if (to > body.length) throw const FormatException('truncated chunk');
      out.write(body.substring(from, to));
      offset = to + 2;
    }
    return out.toString();
  }

  static Future<void> _socksConnect(Socket socket, _Reader reader, String host, int port) async {
    socket.add(const [5, 1, 0]);
    await socket.flush();
    final hello = await reader.take(2);
    if (hello[0] != 5 || hello[1] != 0) throw const SocketException('SOCKS5 refused the greeting');

    final name = ascii.encode(host);
    final request = <int>[5, 1, 0, 3, name.length, ...name, (port >> 8) & 0xff, port & 0xff];
    socket.add(request);
    await socket.flush();

    final reply = await reader.take(4);
    if (reply[0] != 5 || reply[1] != 0) throw SocketException('SOCKS5 CONNECT failed (${reply[1]})');
    switch (reply[3]) {
      case 1:
        await reader.take(6);
      case 4:
        await reader.take(18);
      case 3:
        await reader.take((await reader.take(1))[0] + 2);
      default:
        throw const SocketException('SOCKS5 sent an unknown address type');
    }
  }
}

class _Reader {
  _Reader(Socket socket) {
    _sub = socket.listen(
      (data) {
        _buf.addAll(data);
        _wake();
      },
      onError: (Object _) {
        _done = true;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
      cancelOnError: true,
    );
  }

  late final StreamSubscription<List<int>> _sub;
  final List<int> _buf = <int>[];
  bool _done = false;
  int _want = 0;
  Completer<void>? _waiter;

  void _wake() {
    final w = _waiter;
    if (w != null && (_done || _buf.length >= _want)) {
      _waiter = null;
      w.complete();
    }
  }

  Future<List<int>> take(int n) async {
    while (_buf.length < n && !_done) {
      _want = n;
      final w = Completer<void>();
      _waiter = w;
      await w.future;
    }
    if (_buf.length < n) throw const SocketException('the connection closed early');
    final out = _buf.sublist(0, n);
    _buf.removeRange(0, n);
    return out;
  }

  Future<List<int>> rest({required int limit}) async {
    while (!_done && _buf.length <= limit) {
      _want = limit + 1;
      final w = Completer<void>();
      _waiter = w;
      await w.future;
    }
    if (_buf.length > limit) throw const FormatException('the response is too large');
    final out = List<int>.of(_buf);
    _buf.clear();
    return out;
  }

  Future<void> cancel() => _sub.cancel();
}
