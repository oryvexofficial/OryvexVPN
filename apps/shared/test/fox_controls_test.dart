import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oryvex_shared/src/core/backend.dart';
import 'package:oryvex_shared/src/core/settings.dart';
import 'package:oryvex_shared/src/ui/widgets/fox_controls.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Fox can set the system proxy from its connection controls', (tester) async {
    final backend = _FoxBackend();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: FoxControls(backend: backend)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Set system proxy'), findsOneWidget);
    await tester.ensureVisible(find.text('Set system proxy'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Set system proxy'));
    await tester.pumpAndSettle();

    expect(backend.systemProxyMode, 'set');
    expect(
      backend.requests.any((request) =>
          request['method'] == 'POST' &&
          request['path'] == '/api/system-proxy' &&
          (request['body'] as Map?)?['mode'] == 'set'),
      isTrue,
    );
  });

  testWidgets('Fox hides system proxy on Android', (tester) async {
    final backend = _FoxBackend(isAndroid: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: FoxControls(backend: backend)),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Set system proxy'), findsNothing);
  });
}

class _FoxBackend implements CoreBackend {
  _FoxBackend({this.isAndroid = false});

  @override
  final bool isAndroid;
  final requests = <Map<String, dynamic>>[];
  String systemProxyMode = 'clear';

  @override
  Stream<BackendEvent> get events => const Stream<BackendEvent>.empty();

  @override
  bool get supportsVpn => isAndroid;

  @override
  bool get supportsPsiphon => false;

  @override
  bool get supportsSystemProxy => !isAndroid;

  @override
  String get platformLabel => isAndroid ? 'Android' : 'test';

  @override
  Future<BackendStatus> status() async => const BackendStatus(running: false);

  @override
  Future<void> start(CoreSettings settings, int run) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<String> installMitmCertificate() async => '';

  @override
  Future<Map<String, dynamic>> foxRequest(
    String method,
    String path, [Map<String, dynamic>? body]
  ) async {
    requests.add({'method': method, 'path': path, 'body': body});
    if (path == '/api/accounts') return {'accounts': <dynamic>[]};
    if (path == '/api/status') {
      return {
        'selection': '',
        'system_proxy_supported': true,
        'system_proxy': systemProxyMode,
      };
    }
    if (path == '/api/settings') return {'config': {'network': <String, dynamic>{}}};
    if (path == '/api/system-proxy') {
      systemProxyMode = body?['mode'] as String? ?? 'clear';
      return {'mode': systemProxyMode};
    }
    return <String, dynamic>{};
  }

  @override
  Future<void> shutdown() async {}
}
