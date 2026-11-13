import 'package:flutter/widgets.dart';
import 'package:oryvex_shared/oryvex_shared.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main(List<String> args) async {
  // Started at Windows sign-in with "Start in tray": stay in the tray, no window.
  final background = args.contains('--background');
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // The native Windows caption is replaced by OryvexVPN's own title bar (see _TopBar and _TitleBar in
  // oryvex_shared). Applying the style through waitUntilReadyToShow makes it stick before the
  // first visible frame, so the default grey Windows bar never appears.
  const options = WindowOptions(
    title: 'OryvexVPN',
    // Wide enough for the sidebar layout; the UI adapts down to the minimum size.
    size: Size(1120, 760),
    minimumSize: Size(420, 600),
    center: true,
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    backgroundColor: Color(0xFF0B0D12),
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setPreventClose(true);
    await windowManager.setResizable(true);
    if (!background) {
      await windowManager.show();
      await windowManager.focus();
    }
  });
  await runOryvex(DesktopBackend());
}
