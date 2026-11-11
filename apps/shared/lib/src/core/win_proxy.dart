import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _RegOpenKeyExN = Int32 Function(
    IntPtr hKey, Pointer<Utf16> subKey, Uint32 options, Uint32 sam, Pointer<IntPtr> result);
typedef _RegOpenKeyExD = int Function(
    int hKey, Pointer<Utf16> subKey, int options, int sam, Pointer<IntPtr> result);

typedef _RegSetValueExN = Int32 Function(IntPtr hKey, Pointer<Utf16> name, Uint32 reserved,
    Uint32 type, Pointer<Uint8> data, Uint32 cbData);
typedef _RegSetValueExD = int Function(
    int hKey, Pointer<Utf16> name, int reserved, int type, Pointer<Uint8> data, int cbData);

typedef _RegQueryValueExN = Int32 Function(IntPtr hKey, Pointer<Utf16> name,
    Pointer<Uint32> reserved, Pointer<Uint32> type, Pointer<Uint8> data, Pointer<Uint32> cbData);
typedef _RegQueryValueExD = int Function(int hKey, Pointer<Utf16> name,
    Pointer<Uint32> reserved, Pointer<Uint32> type, Pointer<Uint8> data, Pointer<Uint32> cbData);

typedef _RegDeleteValueN = Int32 Function(IntPtr hKey, Pointer<Utf16> name);
typedef _RegDeleteValueD = int Function(int hKey, Pointer<Utf16> name);

typedef _RegCloseKeyN = Int32 Function(IntPtr hKey);
typedef _RegCloseKeyD = int Function(int hKey);

typedef _InternetSetOptionN = Int32 Function(
    IntPtr h, Uint32 option, Pointer<Void> buffer, Uint32 length);
typedef _InternetSetOptionD = int Function(int h, int option, Pointer<Void> buffer, int length);

/// Sets and restores the per-user WinINet proxy (what Edge, Chrome and most Windows apps follow).
/// The previous values are kept in %APPDATA%\OryvexCore\proxy-backup.json, so a crash while
/// connected is undone the next time the app opens.
class WinProxy {
  WinProxy._();

  // HKEY_CURRENT_USER is ((HKEY)(ULONG_PTR)((LONG)0x80000001)): sign-extended on 64-bit.
  static const _hkcu = -2147483647;
  static const _keyPath = r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const _keyQuery = 0x0001;
  static const _keySet = 0x0002;
  static const _regSz = 1;
  static const _regDword = 4;
  static const _optionSettingsChanged = 39;
  static const _optionRefresh = 37;

  static String get _backupPath {
    final base = Platform.environment['APPDATA'] ?? '.';
    return '$base\\OryvexCore\\proxy-backup.json';
  }

  static DynamicLibrary? _advapi;
  static DynamicLibrary? _wininet;

  static DynamicLibrary get _adv => _advapi ??= DynamicLibrary.open('advapi32.dll');
  static DynamicLibrary get _inet => _wininet ??= DynamicLibrary.open('wininet.dll');

  static int? _open(int sam) {
    final fn = _adv.lookupFunction<_RegOpenKeyExN, _RegOpenKeyExD>('RegOpenKeyExW');
    final out = calloc<IntPtr>();
    final path = _keyPath.toNativeUtf16();
    try {
      final rc = fn(_hkcu, path, 0, sam, out);
      return rc == 0 ? out.value : null;
    } finally {
      calloc.free(out);
      calloc.free(path);
    }
  }

  static void _close(int key) =>
      _adv.lookupFunction<_RegCloseKeyN, _RegCloseKeyD>('RegCloseKey')(key);

  static Object? _query(int key, String name) {
    final fn = _adv.lookupFunction<_RegQueryValueExN, _RegQueryValueExD>('RegQueryValueExW');
    final n = name.toNativeUtf16();
    final type = calloc<Uint32>();
    final size = calloc<Uint32>()..value = 4096;
    final data = calloc<Uint8>(4096);
    try {
      if (fn(key, n, nullptr, type, data, size) != 0) return null;
      if (type.value == _regDword) return data.cast<Uint32>().value;
      if (type.value == _regSz || type.value == 2) {
        return data.cast<Utf16>().toDartString();
      }
      return null;
    } finally {
      calloc.free(n);
      calloc.free(type);
      calloc.free(size);
      calloc.free(data);
    }
  }

