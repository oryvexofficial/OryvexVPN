import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import 'core/backend.dart';
import 'core/controller.dart';
import 'core/internet_check.dart';
import 'core/update_service.dart';
import 'ui/home_page.dart';
import 'ui/logs_page.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';
import 'ui/widgets/brand.dart';
import 'ui/widgets/motion.dart';

/// Boots OryvexVPN on [backend]. Each app (desktop-src, android-src) calls this from main(),
/// after `WidgetsFlutterBinding.ensureInitialized()`.
Future<void> runOryvex(CoreBackend backend) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    // Draw behind the status and navigation bars (Android 15 enforces it anyway); the pages pad
    // themselves with the system insets.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ));
  }
  Ox.setDarkMode(true);
  final controller = CoreController(backend);
  await controller.init();
  final updates = UpdateService(controller);
  await updates.init();
  runApp(OryvexApp(controller: controller, updates: updates));
}

class OryvexApp extends StatefulWidget {
  const OryvexApp({super.key, required this.controller, required this.updates});

  final CoreController controller;
  final UpdateService updates;

  @override
  State<OryvexApp> createState() => _OryvexAppState();
}

class _OryvexAppState extends State<OryvexApp> with WindowListener {
  bool? _lastDark;

  /// Marks every element for a rebuild, so widgets that read the Ox palette while they build
  /// (const ones included, which Flutter would otherwise skip) pick up the new appearance.
  static void _rebuildAll(Element e) {
    e.markNeedsBuild();
    e.visitChildren(_rebuildAll);
  }
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final SystemTray _systemTray = SystemTray();
  bool _trayReady = false;
  bool _closeDialogOpen = false;
  bool _offlineDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_checkInternetAndShowDialog()));
    if (Platform.isWindows) {
      windowManager.addListener(this);
      unawaited(_initTray());
    }
  }

  Future<void> _checkInternetAndShowDialog() async {
    if (!mounted || _offlineDialogOpen) return;
    final online = await hasInternetAccess();
    if (!mounted || online || _offlineDialogOpen) return;
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    _offlineDialogOpen = true;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Internet connection unavailable',
      barrierColor: Colors.black.withValues(alpha: 0.58),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) => _OfflineDialog(
        onRetry: hasInternetAccess,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(curved), child: child),
        );
      },
    );
    _offlineDialogOpen = false;
  }

  Future<void> _initTray() async {
    try {
      final exe = File(Platform.resolvedExecutable).parent.path;
      final icon = '$exe\\data\\flutter_assets\\assets\\app_icon.ico';
      await _systemTray.initSystemTray(iconPath: icon, toolTip: 'OryvexVPN');
      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: 'Show OryvexVPN', onClicked: (_) => unawaited(_showWindow())),
        MenuSeparator(),
        MenuItemLabel(label: 'Quit OryvexVPN', onClicked: (_) => unawaited(_quitFromTray())),
      ]);
      await _systemTray.setContextMenu(menu);
      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) unawaited(_showWindow());
        if (eventName == kSystemTrayEventRightClick) unawaited(_systemTray.popUpContextMenu());
      });
      _trayReady = true;
    } catch (_) {
      _trayReady = false;
      // Started hidden (--background) but no tray to come back from: show the window.
      if (!await windowManager.isVisible()) unawaited(_showWindow());
    }
  }

  Future<void> _quitFromTray() async {
    await widget.controller.shutdown();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  @override
  void onWindowClose() => unawaited(_askCloseChoice());

  Future<void> _askCloseChoice() async {
    final context = _navigatorKey.currentContext;
    if (context == null || !mounted || _closeDialogOpen) return;
    // A remembered choice from Settings skips the question.
    final remembered = widget.controller.settings.closeAction;
    if (remembered == 'quit' || (remembered == 'tray' && _trayReady)) {
      await _applyCloseChoice(remembered);
      return;
    }
    _closeDialogOpen = true;
    final choice = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close options',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) => _CloseChoiceDialog(trayReady: _trayReady),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(opacity: curved, child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(curved), child: child));
      },
    );
    _closeDialogOpen = false;
    if (choice != null) await _applyCloseChoice(choice);
  }

  Future<void> _applyCloseChoice(String choice) async {
    if (choice == 'tray' && _trayReady) {
      await windowManager.hide();
    } else if (choice == 'quit') {
      await widget.controller.shutdown();
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) windowManager.removeListener(this);
    widget.updates.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([widget.controller, widget.updates]),
      builder: (context, _) {
        final dark = widget.controller.settings.darkTheme;
        Ox.setDarkMode(dark);
        if (_lastDark != null && _lastDark != dark) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) (context as Element).visitChildren(_rebuildAll);
          });
        }
        _lastDark = dark;
        if (Platform.isAndroid) {
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          ));
        }
        final selectedTheme = buildOxTheme(dark: dark);
        return MaterialApp(
          title: kAppName,
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          // Build one selected palette and pin it to both platform brightnesses. Ox is a
          // shared token set used by custom-painted widgets, so building separate light/dark
          // themes here would leave the last palette built active for both modes.
          theme: selectedTheme,
          darkTheme: selectedTheme,
          themeMode: ThemeMode.light,
          home: Platform.isWindows
              ? DragToResizeArea(child: Shell(controller: widget.controller, updates: widget.updates))
              : Shell(controller: widget.controller, updates: widget.updates),
        );
      },
    );
  }
}

