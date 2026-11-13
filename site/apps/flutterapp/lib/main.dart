import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/vexo_api.dart';
import 'pages/account_page.dart';
import 'pages/admin_page.dart';
import 'pages/auth_page.dart';
import 'pages/catalog_page.dart';
import 'pages/check_host_page.dart';
import 'pages/developers_page.dart';
import 'pages/home_page.dart';
import 'pages/models_page.dart';
import 'pages/embedded_player_page.dart' as embedded_player;
import 'pages/social_page.dart';
import 'pages/status_page.dart';
import 'widgets/vexo_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VexoApp());
}

class VexoApp extends StatefulWidget {
  const VexoApp({super.key});
  @override
  State<VexoApp> createState() => _VexoAppState();
}

class _VexoAppState extends State<VexoApp> {
  final VexoApi _api = VexoApi();
  bool _ready = false;
  bool _adult = false;
  bool _blocked = false;
  bool _signedIn = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    var adultConfirmed = false;
    try { adultConfirmed = (await SharedPreferences.getInstance()).getBool('vexostream.adult.confirmed') == true; } catch (_) {}
    String? token;
    try { token = await _api.loadToken(); } catch (_) {}
    if (!mounted) return;
    setState(() {
      _ready = true;
      _adult = adultConfirmed;
      _signedIn = (token ?? '').isNotEmpty;
    });
  }

  Future<void> _acceptAge() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('vexostream.adult.confirmed', true);
    if (mounted) setState(() => _adult = true);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'VexoStream',
        debugShowCheckedModeBanner: false,
        theme: buildVexoTheme(),
        darkTheme: buildVexoTheme(),
        themeMode: ThemeMode.dark,
        home: !_ready
            ? const _AppStartupLoader()
            : _blocked
                ? const _AgeBlockedPage()
                : !_adult
                    ? _AgeGate(onAccept: _acceptAge, onReject: () => setState(() => _blocked = true))
                    : VexoShell(api: _api, signedIn: _signedIn, onSessionChanged: (v) => setState(() => _signedIn = v)),
      );
}

class _AppStartupLoader extends StatelessWidget {
  const _AppStartupLoader();

  @override
  Widget build(BuildContext context) => Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -.15),
              radius: 1.1,
              colors: [Color(0xFF111923), Vx.bg],
            ),
          ),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Vx.panel,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Vx.line),
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 36, offset: Offset(0, 14))],
                ),
                child: const _BrandMark(size: 58),
              ),
              const SizedBox(height: 28),
              const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 2.6)),
              const SizedBox(height: 16),
              Text('Getting VexoStream ready…', style: Vx.sans(size: 14, color: Vx.text2, weight: FontWeight.w500)),
            ]),
          ),
        ),
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) => Image.asset('assets/brand/vexostream-mark-512.png', width: size, height: size, filterQuality: FilterQuality.medium);
}

class _AgeGate extends StatelessWidget {
  const _AgeGate({required this.onAccept, required this.onReject});
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.fromLTRB(34, 36, 34, 30),
            decoration: BoxDecoration(
              color: Vx.panel,
              borderRadius: BorderRadius.circular(Vx.radius2xl),
              border: Border.all(color: Vx.line),
              boxShadow: const [BoxShadow(color: Color(0xE6000000), blurRadius: 50, offset: Offset(0, 26), spreadRadius: -24)],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const _BrandMark(size: 60),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(color: Vx.red.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
                child: Text('18+', style: Vx.mono(size: 13, weight: FontWeight.w600, color: Vx.red, spacing: 1)),
              ),
              const SizedBox(height: 16),
              Text('Adults only', style: t.headlineMedium),
              const SizedBox(height: 10),
              Text(
                'VexoStream shows adult content. Continue only if you are 18 or older and it is legal where you live.',
                textAlign: TextAlign.center,
                style: t.bodyMedium?.copyWith(fontSize: 15),
              ),
              const SizedBox(height: 26),
              FilledButton(onPressed: onAccept, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)), child: const Text('I am 18 or older, enter')),
              const SizedBox(height: 10),
              TextButton(onPressed: onReject, child: Text('Leave', style: Vx.sans(size: 14, color: Vx.text3))),
            ]),
          ),
        ),
      ),
    );
  }
}

