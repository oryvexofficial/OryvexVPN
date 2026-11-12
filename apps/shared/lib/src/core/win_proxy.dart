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

  static bool get hasBackup => File(_backupPath).existsSync();

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
      final rc = fn(key, n, nullptr, type, data, size);
      if (rc == 2) return null; // ERROR_FILE_NOT_FOUND is the only valid "unset" case.
      if (rc != 0) throw StateError('Could not read Windows proxy value $name (error $rc).');
      if (type.value == _regDword) return data.cast<Uint32>().value;
      if (type.value == _regSz || type.value == 2) {
        return data.cast<Utf16>().toDartString();
      }
      throw StateError('Windows proxy value $name has an unsupported registry type.');
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

  static bool _delete(int key, String name) {
    final fn = _adv.lookupFunction<_RegDeleteValueN, _RegDeleteValueD>('RegDeleteValueW');
    final n = name.toNativeUtf16();
    try {
      final rc = fn(key, n);
      return rc == 0 || rc == 2; // Missing is already the requested state.
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
      final backupFile = File(_backupPath);
      // A previous run may have died while the proxy was enabled. Never overwrite its recovery
      // record with the Oryvex proxy; recover the original first or leave this run's proxy off.
      if (backupFile.existsSync() && !restore()) return false;

      final key = _open(_keyQuery | _keySet);
      if (key == null) return false;
      var ok = false;
      try {
        final enabled = _query(key, 'ProxyEnable');
        final server = _query(key, 'ProxyServer');
        final override = _query(key, 'ProxyOverride');
        if (enabled != null && enabled is! int) {
          throw StateError('Windows ProxyEnable is not a DWORD.');
        }
        if (server != null && server is! String) {
          throw StateError('Windows ProxyServer is not a string.');
        }
        if (override != null && override is! String) {
          throw StateError('Windows ProxyOverride is not a string.');
        }

        backupFile.parent.createSync(recursive: true);
        final pendingBackup = File('${backupFile.path}.tmp');
        final backupData = jsonEncode({
          'ProxyEnable': enabled,
          'ProxyServer': server,
          'ProxyOverride': override,
        });
        final backupHandle = pendingBackup.openSync(mode: FileMode.write);
        try {
          backupHandle.writeStringSync(backupData);
          backupHandle.flushSync();
        } finally {
          backupHandle.closeSync();
        }
        pendingBackup.renameSync(backupFile.path);
        ok = _setString(key, 'ProxyServer', hostPort) &&
            _setString(key, 'ProxyOverride',
                'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>') &&
            _setDword(key, 'ProxyEnable', 1);
        _broadcast();
      } finally {
        _close(key);
      }
      if (!ok) {
        restore();
        return false;
      }
      return true;
    } catch (_) {
      restore();
      return false;
    }
  }

  /// Puts back whatever was there before [enable]. Safe to call any number of times.
  /// The recovery record is kept until the registry matches the saved state exactly.
  static bool restore() {
    if (!Platform.isWindows) return true;
    final backupFile = File(_backupPath);
    if (!backupFile.existsSync()) return true;
    try {
      final saved = jsonDecode(backupFile.readAsStringSync()) as Map<String, dynamic>;
      if (!saved.containsKey('ProxyEnable') ||
          !saved.containsKey('ProxyServer') ||
          !saved.containsKey('ProxyOverride')) {
        return false;
      }
      final rawEnable = saved['ProxyEnable'];
      if (rawEnable != null && rawEnable is! int) return false;
      final enable = rawEnable is int ? rawEnable : 0;
      final enablePresent = rawEnable is int;
      final server = saved['ProxyServer'];
      final override = saved['ProxyOverride'];
      if ((server != null && server is! String) ||
          (override != null && override is! String)) {
        return false;
      }

      final key = _open(_keyQuery | _keySet);
      if (key == null) return false;
      var writesOk = false;
      try {
        final serverOk = server is String
            ? _setString(key, 'ProxyServer', server)
            : _delete(key, 'ProxyServer');
        final overrideOk = override is String
            ? _setString(key, 'ProxyOverride', override)
            : _delete(key, 'ProxyOverride');
        // Restore the enable flag last, so the app's proxy is not briefly active while the
        // previous server and bypass list are being put back.
        final enableOk = enablePresent
            ? _setDword(key, 'ProxyEnable', enable)
            : _delete(key, 'ProxyEnable');
        writesOk = serverOk && overrideOk && enableOk;
        _broadcast();
      } finally {
        _close(key);
      }

      if (!writesOk) return false;
      final verifyKey = _open(_keyQuery);
      if (verifyKey == null) return false;
      var matches = false;
      try {
        matches = _query(verifyKey, 'ProxyEnable') == (enablePresent ? enable : null) &&
            _query(verifyKey, 'ProxyServer') == server &&
            _query(verifyKey, 'ProxyOverride') == override;
      } finally {
        _close(verifyKey);
      }
      if (!matches) return false;

      backupFile.deleteSync();
      return true;
    } catch (_) {
      // Do not discard the only copy of the user's prior proxy settings. Startup and shutdown
      // will retry; a future enable is also blocked until recovery succeeds.
      return false;
    }
  }
}