class _OfflineDialog extends StatefulWidget {
  const _OfflineDialog({required this.onRetry});

  final Future<bool> Function() onRetry;

  @override
  State<_OfflineDialog> createState() => _OfflineDialogState();
}

class _OfflineDialogState extends State<_OfflineDialog> {
  bool _checking = false;
  String? _status;

  Future<void> _retry() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _status = null;
    });
    final online = await widget.onRetry();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _status = online ? null : 'Still offline. Check your connection and try again.';
    });
    if (online) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 410),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Ox.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Ox.hairlineSoft),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.38), blurRadius: 48, offset: const Offset(0, 20))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: Ox.danger.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(15)),
                child: const Icon(Icons.wifi_off_rounded, color: Ox.danger, size: 25),
              ),
              const SizedBox(height: 18),
              Text('No internet connection', style: Ox.headline(22)),
              const SizedBox(height: 8),
              Text(
                'OryvexVPN can’t reach the internet. Check your network connection, then try again.',
                style: Ox.body(14, color: Ox.secondary),
              ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(_status!, style: Ox.body(13, color: Ox.warn)),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _checking ? null : () => Navigator.of(context).pop(),
                    child: Text('Continue offline', style: Ox.body(14, color: Ox.secondary, weight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _checking ? null : _retry,
                    icon: _checking
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(_checking ? 'Checking…' : 'Try again'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseChoiceDialog extends StatelessWidget {
  const _CloseChoiceDialog({required this.trayReady});
  final bool trayReady;

  @override
  Widget build(BuildContext context) {
    final options = <Widget>[
      if (trayReady)
        _CloseOption(icon: Icons.dock_rounded, title: 'Keep running in the system tray', subtitle: 'Hide this window and leave OryvexVPN running', value: 'tray'),
      _CloseOption(icon: Icons.power_settings_new_rounded, title: 'Quit OryvexVPN', subtitle: 'Disconnect your VPN and close the app', value: 'quit'),
      _CloseOption(icon: Icons.arrow_back_rounded, title: 'Cancel', subtitle: 'Return to OryvexVPN', value: 'cancel'),
    ];
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 390,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Ox.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: Ox.hairlineSoft), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 48, offset: const Offset(0, 20))]),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Close OryvexVPN?', style: Ox.headline(22)),
            const SizedBox(height: 7),
            Text('Choose what happens to your VPN connection.', style: Ox.body(14, color: Ox.secondary)),
            const SizedBox(height: 18),
            ...options.map((option) => Padding(padding: const EdgeInsets.only(top: 8), child: option)),
          ]),
        ),
      ),
    );
  }
}

