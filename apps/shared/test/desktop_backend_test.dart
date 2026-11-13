import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oryvex_shared/src/core/backend.dart';
import 'package:oryvex_shared/src/core/desktop_backend.dart';

void main() {
  late Directory tempDir;
  late File executable;
  late List<_FakeProcess> processes;
  HttpServer? server;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('oryvex-fox-test-');
    executable = File('${tempDir.path}${Platform.pathSeparator}fox-core-test');
    await executable.writeAsString('test executable');
    processes = [];
    server = null;
  });

  tearDown(() async {
    await server?.close(force: true);
    for (final process in processes) {
      process.kill();
    }
    await tempDir.delete(recursive: true);
  });

  Future<void> serveConfiguredPort(String token) async {
    final configFile = File('${tempDir.path}${Platform.pathSeparator}config.json');
    final config = jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final dashboard = config['dashboard'] as Map<String, dynamic>;
    final port = int.parse((dashboard['listen'] as String).split(':').last);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    server!.listen((request) async {
      final authenticated = request.headers.value('X-Local-Token') == token;
      request.response.statusCode = authenticated ? HttpStatus.ok : HttpStatus.unauthorized;
      request.response.write('{}');
      await request.response.close();
    });
  }

  test('concurrent first Fox requests wait for one startup to finish', () async {
    var startCount = 0;
    final processStarterCalled = Completer<void>();
    final backend = DesktopBackend.forTesting(
      foxExecutableForTesting: executable.path,
      foxDataDirectoryForTesting: tempDir.path,
      foxProcessStarterForTesting: (
        executable,
        arguments, {
        workingDirectory,
        required mode,
      }) async {
        startCount++;
        final process = _FakeProcess();
        processes.add(process);
        processStarterCalled.complete();
        unawaited(Future<void>.delayed(const Duration(milliseconds: 20)).then((_) async {
          await serveConfiguredPort('test-token');
          await File('${tempDir.path}${Platform.pathSeparator}local-api.token')
              .writeAsString('test-token');
        }));
        return process;
      },
      foxStartupAttemptsForTesting: 60,
      foxStartupDelayForTesting: const Duration(milliseconds: 2),
    );

    final requests = <Future<Map<String, dynamic>>>[
      backend.foxRequest('GET', '/api/status'),
    ];
    await processStarterCalled.future;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    requests.addAll(
      List<Future<Map<String, dynamic>>>.generate(
        7,
        (_) => backend.foxRequest('GET', '/api/status'),
      ),
    );
    await Future.wait(requests);

    expect(startCount, 1);
  });

  test('failed startup kills its child and a later request starts cleanly', () async {
    var startCount = 0;
    final backend = DesktopBackend.forTesting(
      foxExecutableForTesting: executable.path,
      foxDataDirectoryForTesting: tempDir.path,
      foxProcessStarterForTesting: (
        executable,
        arguments, {
        workingDirectory,
        required mode,
      }) async {
        startCount++;
        final process = _FakeProcess();
        processes.add(process);
        if (startCount == 2) {
          await serveConfiguredPort('retry-token');
          await File('${tempDir.path}${Platform.pathSeparator}local-api.token')
              .writeAsString('retry-token');
        }
        return process;
      },
      foxStartupAttemptsForTesting: 2,
      foxStartupDelayForTesting: const Duration(milliseconds: 1),
    );

    await expectLater(
      backend.foxRequest('GET', '/api/status'),
      throwsA(isA<BackendException>()),
    );
    expect(processes.first.wasKilled, isTrue);

    await backend.foxRequest('GET', '/api/status');
    expect(startCount, 2);
  });
}

class _FakeProcess implements Process {
  final _exitCode = Completer<int>();
  final _stdinController = StreamController<List<int>>();
  late final IOSink _stdin = IOSink(_stdinController);

  bool wasKilled = false;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  int get pid => 1;

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  IOSink get stdin => _stdin;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    wasKilled = true;
    if (!_exitCode.isCompleted) _exitCode.complete(137);
    unawaited(_stdin.close());
    return true;
  }
}
