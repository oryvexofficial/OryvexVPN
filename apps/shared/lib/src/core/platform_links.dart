import 'dart:io';

import 'package:flutter/services.dart';

/// Opens [url] in the default browser. Returns false when nothing could take it.
Future<bool> openExternal(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) return false;
  try {
    if (Platform.isAndroid) {
      return await const MethodChannel('oryvexcore/core').invokeMethod<bool>('openUrl', {'url': url}) ?? false;
    }
    if (Platform.isWindows) {
      // rundll32 hands the URL to the shell without a console window or cmd quoting rules.
      final r = await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      return r.exitCode == 0;
    }
    if (Platform.isMacOS) return (await Process.run('open', [url])).exitCode == 0;
    if (Platform.isLinux) return (await Process.run('xdg-open', [url])).exitCode == 0;
  } catch (_) {}
  return false;
}

/// The CPU ABIs this Android device runs, best first ("arm64-v8a", "armeabi-v7a", ...).
/// Empty on desktop or when the platform does not say.
Future<List<String>> androidAbis() async {
  if (!Platform.isAndroid) return const [];
  try {
    final info = await const MethodChannel('oryvexcore/core').invokeMapMethod<String, Object?>('deviceInfo');
    final abis = info?['abis'];
    if (abis is List) return [for (final a in abis) if (a is String) a];
  } catch (_) {}
  return const [];
}