class _CloseOption extends StatelessWidget {
  const _CloseOption({required this.icon, required this.title, required this.subtitle, required this.value});
  final IconData icon;
  final String title, subtitle, value;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: () => Navigator.of(context).pop(value == 'cancel' ? null : value),
    child: Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: Ox.nav, borderRadius: BorderRadius.circular(14), border: Border.all(color: Ox.hairlineSoft)),
      child: Row(children: [
        Icon(icon, color: Ox.blue, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Ox.body(14, weight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(subtitle, style: Ox.body(12, color: Ox.secondary)),
        ])),
        Icon(Icons.chevron_right_rounded, color: Ox.secondary, size: 19),
      ]),
    ),
  );
}

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _destinations = <_Dest>[
  _Dest(Icons.shield_outlined, Icons.shield_rounded, 'Connect'),
  _Dest(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Activity'),
  _Dest(Icons.tune_outlined, Icons.tune_rounded, 'Settings'),
];

/// How the three pages are reached at the current size.
///  * rail: a sidebar on the left (desktop and tablets 900 px and wider);
///  * top: a compact bar with icon tabs (narrow desktop windows, mid-size tablets);
///  * bottom: a floating tab bar within thumb reach (phones).
enum _NavStyle { rail, top, bottom }

/// The frame around the three pages: navigation, the Windows caption, the update notice, and a
/// shared-axis transition between pages that keeps each page's state.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.controller, required this.updates});

  final CoreController controller;
  final UpdateService updates;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  String? _dismissedUpdateVersion;

  void _go(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
  }

  Widget _updateBanner(String version, {required bool rail, required double topInset}) {
    final side = rail ? 24.0 : 12.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(side, 10 + topInset, side, 0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: HomePage.maxContent),
          child: _UpdateAvailableBanner(
            version: version,
            onOpen: () => unawaited(widget.updates.openDownload()),
            onDismiss: () => setState(() => _dismissedUpdateVersion = version),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final updates = widget.updates;
    final latest = updates.latest;
    final String? updateVersion =
        updates.shouldNotify && latest != null && _dismissedUpdateVersion != latest.version ? latest.version : null;

    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    final style = width >= 900
        ? _NavStyle.rail
        : (c.backend.isAndroid && width < 760 ? _NavStyle.bottom : _NavStyle.top);
    final hasTopBar = style == _NavStyle.top || (style == _NavStyle.rail && Platform.isWindows);

    final pages = <Widget>[
      HomePage(controller: c, onOpenActivity: () => _go(1), showHeader: style == _NavStyle.bottom),
      LogsPage(controller: c),
      SettingsPage(controller: c),
    ];

    final Widget? banner = updateVersion == null
        ? null
        : _updateBanner(updateVersion, rail: style == _NavStyle.rail, topInset: hasTopBar ? 0 : mq.padding.top);

    // The bars above the pages already sit below the status bar, so the pages drop that inset;
    // the floating tab bar sits over the pages, so they reserve room for it at the bottom.
    final pageData = mq.copyWith(
      padding: mq.padding.copyWith(
        top: hasTopBar || banner != null ? 0 : mq.padding.top,
        bottom: style == _NavStyle.bottom ? mq.padding.bottom + Ox.tabBarHeight + 20 : mq.padding.bottom,
      ),
    );
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: Ox.fast,
          reverseDuration: Ox.fast,
          switchInCurve: Ox.easeOut,
          switchOutCurve: Ox.easeIn,
          transitionBuilder: (child, animation) {
            final curved = CurvedAnimation(parent: animation, curve: Ox.easeOut, reverseCurve: Ox.easeIn);
            return SizeTransition(
              sizeFactor: curved,
              axisAlignment: -1,
              child: FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, -0.06), end: Offset.zero).animate(curved),
                  child: child,
                ),
              ),
            );
          },
          child: banner == null
              ? const SizedBox.shrink(key: ValueKey<String>('update-banner-hidden'))
              : KeyedSubtree(
                  key: ValueKey<String>('update-banner-${updateVersion ?? ''}'),
                  child: banner,
                ),
        ),
        Expanded(
          child: MediaQuery(data: pageData, child: PageSwitcher(index: _tab, children: pages)),
        ),
      ],
    );

    final Widget body = switch (style) {
      _NavStyle.rail => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SideNav(controller: c, index: _tab, onSelect: _go),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (Platform.isWindows) _TitleBar(title: _destinations[_tab].label),
                  Expanded(child: content),
                ],
              ),
            ),
          ],
        ),
      _NavStyle.top => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TopBar(controller: c, index: _tab, onSelect: _go, topInset: mq.padding.top, width: width),
            Expanded(child: content),
          ],
        ),
      _NavStyle.bottom => Stack(
          children: [
            Positioned.fill(child: content),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _TabBar(index: _tab, onSelect: _go, bottomInset: mq.padding.bottom),
            ),
          ],
        ),
    };

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () => _go(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () => _go(2),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Ox.canvas,
          body: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Ox.easeOut,
            builder: (context, v, child) => Opacity(
              opacity: v,
              child: Transform.scale(scale: 0.985 + 0.015 * v, child: child),
            ),
            child: body,
          ),
        ),
      ),
    );
  }
}

/// The desktop sidebar: brand, the three pages, and a live connection card with its own
/// Connect / Disconnect button, so the tunnel can be controlled from any page.
class _SideNav extends StatelessWidget {
  const _SideNav({required this.controller, required this.index, required this.onSelect});

