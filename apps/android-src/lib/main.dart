import 'package:flutter/widgets.dart';
import 'package:oryvex_shared/oryvex_shared.dart';

Future<void> main() async {
  // Bindings first: the backend talks to the platform, which needs them to exist.
  WidgetsFlutterBinding.ensureInitialized();
  await runOryvex(AndroidBackend());
}
