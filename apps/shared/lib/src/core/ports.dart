import 'dart:io';

/// The ports of [ports] something else is still listening on. Binding and closing at once is
/// the only portable way to ask; an old core that is still shutting down shows up here too.
Future<List<String>> busyPorts(Map<String, int> ports, {required bool shareLan}) async {
  final host = shareLan ? InternetAddress.anyIPv4 : InternetAddress.loopbackIPv4;
  final busy = <String>[];
  for (final e in ports.entries) {
    try {
      final s = await ServerSocket.bind(host, e.value);
      await s.close();
    } on SocketException {
      busy.add('${e.key} ${e.value}');
    } catch (_) {
      // Anything else (sandboxing, odd stacks) is the core's to report.
    }
  }
  return busy;
}

/// Waits up to [within] for every port to come free. Returns the ones still busy.
Future<List<String>> waitForPorts(Map<String, int> ports,
    {required bool shareLan, Duration within = const Duration(seconds: 4)}) async {
  final until = DateTime.now().add(within);
  var busy = await busyPorts(ports, shareLan: shareLan);
  while (busy.isNotEmpty && DateTime.now().isBefore(until)) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    busy = await busyPorts(ports, shareLan: shareLan);
  }
  return busy;
}