  final CoreController controller;
  final int index;
  final ValueChanged<int> onSelect;

  static const width = 244.0;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    Widget brand = Container(
      height: pad.top + Ox.navHeight,
      padding: EdgeInsets.only(top: pad.top, left: 20, right: 12),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const OxMark(size: 26),
          const SizedBox(width: 10),
          Flexible(child: OxWordmark(size: 18)),
        ],
      ),
    );
    if (Platform.isWindows) brand = DragToMoveArea(child: brand);
    final desktop = !controller.backend.isAndroid;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Ox.nav,
        border: Border(right: BorderSide(color: Ox.hairlineSoft, width: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          brand,
          const SizedBox(height: 12),
          for (var i = 0; i < _destinations.length; i++)
            _SideNavItem(
              dest: _destinations[i],
              selected: i == index,
              shortcut: desktop ? 'Ctrl ${i + 1}' : null,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => _SideStatus(controller: controller),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(22, 12, 22, 16 + pad.bottom),
            child: Text('Version $kAppVersion', style: Ox.body(13, color: Ox.tertiary)),
          ),
        ],
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  const _SideNavItem({required this.dest, required this.selected, required this.onTap, this.shortcut});

  final _Dest dest;
  final bool selected;
  final VoidCallback onTap;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Pressable(
        onTap: onTap,
        scale: 0.98,
        semanticLabel: dest.label,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: Ox.medium,
          curve: Ox.easeOut,
          height: 44,
          padding: const EdgeInsets.only(left: 6, right: 12),
          decoration: BoxDecoration(
            color: selected ? Ox.blueWash : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: Ox.medium,
                curve: Ox.easeOut,
                width: 3,
                height: selected ? 18 : 0,
                decoration: BoxDecoration(color: Ox.blue, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 9),
              Icon(selected ? dest.selectedIcon : dest.icon, size: 20, color: selected ? Ox.link : Ox.secondary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  dest.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ox.body(15,
                      weight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? Ox.text : Ox.secondary),
                ),
              ),
              if (shortcut != null) Text(shortcut!, style: Ox.code(12, color: Ox.tertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The sidebar's connection card: state, route, and the one action.
class _SideStatus extends StatelessWidget {
  const _SideStatus({required this.controller});

  final CoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final stopped = c.state == CoreState.stopped;
    final label = switch (c.state) {
      CoreState.stopped => 'Connect',
      CoreState.connected => 'Disconnect',
      CoreState.stopping => 'Disconnecting',
      _ => 'Cancel',
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Ox.tile,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Ox.hairlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StatusPill(state: c.state, vpnUp: c.vpnUp, dense: true),
          const SizedBox(height: 10),
          Text(c.routeLabel, maxLines: 2, overflow: TextOverflow.ellipsis, style: Ox.body(13, color: Ox.secondary)),
          const SizedBox(height: 12),
          Pressable(
            onTap: c.canToggle ? c.toggle : null,
            semanticLabel: label,
            borderRadius: BorderRadius.circular(99),
            child: AnimatedContainer(
              duration: Ox.medium,
              curve: Ox.easeInOut,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: stopped ? Ox.blueCta : Ox.tileHi,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(label,
                  style: Ox.body(14, weight: FontWeight.w600, color: stopped ? Colors.white : Ox.text)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Windows caption above the pages in the sidebar layout: the page name, room to drag the
/// window, and the caption buttons.
class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return DragToMoveArea(
      child: Container(
        height: Ox.navHeight,
        padding: const EdgeInsets.only(left: 24),
        decoration: BoxDecoration(
          color: Ox.canvas,
          border: Border(bottom: BorderSide(color: Ox.hairlineSoft, width: 0.6)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ox.body(14, weight: FontWeight.w600, color: Ox.secondary)),
            ),
            const _WindowControls(),
          ],
        ),
      ),
    );
  }
}

/// The compact top bar for narrow windows: brand, icon tabs (with labels once there is room),
/// the connection dot, and on Windows the caption buttons. Nothing in it can overflow: the tabs
/// scale down before anything is clipped.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.controller,
    required this.index,
    required this.onSelect,
    required this.topInset,
    required this.width,
  });

  final CoreController controller;
  final int index;
  final ValueChanged<int> onSelect;
  final double topInset;
  final double width;

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      height: topInset + Ox.navHeight,
      padding: EdgeInsets.only(top: topInset, left: width < 460 ? 12 : 18, right: Platform.isWindows ? 0 : 14),
      decoration: BoxDecoration(
        color: Ox.nav,
        border: Border(bottom: BorderSide(color: Ox.hairlineSoft, width: 0.6)),
      ),
      child: Row(
        children: [
          const OxMark(size: 22),
          if (width >= 520) ...[
            const SizedBox(width: 9),
            OxWordmark(size: 17),
          ],
          const SizedBox(width: 12),
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _NavTabs(index: index, onSelect: onSelect, compact: width < 760),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) =>
                StatusPill(state: controller.state, vpnUp: controller.vpnUp, dense: true, showLabel: false),
          ),
          if (Platform.isWindows) ...[
            const SizedBox(width: 10),
            Container(width: 1, height: 20, color: Ox.hairlineSoft),
            const SizedBox(width: 4),
            _WindowControls(compact: width < 520),
          ],
        ],
      ),
    );
    return Platform.isWindows ? DragToMoveArea(child: bar) : bar;
  }
}