class _AgeBlockedPage extends StatelessWidget {
  const _AgeBlockedPage();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: ErrorPanel(
          title: 'VexoStream is for adults only.',
          message: 'You can close the app now.',
          icon: Icons.lock_outline_rounded,
          action: OutlinedButton(onPressed: () => exit(0), child: const Text('Close app')),
        ),
      );
}

class _AppMaintenancePage extends StatefulWidget {
  const _AppMaintenancePage({required this.api, this.onSignIn});
  final VexoApi api;
  final VoidCallback? onSignIn;
  @override
  State<_AppMaintenancePage> createState() => _AppMaintenancePageState();
}

class _AppMaintenancePageState extends State<_AppMaintenancePage> {
  bool _checking = false;
  Future<void> _checkAgain() async {
    setState(() => _checking = true);
    try { await widget.api.get('/config'); } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.build_circle_outlined, size: 52, color: Vx.amber),
              const SizedBox(height: 20),
              Text('We’ll be right back.', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text('VexoStream is getting a quick tune-up. Try again in a few minutes.', style: Vx.sans(size: 15, color: Vx.text2), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (widget.onSignIn != null) ...[
                FilledButton.icon(onPressed: widget.onSignIn, icon: const Icon(Icons.login_rounded), label: const Text('Owner / Admin log in')),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(onPressed: _checking ? null : _checkAgain, icon: const Icon(Icons.refresh_rounded), label: Text(_checking ? 'Checking…' : 'Check again')),
            ]),
          ),
        ),
      );
}

enum _Page { home, browse, models, social, developers, status, checkHost, admin, account }

class VexoShell extends StatefulWidget {
  const VexoShell({super.key, required this.api, required this.signedIn, required this.onSessionChanged});
  final VexoApi api;
  final bool signedIn;
  final ValueChanged<bool> onSessionChanged;
  @override
  State<VexoShell> createState() => _VexoShellState();
}

class _VexoShellState extends State<VexoShell> {
  _Page _page = _Page.home;
  String _query = '';
  String _provider = '';
  int _browseKey = 0;
  int _accountKey = 0;
  List<Map<String, dynamic>> _providers = [];
  String _username = '';
  bool _isAdmin = false;
  final _search = TextEditingController();