  static bool _setDword(int key, String name, int value) {
    final fn = _adv.lookupFunction<_RegSetValueExN, _RegSetValueExD>('RegSetValueExW');
    final n = name.toNativeUtf16();
    final data = calloc<Uint32>()..value = value;
    try {
      return fn(key, n, 0, _regDword, data.cast<Uint8>(), 4) == 0;
    } finally {
      calloc.free(n);
      calloc.free(data);
    }
  }

  static bool _setString(int key, String name, String value) {
    final fn = _adv.lookupFunction<_RegSetValueExN, _RegSetValueExD>('RegSetValueExW');
    final n = name.toNativeUtf16();
    final data = value.toNativeUtf16();
    try {
      return fn(key, n, 0, _regSz, data.cast<Uint8>(), (value.length + 1) * 2) == 0;
    } finally {
      calloc.free(n);
      calloc.free(data);
    }
  }

  static void _delete(int key, String name) {
    final fn = _adv.lookupFunction<_RegDeleteValueN, _RegDeleteValueD>('RegDeleteValueW');
    final n = name.toNativeUtf16();
    try {
      fn(key, n);
    } finally {
      calloc.free(n);
    }
  }

  static void _broadcast() {
    try {
      final fn =
          _inet.lookupFunction<_InternetSetOptionN, _InternetSetOptionD>('InternetSetOptionW');
      fn(0, _optionSettingsChanged, nullptr, 0);
      fn(0, _optionRefresh, nullptr, 0);
    } catch (_) {}
  }

  /// Points the system proxy at [hostPort] (the core's HTTP proxy). Returns false on failure.
  static bool enable(String hostPort) {
    if (!Platform.isWindows) return false;
    try {
      final key = _open(_keyQuery | _keySet);
      if (key == null) return false;
      try {
        final backupFile = File(_backupPath);
        if (!backupFile.existsSync()) {
          backupFile.parent.createSync(recursive: true);
          backupFile.writeAsStringSync(jsonEncode({
            'ProxyEnable': _query(key, 'ProxyEnable'),
            'ProxyServer': _query(key, 'ProxyServer'),
            'ProxyOverride': _query(key, 'ProxyOverride'),
          }));
        }
        final ok = _setString(key, 'ProxyServer', hostPort) &&
            _setString(key, 'ProxyOverride',
                'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.2*;172.30.*;172.31.*;192.168.*;<local>') &&
            _setDword(key, 'ProxyEnable', 1);
        _broadcast();
        return ok;
      } finally {
        _close(key);
      }
    } catch (_) {
      return false;
    }
  }

  /// Puts back whatever was there before [enable]. Safe to call any number of times.
  static void restore() {
    if (!Platform.isWindows) return;
    final backupFile = File(_backupPath);
    if (!backupFile.existsSync()) return;
    try {
      final saved = jsonDecode(backupFile.readAsStringSync()) as Map<String, dynamic>;
      final key = _open(_keyQuery | _keySet);
      if (key == null) return;
      try {
        final enable = saved['ProxyEnable'];
        _setDword(key, 'ProxyEnable', enable is int ? enable : 0);
        for (final name in ['ProxyServer', 'ProxyOverride']) {
          final v = saved[name];
          if (v is String) {
            _setString(key, name, v);
          } else {
            _delete(key, name);
          }
        }
        _broadcast();
      } finally {
        _close(key);
      }
      backupFile.deleteSync();
    } catch (_) {
      // Never leave the user stuck behind a dead proxy.
      final key = _open(_keyQuery | _keySet);
      if (key != null) {
        _setDword(key, 'ProxyEnable', 0);
        _close(key);
        _broadcast();
      }
      try {
        backupFile.deleteSync();
      } catch (_) {}
    }
  }
}