/// The page switcher in the top bar: a capsule of tabs, icons only when space is short.
class _NavTabs extends StatelessWidget {
  const _NavTabs({required this.index, required this.onSelect, required this.compact});

  final int index;
  final ValueChanged<int> onSelect;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < _destinations.length; i++) {
      final d = _destinations[i];
      final selected = i == index;
      Widget item = Pressable(
        onTap: () => onSelect(i),
        scale: 0.95,
        semanticLabel: d.label,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: Ox.medium,
          curve: Ox.easeOut,
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 14),
          decoration: BoxDecoration(
            color: selected ? Ox.tileTop : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(selected ? d.selectedIcon : d.icon, size: 18, color: selected ? Ox.link : Ox.secondary),
              if (!compact) ...[
                const SizedBox(width: 7),
                Text(
                  d.label,
                  style: Ox.body(14,
                      weight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? Ox.text : Ox.secondary),
                ),
              ],
            ],
          ),
        ),
      );
      if (compact) item = Tooltip(message: d.label, child: item);
      items.add(item);
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Ox.field,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Ox.hairlineSoft),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: items),
    );
  }
}

/// A compact, non-blocking update notice pinned beneath the app's top bar.
class _UpdateAvailableBanner extends StatelessWidget {
  const _UpdateAvailableBanner({
    required this.version,
    required this.onOpen,
    required this.onDismiss,
  });

  final String version;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  static const _background = Color(0xFFFFF1C2);
  static const _border = Color(0xFFFFD166);
  static const _ink = Color(0xFF3B2A00);
  static const _muted = Color(0xFF6B4E00);
  static const _accent = Color(0xFFB45309);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _border.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.new_releases_rounded, color: _accent, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Update available',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ox.body(14, color: _ink, weight: FontWeight.w700),
                ),
                Text(
                  'Version $version is ready',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Ox.body(12, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.download_rounded, size: 17),
            label: const Text('Update'),
            style: TextButton.styleFrom(
              foregroundColor: _ink,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 38),
              textStyle: Ox.body(13, color: _ink, weight: FontWeight.w700),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss update notice',
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.close_rounded, color: _muted, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Frosted glass: whatever scrolls underneath shows through, blurred.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.borderRadius = BorderRadius.zero});

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: child,
      ),
    );
  }
}

class _WindowControls extends StatefulWidget {
  const _WindowControls({this.compact = false});
  final bool compact;
  @override
  State<_WindowControls> createState() => _WindowControlsState();
}

/// OryvexVPN's own caption buttons. The native Windows title bar is hidden, so these replace
/// it: flush with the window edge, full bar height, hand-drawn hairline glyphs, a red close.
/// The maximise glyph follows the real window state, and everything dims while unfocused.
class _WindowControlsState extends State<_WindowControls> with WindowListener {
  bool _maximized = false;
  bool _focused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncMaximized());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    final value = await windowManager.isMaximized();
    if (mounted && value != _maximized) setState(() => _maximized = value);
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);
  @override
  void onWindowRestore() => unawaited(_syncMaximized());
  @override
  void onWindowFocus() => setState(() => _focused = true);
  @override
  void onWindowBlur() => setState(() => _focused = false);

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _syncMaximized();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: Ox.fast,
    opacity: _focused ? 1 : 0.55,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _CaptionButton(glyph: _Glyph.minimize, label: 'Minimize', onPressed: windowManager.minimize, compact: widget.compact),
      _CaptionButton(
        glyph: _maximized ? _Glyph.restore : _Glyph.maximize,
        label: _maximized ? 'Restore down' : 'Maximize',
        onPressed: _toggleMaximize,
        compact: widget.compact,
      ),
      // close() goes through setPreventClose, so the "Close OryvexVPN?" dialog still asks.
      _CaptionButton(glyph: _Glyph.close, label: 'Close', onPressed: windowManager.close, close: true, compact: widget.compact),
    ]),
  );
}