  static const _nav = [
    (_Page.home, 'Home', Icons.home_outlined, Icons.home_rounded),
    (_Page.browse, 'Browse', Icons.video_library_outlined, Icons.video_library_rounded),
    (_Page.models, 'Models', Icons.people_alt_outlined, Icons.people_alt_rounded),
    (_Page.social, 'Social media', Icons.forum_outlined, Icons.forum_rounded),
    (_Page.developers, 'Developers', Icons.code_rounded, Icons.code_rounded),
    (_Page.status, 'Status', Icons.monitor_heart_outlined, Icons.monitor_heart_rounded),
    (_Page.checkHost, 'Check host', Icons.dns_outlined, Icons.dns_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _loadProviders();
    _loadAccount();
  }

  @override
  void didUpdateWidget(covariant VexoShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signedIn != widget.signedIn) _loadAccount();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadProviders() async {
    try {
      final config = asMap(await widget.api.get('/config'));
      if (mounted) setState(() => _providers = asList(config['providers']).map(asMap).toList());
    } catch (_) {}
  }

  Future<void> _loadAccount() async {
    if (!widget.signedIn) {
      if (mounted) setState(() { _username = ''; _isAdmin = false; });
      return;
    }
    try {
      final data = asMap(await widget.api.get('/account', authenticated: true));
      final account = asMap(data['account']);
      if (!widget.signedIn) return;
      if (mounted) setState(() {
        _username = (account['username'] ?? '').toString();
        _isAdmin = account['isOwner'] == true || account['role'] == 'Owner' || account['role'] == 'Admin';
      });
      if (_isAdmin) _loadProviders();
    } on ApiException catch (e) {
      if (e.needsLogin) {
        await widget.api.clearToken();
        widget.onSessionChanged(false);
      }
    } catch (_) {}
  }

  Future<void> _openAuth({bool signup = false}) async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => AuthPage(api: widget.api, initialSignup: signup)));
    if (ok == true && mounted) {
      widget.onSessionChanged(true);
      setState(() => _accountKey++);
    }
  }

  void _openPlayer(Map<String, dynamic> video) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => embedded_player.PlayerPage(
        api: widget.api,
        video: video,
        onSignIn: () => _openAuth(),
      ),
    ));
  }

  void _browse(String provider, {String query = ''}) {
    setState(() {
      _provider = provider;
      _query = query;
      _browseKey++;
      _page = _Page.browse;
    });
  }

  void _go(_Page page) {
    if (page == _Page.browse) return _browse(_provider);
    setState(() => _page = page);
  }

  Widget _body() => switch (_page) {
        _Page.home => HomePage(api: widget.api, onPlay: _openPlayer, onBrowse: (p) => _browse(p), onSearch: (q, p) => _browse(p, query: q)),
        _Page.browse => CatalogPage(key: ValueKey('browse-$_browseKey'), api: widget.api, onPlay: _openPlayer, initialQuery: _query, initialProvider: _provider),
        _Page.models => ModelsPage(api: widget.api, onSignIn: () => _openAuth()),
        _Page.social => SocialPage(api: widget.api),
        _Page.developers => DevelopersPage(api: widget.api),
        _Page.status => StatusPage(api: widget.api),
        _Page.checkHost => CheckHostPage(api: widget.api),
        _Page.admin => AdminPage(api: widget.api, onNavigate: (destination) => setState(() {
          _page = switch (destination) {
            AdminDestination.home => _Page.home,
            AdminDestination.social => _Page.social,
            AdminDestination.status => _Page.status,
          };
        })),
        _Page.account => AccountPage(
            key: ValueKey('account-$_accountKey-${widget.signedIn}'),
            api: widget.api,
            onSignIn: () => _openAuth(),
            onOpenAdmin: () => setState(() => _page = _Page.admin),
            onSignedOut: () {
              widget.onSessionChanged(false);
              setState(() => _page = _Page.home);
              _loadProviders();
            },
          ),
      };

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth >= 1100;
        return Scaffold(
          body: Column(children: [
            _topBar(wide),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _sidebar(wide),
                Expanded(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: widget.api.maintenanceMode,
                    builder: (context, maintenance, _) => maintenance && !_isAdmin
                        ? _AppMaintenancePage(api: widget.api, onSignIn: () => _openAuth())
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Vx.ease,
                            transitionBuilder: (child, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: Tween(begin: .985, end: 1.0).animate(a), child: child)),
                            child: KeyedSubtree(key: ValueKey('${_page.name}-$_browseKey-$_accountKey'), child: _body()),
                          ),
                  ),
                ),
              ]),
            ),
          ]),
        );
      });

  Widget _topBar(bool wide) => Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: const BoxDecoration(color: Vx.bg, border: Border(bottom: BorderSide(color: Vx.line))),
        child: Row(children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => _go(_Page.home),
              child: wide ? Image.asset('assets/brand/vexostream-logo-dark.png', height: 26) : const _BrandMark(size: 30),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _search,
                    onSubmitted: (q) {
                      final query = q.trim();
                      if (query.isNotEmpty) _browse(_provider, query: query);
                    },
                    style: Vx.sans(size: 14),
                    decoration: const InputDecoration(
                      hintText: 'Search videos',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                      prefixIcon: Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.search_rounded, size: 18)),
                      prefixIconConstraints: BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(color: Vx.red.withValues(alpha: .12), borderRadius: BorderRadius.circular(999)),
            child: Text('18+', style: Vx.mono(size: 12, weight: FontWeight.w600, color: Vx.red)),
          ),
          const SizedBox(width: 12),
          if (widget.signedIn)
            Tooltip(
              message: _username.isEmpty ? 'Account' : _username,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _page = _Page.account),
                child: Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Vx.blue, borderRadius: BorderRadius.circular(12)),
                  child: Text(_username.isEmpty ? '•' : _username[0].toUpperCase(), style: Vx.sans(size: 16, weight: FontWeight.w700, color: Colors.white)),
                ),
              ),
            )
          else ...[
            TextButton(onPressed: () => _openAuth(), child: Text('Log in', style: Vx.sans(size: 14, weight: FontWeight.w500, color: Vx.text))),
            const SizedBox(width: 6),
            FilledButton(onPressed: () => _openAuth(signup: true), style: FilledButton.styleFrom(minimumSize: const Size(0, 38)), child: const Text('Sign up')),
          ],
        ]),
      );

  Widget _sidebar(bool wide) {
    final live = _providers.where((p) => p['available'] == true).toList();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Vx.ease,
      width: wide ? 248 : 76,
      decoration: const BoxDecoration(color: Vx.bg, border: Border(right: BorderSide(color: Vx.line))),
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 16, 12, 16), children: [
        for (final item in _nav) _NavItem(label: item.$2, icon: item.$3, activeIcon: item.$4, active: _page == item.$1, wide: wide, onTap: () => _go(item.$1)),
        if (_isAdmin)
          _NavItem(label: 'Admin', icon: Icons.admin_panel_settings_outlined, activeIcon: Icons.admin_panel_settings_rounded, active: _page == _Page.admin, wide: wide, onTap: () => _go(_Page.admin)),
        if (live.isNotEmpty) ...[
          const SizedBox(height: 18),
          if (wide)
            Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10), child: Text('LIBRARIES', style: Vx.mono(size: 11, spacing: 1.4)))
          else
            const Padding(padding: EdgeInsets.symmetric(vertical: 8, horizontal: 14), child: Divider()),
          for (final p in live)
            _NavItem(
              label: (p['name'] ?? '').toString(),
              leading: ProviderIcon(id: (p['id'] ?? '').toString(), name: (p['name'] ?? '').toString(), size: 24),
              active: _page == _Page.browse && _provider == p['id'] && _query.isEmpty,
              wide: wide,
              onTap: () => _browse((p['id'] ?? '').toString()),
            ),
        ],
        const SizedBox(height: 18),
        _NavItem(label: widget.signedIn ? 'Account' : 'Log in', icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, active: _page == _Page.account, wide: wide, onTap: () => widget.signedIn ? setState(() => _page = _Page.account) : _openAuth()),
      ]),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({required this.label, required this.active, required this.wide, required this.onTap, this.icon, this.activeIcon, this.leading});
  final String label;
  final IconData? icon;
  final IconData? activeIcon;
  final Widget? leading;
  final bool active;
  final bool wide;
  final VoidCallback onTap;
  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final color = widget.active ? Vx.text : (_hover ? Vx.text : Vx.text2);
    final leading = widget.leading ?? Icon(widget.active ? widget.activeIcon : widget.icon, size: 20, color: widget.active ? Vx.blue : color);
    final tile = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 42,
          margin: const EdgeInsets.only(bottom: 2),
          padding: EdgeInsets.symmetric(horizontal: widget.wide ? 12 : 0),
          decoration: BoxDecoration(
            color: widget.active ? Vx.well2 : (_hover ? Vx.well : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(mainAxisAlignment: widget.wide ? MainAxisAlignment.start : MainAxisAlignment.center, children: [
            leading,
            if (widget.wide) ...[
              const SizedBox(width: 12),
              Expanded(child: Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Vx.sans(size: 14, weight: FontWeight.w500, color: color))),
            ],
          ]),
        ),
      ),
    );
    return widget.wide ? tile : Tooltip(message: widget.label, waitDuration: const Duration(milliseconds: 400), child: tile);
  }
}
