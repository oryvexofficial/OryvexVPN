import 'package:flutter_test/flutter_test.dart';
import 'package:oryvex_shared/oryvex_shared.dart';

void main() {
  test('settings round-trip', () {
    final s = CoreSettings()..protocol = 'wg';
    expect(CoreSettings.fromJson(s.toJson()).protocol, 'wg');
  });
}