enum _Glyph { minimize, maximize, restore, close }

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({required this.glyph, required this.label, required this.onPressed, this.close = false, this.compact = false});
  final _Glyph glyph;
  final String label;
  final VoidCallback onPressed;
  final bool close;
  final bool compact;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  static const _closeRed = Color(0xFFE81123); // the Windows close-button red
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    if (widget.close) {
      fill = _down ? const Color(0xFFF1707A) : (_hover ? _closeRed : Colors.transparent);
    } else {
      fill = _down ? Ox.text.withValues(alpha: 0.14) : (_hover ? Ox.text.withValues(alpha: 0.08) : Colors.transparent);
    }
    final ink = widget.close && (_hover || _down) ? Colors.white : Ox.text;
    return Semantics(
      button: true,
      label: widget.label,
      child: Tooltip(
        message: widget.label,
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() { _hover = false; _down = false; }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _down = true),
            onTapCancel: () => setState(() => _down = false),
            onTap: () {
              setState(() => _down = false);
              widget.onPressed();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: widget.compact ? 34 : 46,
              height: Ox.navHeight,
              color: fill,
              alignment: Alignment.center,
              child: CustomPaint(size: const Size(10, 10), painter: _GlyphPainter(widget.glyph, ink)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline caption glyphs, drawn rather than taken from an icon font so they stay crisp at
/// every scale and match the 1 px weight of the Windows 11 caption.
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);
  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..isAntiAlias = true;
    final w = size.width, h = size.height;
    switch (glyph) {
      case _Glyph.minimize:
        canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), p);
      case _Glyph.maximize:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0.5, 0.5, w - 1, h - 1), const Radius.circular(1.5)), p);
      case _Glyph.restore:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0.5, 2.5, w - 3, h - 3), const Radius.circular(1.2)), p);
        final back = Path()
          ..moveTo(2.5, 2.5)
          ..lineTo(2.5, 0.5)
          ..lineTo(w - 0.5, 0.5)
          ..lineTo(w - 0.5, h - 2.5)
          ..lineTo(w - 2.5, h - 2.5);
        canvas.drawPath(back, p);
      case _Glyph.close:
        canvas.drawLine(Offset.zero, Offset(w, h), p);
        canvas.drawLine(Offset(w, 0), Offset(0, h), p);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onSelect, required this.bottomInset});

  final int index;
  final ValueChanged<int> onSelect;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottomInset + 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 28, offset: const Offset(0, 10)),
              ],
            ),
            child: _Glass(
              borderRadius: BorderRadius.circular(32),
              child: Container(
                height: Ox.tabBarHeight,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Ox.nav,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Ox.hairlineSoft, width: 0.8),
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final seg = box.maxWidth / _destinations.length;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: context.reduceMotion ? Duration.zero : Ox.medium,
                          curve: Ox.easeOut,
                          left: seg * index,
                          top: 0,
                          bottom: 0,
                          width: seg,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Ox.blueWash,
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < _destinations.length; i++)
                              Expanded(
                                child: Pressable(
                                  onTap: () => onSelect(i),
                                  scale: 0.92,
                                  semanticLabel: _destinations[i].label,
                                  borderRadius: BorderRadius.circular(26),
                                  child: _TabItem(dest: _destinations[i], selected: i == index),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.dest, required this.selected});

  final _Dest dest;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Ox.link : Ox.secondary;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedScale(
          scale: selected ? 1.08 : 1.0,
          duration: Ox.medium,
          curve: Ox.easeOut,
          child: AnimatedSwitcher(
            duration: Ox.fast,
            child: Icon(
              selected ? dest.selectedIcon : dest.icon,
              key: ValueKey<bool>(selected),
              size: 22,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 3),
        AnimatedDefaultTextStyle(
          duration: Ox.fast,
          style: Ox.body(12, weight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? Ox.text : Ox.secondary, height: 1.1),
          child: Text(dest.label),
        ),
      ],
    );
  }
}
