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

/// "Launch at Windows sign-in": one value under HKCU\...\Run, the same one the installer writes.
/// Uses advapi32 directly (no reg.exe), so no console window ever flashes.
class WinStartup {
  WinStartup._();

  static const _hkcu = -2147483647; // HKEY_CURRENT_USER, sign-extended
  static const _keyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const valueName = 'OryvexVPN';
  static const backgroundFlag = '--background';
  static const _keyQuery = 0x0001;
  static const _keySet = 0x0002;
  static const _regSz = 1;

  static DynamicLibrary? _advapi;
  static DynamicLibrary get _adv => _advapi ??= DynamicLibrary.open('advapi32.dll');

  static int? _open(int sam) {
    final fn = _adv.lookupFunction<_RegOpenKeyExN, _RegOpenKeyExD>('RegOpenKeyExW');
    final out = calloc<IntPtr>();
    final path = _keyPath.toNativeUtf16();
    try {
      return fn(_hkcu, path, 0, sam, out) == 0 ? out.value : null;
    } finally {
      calloc.free(out);
      calloc.free(path);
    }
  }

  static void _close(int key) => _adv.lookupFunction<_RegCloseKeyN, _RegCloseKeyD>('RegCloseKey')(key);

  /// Whether OryvexVPN starts at sign-in right now (set by the app or by the installer).
  static bool isEnabled() {
    if (!Platform.isWindows) return false;
    try {
      final key = _open(_keyQuery);
      if (key == null) return false;
      final fn = _adv.lookupFunction<_RegQueryValueExN, _RegQueryValueExD>('RegQueryValueExW');
      final name = valueName.toNativeUtf16();
      final size = calloc<Uint32>()..value = 0;
      try {
        return fn(key, name, nullptr, nullptr, nullptr, size) == 0;
      } finally {
        calloc.free(name);
        calloc.free(size);
        _close(key);
      }
    } catch (_) {
      return false;
    }
  }

  /// The command line written to the Run key.
  static String commandFor(String exe, {required bool inTray}) =>
      inTray ? '"$exe" $backgroundFlag' : '"$exe"';

  /// Adds or removes the sign-in entry. Returns true when the registry now matches [enabled].
  static bool apply({required bool enabled, required bool inTray}) {
    if (!Platform.isWindows) return false;
    try {
      final key = _open(_keySet);
      if (key == null) return false;
      final name = valueName.toNativeUtf16();
      try {
        if (!enabled) {
          final del = _adv.lookupFunction<_RegDeleteValueN, _RegDeleteValueD>('RegDeleteValueW');
          final rc = del(key, name);
          return rc == 0 || rc == 2; // 2: ERROR_FILE_NOT_FOUND, already gone
        }
        final value = commandFor(Platform.resolvedExecutable, inTray: inTray).toNativeUtf16();
        try {
          final bytes = (commandFor(Platform.resolvedExecutable, inTray: inTray).length + 1) * 2;
          final set = _adv.lookupFunction<_RegSetValueExN, _RegSetValueExD>('RegSetValueExW');
          return set(key, name, 0, _regSz, value.cast<Uint8>(), bytes) == 0;
        } finally {
          calloc.free(value);
        }
      } finally {
        calloc.free(name);
        _close(key);
      }
    } catch (_) {
      return false;
    }
  }
}
