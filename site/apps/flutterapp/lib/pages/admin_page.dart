import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/vexo_api.dart';
import '../widgets/vexo_theme.dart';

enum AdminDestination { home, social, status }

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.api, required this.onNavigate});
  final VexoApi api;
  final ValueChanged<AdminDestination> onNavigate;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  static const _sections = <(String, IconData)>[
    ('Overview', Icons.dashboard_outlined),
    ('Providers', Icons.video_library_outlined),
    ('Backend', Icons.dns_outlined),
    ('Members', Icons.people_outline_rounded),
    ('Team', Icons.admin_panel_settings_outlined),
    ('Social', Icons.forum_outlined),
    ('Telegram', Icons.send_outlined),
    ('Live viewers', Icons.visibility_outlined),
    ('Operations', Icons.build_outlined),
    ('Links', Icons.link_rounded),
    ('Account', Icons.manage_accounts_outlined),
  ];
  static const _permissions = <(String, String)>[
    ('site', 'Site mode'),
    ('backend', 'Backend'),
    ('providers', 'Providers'),
    ('operations', 'Operations'),
    ('social', 'Social media'),
    ('users', 'Team management'),
  ];
  static const _socialNetworks = <(String, String)>[
    ('telegram', 'Telegram'), ('x', 'X'), ('instagram', 'Instagram'), ('youtube', 'YouTube'),
    ('tiktok', 'TikTok'), ('discord', 'Discord'), ('reddit', 'Reddit'), ('whatsapp', 'WhatsApp'),
    ('facebook', 'Facebook'), ('website', 'Website'),
  ];
  static const _botPlatforms = <String>['telegram', 'discord', 'whatsapp', 'messenger', 'line', 'slack', 'viber', 'other'];

  final _query = TextEditingController();
  final _backend = TextEditingController();
  final _lockMessage = TextEditingController();
  final _newAdminName = TextEditingController();
  final _newAdminPassword = TextEditingController();
  final _telegramToken = TextEditingController();
  final _telegramWebhook = TextEditingController();
  final _channelId = TextEditingController();
  final _channelInvite = TextEditingController();
  final _postText = TextEditingController();
  final _currentPassword = TextEditingController();
  final _nextPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  final Map<String, TextEditingController> _linkFields = {};
  final Map<String, TextEditingController> _botFields = {};
  final Map<String, TextEditingController> _liveFields = {};

  int _section = 0;
  bool _loading = true;
  bool _saving = false;
  bool _maintenance = false;
  bool _showSocialPage = true;
  bool _showSocialFooter = false;
  bool _botButtons = true;
  bool _memberRequireLogin = true;
  bool _memberAllowSignup = true;
  bool _memberEmbedsToo = false;
  bool _memberModelsLogin = true;
  bool _telegramConfigured = false;
  String _telegramSource = '';
  String _defaultProvider = '';
  String _liveMode = 'simulated';
  List<Map<String, dynamic>> _providers = [];
  List<String> _providerOrder = [];
  Map<String, String> _providerModes = {};
  List<Map<String, dynamic>> _team = [];
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _bots = [];
  List<Map<String, dynamic>> _posts = [];
  Map<String, dynamic> _database = {};
  Map<String, dynamic> _liveStats = {};
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _backend.dispose();
    _lockMessage.dispose();
    _newAdminName.dispose();
    _newAdminPassword.dispose();
    _telegramToken.dispose();
    _telegramWebhook.dispose();
    _channelId.dispose();
    _channelInvite.dispose();
    _postText.dispose();
    _postButtonText.dispose();
    _postButtonUrl.dispose();
    _currentPassword.dispose();
    _nextPassword.dispose();
    _confirmPassword.dispose();
    for (final c in [..._linkFields.values, ..._botFields.values, ..._liveFields.values]) { c.dispose(); }
    super.dispose();
  }

  void _setField(Map<String, TextEditingController> fields, String key, String value) {
    final c = fields.putIfAbsent(key, TextEditingController.new);
    c.text = value;
  }

  String _field(Map<String, TextEditingController> fields, String key) => fields[key]?.text.trim() ?? '';

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async =>
      asMap(await widget.api.post(path, authenticated: true, body: body, timeout: const Duration(seconds: 40)));

  Future<bool> _confirm(String title, String detail) async => await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue'))],
        ),
      ) ?? false;

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _notice = null; });
    try {
      final data = asMap(await widget.api.get('/admin', authenticated: true, timeout: const Duration(seconds: 40)));
      final providers = asList(data['providers']).map(asMap).toList();
      final social = asMap(data['social']);
      final socialConfig = asMap(social['config']);
      final channel = asMap(socialConfig['channel']);
      final members = asMap(data['members']);
      final memberConfig = asMap(members['config']);
      final telegram = asMap(data['telegram']);
      final live = asMap(data['live']);
      final liveConfig = asMap(live['config']);
      final stats = asMap(live['stats']);
      final db = asMap(data['database']);
      final modes = <String, String>{};
      for (final p in providers) { modes[(p['id'] ?? '').toString()] = (p['mode'] ?? 'live').toString(); }
      _providers = providers;
      _providerOrder = (data['providerOrder'] is List ? (data['providerOrder'] as List).map((e) => e.toString()).toList() : providers.map((p) => (p['id'] ?? '').toString()).toList());
      _providerModes = modes;
      _defaultProvider = (data['defaultProvider'] ?? '').toString();
      _query.text = (data['defaultQuery'] ?? '').toString();
      _lockMessage.text = (data['lockMessage'] ?? '').toString();
      _backend.text = (data['backendUrl'] ?? '').toString();
      _maintenance = data['maintenanceOn'] == true;
      _team = asList(data['team']).map(asMap).toList();
      _members = asList(members['rows']).map(asMap).toList();
      _memberRequireLogin = memberConfig['requireLogin'] != false;
      _memberAllowSignup = memberConfig['allowSignup'] != false;
      _memberEmbedsToo = memberConfig['embedsToo'] == true;
      _memberModelsLogin = memberConfig['modelsLogin'] != false;
      _showSocialPage = socialConfig['showPage'] != false;
      _showSocialFooter = socialConfig['showInFooter'] == true;
      _botButtons = socialConfig['botButtons'] != false;
      for (final (id, _) in _socialNetworks) { _setField(_linkFields, id, (asMap(socialConfig['links'])[id] ?? '').toString()); }
      _channelId.text = (channel['chatId'] ?? '').toString();
      _channelInvite.text = (channel['inviteUrl'] ?? '').toString();
      _bots = asList(socialConfig['bots']).map(asMap).toList();
      for (final bot in _bots) {
        final key = (bot['key'] ?? '').toString();
        for (final (field, source) in [('name', 'name'), ('id', 'botId'), ('url', 'url'), ('about', 'about')]) {
          _setField(_botFields, '$key-$field', (bot[source] ?? '').toString());
        }
      }
      _posts = asList(social['posts']).map(asMap).toList();
      _telegramConfigured = telegram['tokenConfigured'] == true;
      _telegramSource = (telegram['tokenSource'] ?? 'Not configured').toString();
      _telegramWebhook.text = (telegram['webhookOrigin'] ?? '').toString();
      _liveMode = (liveConfig['mode'] ?? 'simulated').toString();
      _liveEnabled = liveConfig['enabled'] == true;
      _owner = asMap(data['owner']);
      _memberTotal = asInt(members['total']);
      for (final key in ['min', 'max', 'joinMin', 'joinMax', 'leaveMin', 'leaveMax']) { _setField(_liveFields, key, (liveConfig[key] ?? '').toString()); }
      _liveStats = stats;
      _database = db;
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _run(Future<dynamic> Function() action, String success) async {
    setState(() { _saving = true; _error = null; _notice = null; });
    try {
      await action();
      await _load();
      if (mounted) setState(() { _saving = false; _notice = success; });
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = e.toString(); });
    }
  }

  Future<void> _saveSettings({bool includeMaintenance = false}) => _run(() async {
        await _post('/admin/settings', includeMaintenance
          ? {'maintenanceOn': _maintenance}
          : {'backendUrl': _backend.text.trim()});
      }, 'Settings saved.');

  Future<void> _saveProviders() => _run(() async {
        await _post('/admin/settings', {
          'defaultQuery': _query.text.trim(), 'defaultProvider': _defaultProvider,
          'lockMessage': _lockMessage.text.trim(), 'providerOrder': _providerOrder,
          'providerModes': _providerModes,
        });
      }, 'Provider settings saved.');

  Future<void> _setMaintenance(bool value) async {
    setState(() => _maintenance = value);
    await _saveSettings(includeMaintenance: true);
  }

  Future<void> _setProviderBulk(String mode) async {
    setState(() => _providerModes = {for (final p in _providers) (p['id'] ?? '').toString(): mode});
    await _saveProviders();
  }

  Future<void> _saveMembers() => _run(() async {
        await _post('/admin/members', {'action': 'settings', 'config': {
          'requireLogin': _memberRequireLogin, 'allowSignup': _memberAllowSignup,
          'embedsToo': _memberEmbedsToo, 'modelsLogin': _memberModelsLogin,
        }});
      }, 'Member settings saved.');

  Future<void> _memberAction(String action, Map<String, dynamic> member) async {
    final name = (member['username'] ?? 'this member').toString();
    if (action == 'remove' && !await _confirm('Remove member?', '$name will be deleted and signed out. This cannot be undone.')) return;
    await _run(() async { await _post('/admin/members', {'action': action, 'member_id': member['id']}); }, 'Member action completed.');
  }

  Future<void> _teamAction(String action, {Map<String, dynamic>? target}) async {
    final name = target == null ? _newAdminName.text.trim() : (target['username'] ?? '').toString();
    final password = target == null ? _newAdminPassword.text : _field(_botFields, 'team-password-${name.toLowerCase()}');
    final selected = target == null ? Set<String>.from(_newAdminPermissions) : (target['permissions'] is List ? (target['permissions'] as List).map((e) => e.toString()).toSet() : <String>{});
    if (action == 'create' && (name.isEmpty || password.length < 10)) {
      setState(() => _error = 'Enter a username and a starting password of at least 10 characters.');
      return;
    }
    if (action == 'remove' && !await _confirm('Remove admin?', '$name will lose app/admin access immediately.')) return;
    await _run(() async {
      await _post('/admin/team', {'action': action, 'username': name, if (password.isNotEmpty) 'password': password, 'permissions': selected.toList()});
      if (action == 'create') { _newAdminName.clear(); _newAdminPassword.clear(); }
      if (action == 'reset') _botFields['team-password-${name.toLowerCase()}']?.clear();
    }, 'Team updated.');
  }

  Future<void> _saveSocialLinks() => _run(() async {
        final links = <String, String>{for (final (id, _) in _socialNetworks) if (_field(_linkFields, id).isNotEmpty) id: _field(_linkFields, id)};
        await _post('/admin/social', {'action': 'save', 'config': {'links': links, 'showPage': _showSocialPage, 'showInFooter': _showSocialFooter, 'botButtons': _botButtons}});
      }, 'Social links saved.');

  Future<void> _saveChannel() => _run(() async {
        await _post('/admin/social', {'action': 'channel', 'config': {'channel': {'chatId': _channelId.text.trim(), 'inviteUrl': _channelInvite.text.trim()}}});
      }, 'Channel settings saved.');

  Future<void> _saveBots() => _run(() async {
        final bots = _bots.map((bot) {
          final key = (bot['key'] ?? '').toString();
          return <String, dynamic>{
            ...bot,
            'name': _field(_botFields, '$key-name'),
            'botId': _field(_botFields, '$key-id'),
            'url': _field(_botFields, '$key-url'),
            'about': _field(_botFields, '$key-about'),
          };
        }).toList();
        final key = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
        if (_field(_botFields, 'new-id').isNotEmpty || _field(_botFields, 'new-url').isNotEmpty || _field(_botFields, 'new-name').isNotEmpty) {
          bots.add({'key': key, 'platform': _newBotPlatform, 'name': _field(_botFields, 'new-name'), 'botId': _field(_botFields, 'new-id'), 'url': _field(_botFields, 'new-url'), 'about': _field(_botFields, 'new-about'), 'visible': _newBotVisible});
        }
        await _post('/admin/social', {'action': 'bots', 'config': {'bots': bots}});
        for (final key in ['new-name', 'new-id', 'new-url', 'new-about']) { _botFields[key]?.clear(); }
      }, 'Bots saved.');

  Future<void> _socialAction(String action, [Map<String, dynamic>? data]) async {
    if (action == 'delete_post' && !await _confirm('Delete channel post?', 'This removes the post from Telegram where possible and hides it from the post log.')) return;
    await _run(() async {
      await _post('/admin/social', {'action': action, ...?data});
      if (action == 'post') _postText.clear();
    }, action == 'post' ? 'Post sent.' : 'Social action complete.');
  }

  Future<void> _telegramAction(String action) => _run(() async {
        await _post('/admin/telegram', {
          'action': action, 'botToken': _telegramToken.text.trim(), 'webhookOrigin': _telegramWebhook.text.trim(),
        });
        if (action == 'save') _telegramToken.clear();
      }, 'Telegram settings updated.');

  Future<void> _saveLive() => _run(() async {
        final config = <String, dynamic>{
          'enabled': _liveEnabled, 'mode': _liveMode,
          'min': int.tryParse(_field(_liveFields, 'min')) ?? 0,
          'max': int.tryParse(_field(_liveFields, 'max')) ?? 0,
          'joinMin': int.tryParse(_field(_liveFields, 'joinMin')) ?? 0,
          'joinMax': int.tryParse(_field(_liveFields, 'joinMax')) ?? 0,
          'leaveMin': int.tryParse(_field(_liveFields, 'leaveMin')) ?? 0,
          'leaveMax': int.tryParse(_field(_liveFields, 'leaveMax')) ?? 0,
        };
        await _post('/admin/live', {'config': config});
      }, 'Live viewer settings saved.');

  Future<void> _operations(String action) => _run(() async { await _post('/admin/operations', {'action': action}); }, action == 'repair' ? 'Database repaired.' : 'Database status refreshed.');

  Future<void> _changePassword() => _run(() async {
        final result = await _post('/admin/password', {'current': _currentPassword.text, 'next': _nextPassword.text, 'confirm': _confirmPassword.text});
        final token = (result['token'] ?? '').toString();
        if (token.isNotEmpty) await widget.api.saveToken(token);
        _currentPassword.clear(); _nextPassword.clear(); _confirmPassword.clear();
      }, 'Password changed. Other Owner sessions were signed out.');

  String _newBotPlatform = 'telegram';
  bool _newBotVisible = true;
  bool _liveEnabled = false;
  final Set<String> _newAdminPermissions = {'providers'};
  final _postButtonText = TextEditingController();
  final _postButtonUrl = TextEditingController();
  String _postFormat = 'plain';
  bool _postSilent = false;
  bool _postPin = false;
  bool _postNoPreview = false;

  @override
  Widget build(BuildContext context) => PageBody(maxWidth: 1050, children: [
        PageHeading(kicker: 'Control room', title: 'Admin panel', subtitle: 'Your permitted site controls.', trailing: IconButton(tooltip: 'Reload settings', onPressed: _loading || _saving ? null : _load, icon: const Icon(Icons.refresh_rounded))),
        if (_loading) const SizedBox(height: 240, child: PageLoader(label: 'Loading all Admin settings…')) else ...[
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (var i = 0; i < _sections.length; i++) if (_sectionAllowed(i)) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(_sections[i].$1), selected: _section == i, avatar: Icon(_sections[i].$2, size: 17), onSelected: (_) => setState(() => _section = i))),
          ])),
          if (_error != null) _message(_error!, Vx.red),
          if (_notice != null) _message(_notice!, Vx.green),
          const SizedBox(height: 20),
          _sectionBody(),
        ],
      ]);

  Widget _sectionBody() => switch (_section) {
    0 => _overview(),
    1 => _providersSection(),
    2 => _backendSection(),
    3 => _membersSection(),
    4 => _teamSection(),
    5 => _socialSection(),
    6 => _telegramSection(),
    7 => _liveSection(),
    8 => _operationsSection(),
    9 => _linksSection(),
    _ => _accountSection(),
  };

  Widget _card(String title, String subtitle, List<Widget> children, {IconData icon = Icons.tune_rounded}) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(22),
        decoration: Vx.surface(radius: Vx.radius2xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, color: Vx.blue), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Vx.sans(size: 18, weight: FontWeight.w700)), Text(subtitle, style: Vx.sans(size: 13, color: Vx.text3))]))]),
          const SizedBox(height: 18), ...children,
        ]),
      );

  Widget _message(String text, Color color) => Container(margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: color.withValues(alpha: .1), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: .3))), child: Text(text, style: Vx.sans(size: 14, color: color)));
  bool _can(String permission) => _owner['isOwner'] == true || asList(_owner['permissions']).contains(permission);
  bool _sectionAllowed(int i) => switch (i) {
    0 || 9 || 10 => true,
    1 => _can('providers'),
    2 => _can('backend'),
    3 => _can('site'),
    4 => _can('users'),
    5 || 6 => _can('social'),
    7 => _owner['isOwner'] == true,
    8 => _can('operations'),
    _ => false,
  };
  Widget _saveButton(VoidCallback onPressed, {String label = 'Save changes'}) => FilledButton.icon(onPressed: _saving ? null : onPressed, icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined), label: Text(_saving ? 'Saving…' : label));
  Widget _overview() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    if (_can('site')) _card('Site mode', 'Maintenance controls public website/app traffic.', [
      SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, value: _maintenance, onChanged: _saving ? null : _setMaintenance, title: Text(_maintenance ? 'Maintenance is on' : 'Site is live'), subtitle: const Text('Owner login and admin settings remain available.'), secondary: Icon(_maintenance ? Icons.build_circle_outlined : Icons.check_circle_outline, color: _maintenance ? Vx.amber : Vx.green)),
      _saveButton(() => _saveSettings(includeMaintenance: true), label: 'Save site mode'),
    ], icon: Icons.construction_outlined),
    if (_can('operations')) _card('Quick health', 'DB binding: ${_database['binding'] == true ? 'connected' : 'missing'} · Settings table: ${_database['table'] == true ? 'ready' : 'needs repair'}', [OutlinedButton.icon(onPressed: _saving ? null : () { setState(() => _section = 8); _operations('health'); }, icon: const Icon(Icons.monitor_heart_outlined), label: const Text('Open operations'))], icon: Icons.health_and_safety_outlined),
    _card('Admin account', 'Signed in as ${firstText(asMap(_owner), const ['username'])}', [Text('Use Account to change your password.', style: Vx.sans(size: 14, color: Vx.text2)), OutlinedButton(onPressed: () => setState(() => _section = 10), child: const Text('Account and password'))], icon: Icons.verified_user_outlined),
  ]);

  Map<String, dynamic> _loadedMembers() => {'total': _memberTotal};
  Map<String, dynamic> _owner = {};
  int _memberTotal = 0;
  int asInt(dynamic value) => value is int ? value : int.tryParse(value.toString()) ?? 0;

  Widget _providersSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _card('Provider status and order', 'Set each library live, locked, or hidden. Move rows to change public display order.', [
      Wrap(spacing: 8, runSpacing: 8, children: [OutlinedButton(onPressed: _saving ? null : () => _setProviderBulk('live'), child: const Text('Unlock all')), OutlinedButton(onPressed: _saving ? null : () => _setProviderBulk('locked'), child: const Text('Lock all')), OutlinedButton(onPressed: _saving ? null : () { setState(() { _providerModes = {for (final p in _providers) (p['id'] ?? '').toString(): 'live'}; _providerOrder = _providers.map((p) => (p['id'] ?? '').toString()).toList(); _defaultProvider = 'pornhub'; _query.text = 'Brazzers'; _lockMessage.text = 'This provider is currently unavailable. Try another one.'; }); _saveProviders(); }, child: const Text('Reset defaults'))]),
      const SizedBox(height: 12),
      for (final (i, id) in _providerOrder.indexed) _providerRow(id, i),
      const SizedBox(height: 12), TextField(controller: _lockMessage, maxLength: 200, decoration: const InputDecoration(labelText: 'Locked-provider message')),
      TextField(controller: _query, maxLength: 100, decoration: const InputDecoration(labelText: 'Default search word')),
      const SizedBox(height: 10), DropdownButtonFormField<String>(value: _defaultProvider.isEmpty ? null : _defaultProvider, decoration: const InputDecoration(labelText: 'Default provider'), items: [for (final p in _providers) DropdownMenuItem(value: (p['id'] ?? '').toString(), child: Text('${p['name'] ?? p['id']} (${p['mode']})'))], onChanged: _saving ? null : (v) { if (v != null) setState(() => _defaultProvider = v); }),
      const SizedBox(height: 14), _saveButton(_saveProviders),
    ], icon: Icons.video_library_outlined),
  ]);

  Widget _providerRow(String id, int index) {
    final item = _providers.cast<Map<String, dynamic>?>().firstWhere((p) => p?['id'] == id, orElse: () => null) ?? <String, dynamic>{};
    final mode = _providerModes[id] ?? 'live';
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: Vx.surface(radius: Vx.radiusMd), child: Row(children: [Expanded(child: Text((item['name'] ?? id).toString())), IconButton(onPressed: _saving || index == 0 ? null : () => setState(() { _providerOrder.removeAt(index); _providerOrder.insert(index - 1, id); }), icon: const Icon(Icons.arrow_upward_rounded, size: 18)), IconButton(onPressed: _saving || index == _providerOrder.length - 1 ? null : () => setState(() { _providerOrder.removeAt(index); _providerOrder.insert(index + 1, id); }), icon: const Icon(Icons.arrow_downward_rounded, size: 18)), SizedBox(width: 150, child: DropdownButtonFormField<String>(value: mode, items: const [DropdownMenuItem(value: 'live', child: Text('Live')), DropdownMenuItem(value: 'locked', child: Text('Locked')), DropdownMenuItem(value: 'hidden', child: Text('Hidden'))], onChanged: _saving ? null : (v) { if (v != null) setState(() => _providerModes[id] = v); }))]));
  }

  Widget _backendSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _card('Core backend URL', 'Public API origin used for catalog, models, posters, and stream extraction.', [TextField(controller: _backend, maxLength: 240, decoration: const InputDecoration(labelText: 'Backend URL', hintText: 'https://your-core-service.example')), const SizedBox(height: 10), Wrap(spacing: 8, children: [_saveButton(() => _saveSettings(), label: 'Save backend'), OutlinedButton(onPressed: _saving ? null : () { _backend.clear(); _saveSettings(); }, child: const Text('Reset to Worker variable'))])], icon: Icons.dns_outlined),
  ]);

  Widget _membersSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _card('Member access rules', 'Control registration and account-gated site features.', [
      _switch('Require member login to watch', _memberRequireLogin, (v) => setState(() => _memberRequireLogin = v)),
      _switch('Allow new member sign-ups', _memberAllowSignup, (v) => setState(() => _memberAllowSignup = v)),
      _switch('Require login for embedded players', _memberEmbedsToo, (v) => setState(() => _memberEmbedsToo = v)),
      _switch('Require login for Models pages', _memberModelsLogin, (v) => setState(() => _memberModelsLogin = v)),
      _saveButton(_saveMembers),
    ], icon: Icons.lock_outline_rounded),
    _card('Members ($_memberTotal)', 'Disable/enable an account or remove it. Removed members are signed out.', [
      if (_members.isEmpty) const Text('No member accounts found.') else for (final member in _members) _memberRow(member),
    ], icon: Icons.people_outline_rounded),
  ]);

  Widget _switch(String label, bool value, ValueChanged<bool> onChanged) => SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: Text(label), value: value, onChanged: _saving ? null : onChanged);
  Widget _memberRow(Map<String, dynamic> m) => ListTile(contentPadding: EdgeInsets.zero, title: Text((m['username'] ?? 'Member').toString()), subtitle: Text('Joined ${m['created_at'] ?? 'unknown'} · last login ${m['last_login_at'] ?? 'never'}${m['disabled'] == 1 ? ' · disabled' : ''}'), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(tooltip: m['disabled'] == 1 ? 'Enable' : 'Disable', onPressed: _saving ? null : () => _memberAction(m['disabled'] == 1 ? 'enable' : 'disable', m), icon: Icon(m['disabled'] == 1 ? Icons.check_circle_outline : Icons.block_outlined)), IconButton(tooltip: 'Remove member', onPressed: _saving ? null : () => _memberAction('remove', m), icon: const Icon(Icons.delete_outline, color: Vx.red))]));

  Widget _teamSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _card('Invite admin', 'New admin passwords must be at least 10 characters. Owners can grant Team management.', [TextField(controller: _newAdminName, decoration: const InputDecoration(labelText: 'Username')), const SizedBox(height: 10), TextField(controller: _newAdminPassword, obscureText: true, decoration: const InputDecoration(labelText: 'Starting password')), const SizedBox(height: 12), Wrap(spacing: 8, children: [for (final (id, title) in _permissions) FilterChip(label: Text(title), selected: _newAdminPermissions.contains(id), onSelected: (v) => setState(() { if (v) _newAdminPermissions.add(id); else _newAdminPermissions.remove(id); }))]), const SizedBox(height: 12), _saveButton(() => _teamAction('create'), label: 'Add admin')], icon: Icons.person_add_alt_1_outlined),
    _card('Team & permissions', 'Manage existing admin accounts. The Owner cannot be removed or demoted.', [if (_team.isEmpty) const Text('No team accounts returned.') else for (final person in _team) _teamMember(person)], icon: Icons.admin_panel_settings_outlined),
  ]);

  Widget _teamMember(Map<String, dynamic> person) {
    final name = (person['username'] ?? '').toString();
    final isOwner = person['owner'] == true;
    final permissions = person['permissions'] is List ? (person['permissions'] as List).map((e) => e.toString()).toSet() : <String>{};
    return ExpansionTile(title: Text('$name${isOwner ? ' · Owner' : ''}'), subtitle: Text('Permissions: ${permissions.join(', ')}'), children: [
      if (!isOwner) ...[
        Wrap(spacing: 8, children: [for (final (id, title) in _permissions) FilterChip(label: Text(title), selected: permissions.contains(id), onSelected: _saving ? null : (v) { setState(() { if (v) permissions.add(id); else permissions.remove(id); }); person['permissions'] = permissions.toList(); })]),
        _saveButton(() => _teamAction('update', target: person), label: 'Save permissions'),
        TextField(controller: _botFields.putIfAbsent('team-password-${name.toLowerCase()}', TextEditingController.new), obscureText: true, decoration: const InputDecoration(labelText: 'New password (optional, min 10)')),
        Wrap(spacing: 8, children: [OutlinedButton(onPressed: _saving ? null : () => _teamAction('reset', target: person), child: const Text('Reset password')), TextButton(onPressed: _saving ? null : () => _teamAction('remove', target: person), child: const Text('Remove admin', style: TextStyle(color: Vx.red)))]),
      ] else const Padding(padding: EdgeInsets.all(12), child: Text('Owner has every permission and cannot be removed.')),
    ]);
  }

  Widget _socialSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _card('Social links and visibility', 'The site footer, Social page, and bot menu use these links.', [for (final (id, label) in _socialNetworks) TextField(controller: _linkFields[id], decoration: InputDecoration(labelText: label, hintText: 'https://…')), _switch('Show Social page link', _showSocialPage, (v) => setState(() => _showSocialPage = v)), _switch('Show social icons in footer', _showSocialFooter, (v) => setState(() => _showSocialFooter = v)), _switch('Show channel/social buttons in bot menu', _botButtons, (v) => setState(() => _botButtons = v)), _saveButton(_saveSocialLinks)], icon: Icons.link_outlined),
    _card('Telegram channel', 'Save a public @channel or private -100… ID and optional invite.', [TextField(controller: _channelId, decoration: const InputDecoration(labelText: 'Channel ID')), TextField(controller: _channelInvite, decoration: const InputDecoration(labelText: 'Invite URL')), Wrap(spacing: 8, children: [_saveButton(_saveChannel, label: 'Save channel'), OutlinedButton(onPressed: _saving ? null : () => _socialAction('test_channel'), child: const Text('Test channel'))])], icon: Icons.campaign_outlined),
    _card('Channel posts', 'Publish and manage Telegram channel posts.', [TextField(controller: _postText, maxLines: 4, maxLength: 4000, decoration: const InputDecoration(labelText: 'Message')), DropdownButtonFormField<String>(value: _postFormat, items: const [DropdownMenuItem(value: 'plain', child: Text('Plain text')), DropdownMenuItem(value: 'html', child: Text('HTML formatting'))], onChanged: _saving ? null : (v) { if (v != null) setState(() => _postFormat = v); }), TextField(controller: _postButtonText, decoration: const InputDecoration(labelText: 'Optional button text')), TextField(controller: _postButtonUrl, decoration: const InputDecoration(labelText: 'Optional button URL')), _switch('Send silently', _postSilent, (v) => setState(() => _postSilent = v)), _switch('Pin after posting', _postPin, (v) => setState(() => _postPin = v)), _switch('Disable link previews', _postNoPreview, (v) => setState(() => _postNoPreview = v)), _saveButton(() => _socialAction('post', {'text': _postText.text, 'format': _postFormat, 'button_text': _postButtonText.text, 'button_url': _postButtonUrl.text, 'silent': _postSilent, 'pin': _postPin, 'no_preview': _postNoPreview}), label: 'Post to channel'), if (_posts.isNotEmpty) ...[const Divider(), for (final post in _posts) ListTile(contentPadding: EdgeInsets.zero, title: Text((post['text'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text('${post['created_at'] ?? ''}${post['pinned'] == 1 ? ' · pinned' : ''}'), trailing: IconButton(tooltip: 'Delete post', onPressed: _saving ? null : () => _socialAction('delete_post', {'post_id': post['id']}), icon: const Icon(Icons.delete_outline, color: Vx.red)))]] , icon: Icons.post_add_rounded),
    _botsCard(),
  ]);

  Widget _botsCard() => _card('Bots', 'Manage Telegram, Discord, WhatsApp, Messenger, LINE, Slack, Viber, and custom bots.', [for (final bot in _bots) _botEditor(bot), const Divider(), Text('Add bot', style: Vx.sans(size: 16, weight: FontWeight.w600)), DropdownButtonFormField<String>(value: _newBotPlatform, items: [for (final p in _botPlatforms) DropdownMenuItem(value: p, child: Text(p))], onChanged: _saving ? null : (v) { if (v != null) setState(() => _newBotPlatform = v); }), TextField(controller: _botFields.putIfAbsent('new-name', TextEditingController.new), decoration: const InputDecoration(labelText: 'Bot name')), TextField(controller: _botFields.putIfAbsent('new-id', TextEditingController.new), decoration: const InputDecoration(labelText: 'Bot ID or handle')), TextField(controller: _botFields.putIfAbsent('new-url', TextEditingController.new), decoration: const InputDecoration(labelText: 'Public bot URL (optional)')), TextField(controller: _botFields.putIfAbsent('new-about', TextEditingController.new), decoration: const InputDecoration(labelText: 'Description (optional)')), _switch('Show new bot publicly', _newBotVisible, (v) => setState(() => _newBotVisible = v)), Wrap(spacing: 8, children: [OutlinedButton(onPressed: _saving ? null : () => _socialAction('bot_import_tg'), child: const Text('Import configured Telegram bot')), _saveButton(_saveBots)])], icon: Icons.smart_toy_outlined);
  Widget _botEditor(Map<String, dynamic> bot) {
    final key = (bot['key'] ?? '').toString();
    final platform = _botPlatforms.contains(bot['platform']) ? bot['platform'].toString() : 'other';
    return Column(children: [
      ListTile(contentPadding: EdgeInsets.zero, title: Text((bot['name'] ?? platform).toString()), trailing: IconButton(onPressed: _saving ? null : () async { if (await _confirm('Remove bot?', 'This bot will be removed from the public Social page.')) setState(() => _bots.remove(bot)); }, icon: const Icon(Icons.remove_circle_outline, color: Vx.red))),
      DropdownButtonFormField<String>(value: platform, decoration: const InputDecoration(labelText: 'Platform'), items: [for (final p in _botPlatforms) DropdownMenuItem(value: p, child: Text(p))], onChanged: _saving ? null : (v) { if (v != null) setState(() => bot['platform'] = v); }),
      for (final (field, label) in [('name', 'Name'), ('id', 'Bot ID or handle'), ('url', 'Custom link'), ('about', 'Short description')]) TextField(controller: _botFields['$key-$field'], decoration: InputDecoration(labelText: label)),
      _switch('Visible', bot['visible'] != false, (v) => setState(() => bot['visible'] = v)),
      const Divider(),
    ]);
  }

  Widget _telegramSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _card('Telegram bot', 'Token is write-only here. It is never returned to the app after saving.', [Text('Status: ${_telegramConfigured ? 'configured' : 'not configured'} · source: $_telegramSource', style: Vx.sans(size: 14, color: _telegramConfigured ? Vx.green : Vx.amber)), TextField(controller: _telegramToken, obscureText: true, decoration: const InputDecoration(labelText: 'Bot token', hintText: 'Blank keeps the current token')), TextField(controller: _telegramWebhook, decoration: const InputDecoration(labelText: 'Webhook origin (public HTTPS)')), Wrap(spacing: 8, runSpacing: 8, children: [_saveButton(() => _telegramAction('save'), label: 'Save Telegram settings'), OutlinedButton(onPressed: _saving ? null : () => _telegramAction('check_bot'), child: const Text('Check bot')), OutlinedButton(onPressed: _saving ? null : () => _telegramAction('check_channel'), child: const Text('Test channel')), OutlinedButton(onPressed: _saving ? null : () => _telegramAction('reconnect'), child: const Text('Reconnect webhook')), TextButton(onPressed: _saving ? null : () => _telegramAction('reset_token'), child: const Text('Reset token override')), TextButton(onPressed: _saving ? null : () => _socialAction('bot_import_tg'), child: const Text('Import this bot to Social'))])], icon: Icons.send_outlined),
  ]);

  Widget _liveNumberField(String key, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: Vx.sans(size: 13, weight: FontWeight.w600, color: Vx.text2)),
          const SizedBox(height: 8),
          TextField(
            controller: _liveFields[key],
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 9,
            decoration: const InputDecoration(
              hintText: 'Enter a whole number',
              counterText: '',
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            ),
          ),
        ],
      );

  Widget _liveRange(String heading, String minKey, String maxKey) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(heading.toUpperCase(), style: Vx.mono(size: 11, spacing: 1.2))),
          LayoutBuilder(builder: (context, constraints) {
            final minField = _liveNumberField(minKey, 'Minimum');
            final maxField = _liveNumberField(maxKey, 'Maximum');
            if (constraints.maxWidth < 480) {
              return Column(children: [minField, const SizedBox(height: 16), maxField]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: minField),
              const SizedBox(width: 18),
              Expanded(child: maxField),
            ]);
          }),
        ]),
      );

  Widget _liveSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _card('Live viewers', 'Manage the public “watching now” counter and simulated/real traffic.', [
      _switch('Show counter on the site', _liveEnabled, (v) => setState(() => _liveEnabled = v)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(value: _liveMode, items: const [DropdownMenuItem(value: 'simulated', child: Text('Simulated')), DropdownMenuItem(value: 'real', child: Text('Real visitors'))], onChanged: _saving ? null : (v) { if (v != null) setState(() => _liveMode = v); }),
      const SizedBox(height: 12),
      _liveRange('Online now', 'min', 'max'),
      _liveRange('Joins per second', 'joinMin', 'joinMax'),
      _liveRange('Leaves per second', 'leaveMin', 'leaveMax'),
      Container(margin: const EdgeInsets.only(top: 12, bottom: 16), padding: const EdgeInsets.all(14), decoration: Vx.surface(radius: Vx.radiusMd), child: Text('Real visitors: ${_liveStats['real'] ?? 0}  ·  Visitors see: ${_liveStats['shown'] ?? 'Hidden'}  ·  Joined +${_liveStats['joins'] ?? 0} / left -${_liveStats['leaves'] ?? 0}', style: Vx.sans(size: 13, color: Vx.text2))),
      _saveButton(_saveLive),
    ], icon: Icons.visibility_outlined),
  ]);

  Widget _operationsSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _card('Database health', 'Inspect bindings and run the same repair operation as the website Admin panel.', [for (final entry in _database.entries) ListTile(contentPadding: EdgeInsets.zero, title: Text(entry.key), trailing: Text(entry.value.toString())), if (_database['error'] != null) Text((_database['error'] ?? '').toString(), style: Vx.sans(size: 13, color: Vx.red)), Wrap(spacing: 8, children: [OutlinedButton(onPressed: _saving ? null : () => _operations('health'), child: const Text('Refresh health')), _saveButton(() => _operations('repair'), label: 'Repair database')])], icon: Icons.build_outlined),
  ]);

  Widget _linksSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _card('Public pages', 'Jump to the matching section in the app.', [
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => widget.onNavigate(AdminDestination.home), icon: const Icon(Icons.home_outlined), label: const Text('Explore')),
        OutlinedButton.icon(onPressed: () => widget.onNavigate(AdminDestination.status), icon: const Icon(Icons.monitor_heart_outlined), label: const Text('Status')),
        OutlinedButton.icon(onPressed: () => widget.onNavigate(AdminDestination.social), icon: const Icon(Icons.forum_outlined), label: const Text('Social')),
      ]),
    ], icon: Icons.open_in_new_rounded),
  ]);

  Widget _accountSection() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    _card('Owner account', 'Change your Owner password. This signs out other sessions.', [TextField(controller: _currentPassword, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')), TextField(controller: _nextPassword, obscureText: true, decoration: const InputDecoration(labelText: 'New password (min 10 characters)')), TextField(controller: _confirmPassword, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')), _saveButton(_changePassword, label: 'Change password')], icon: Icons.password_rounded),
  ]);
}
