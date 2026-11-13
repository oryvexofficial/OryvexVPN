import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/backend.dart';
import '../../core/cloudflare_relay.dart';
import '../../core/platform_links.dart';
import '../theme.dart';
import 'tor_exit_picker.dart' show CountryFlag;
import 'cloudflare_relay_setup.dart';
import 'fox_web_signin.dart';

/// Fox's account and location controls live in the same route card as other
/// connections. All service requests remain on the device, via the backend.
class FoxControls extends StatefulWidget {
  const FoxControls({super.key, required this.backend});
  final CoreBackend backend;

  @override
  State<FoxControls> createState() => _FoxControlsState();
}

class _FoxControlsState extends State<FoxControls> {
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> accounts = [];
  List<Map<String, dynamic>> locations = [];
  String selected = '';

  List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
      : [];

  @override
  void initState() {
    super.initState();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (mounted) setState(() { loading = true; error = null; });
    try {
      final accountData = await widget.backend.foxRequest('GET', '/api/accounts');
      final state = await widget.backend.foxRequest('GET', '/api/status');
      final loadedAccounts = _list(accountData['accounts']);
      if (!mounted) return;
      setState(() {
        accounts = loadedAccounts;
        selected = (state['selection'] as String? ?? '').toUpperCase();
        if (selected == 'FASTEST') selected = 'fastest';
        error = null;
      });
      // Do not make first-time sign-in wait on a server-list request.
      if (loadedAccounts.isNotEmpty) {
        final locationData = await widget.backend.foxRequest('GET', '/api/locations');
        if (mounted) setState(() => locations = _list(locationData['locations']));
      } else if (mounted) {
        setState(() => locations = []);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> changeLocation(String value) async {
    setState(() { loading = true; error = null; });
    try {
      await widget.backend.foxRequest('POST', '/api/location', {'country': value});
      await refresh();
    } catch (e) {
      if (mounted) setState(() { loading = false; error = e.toString(); });
    }
  }

  Future<void> addAccount() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => FoxWebSignIn(backend: widget.backend),
    ));
    if (mounted) await refresh();
  }

  Future<void> activateAccount(Map<String, dynamic> account) async {
    final id = account['id'];
    if (id is! String || id.isEmpty) return;
    setState(() { loading = true; error = null; });
    try {
      await widget.backend.foxRequest('POST', '/api/accounts/${Uri.encodeComponent(id)}/activate', {});
      await refresh();
    } catch (e) {
      if (mounted) setState(() { loading = false; error = e.toString(); });
    }
  }

  Future<void> manage(Map<String, dynamic> account, String action) async {
    if (action == 'remove') return remove(account);
    if (action == 'activate') return activateAccount(account);
    final id = account['id'];
    if (id is! String || id.isEmpty) return;
    setState(() { loading = true; error = null; });
    try {
      if (action == 'toggle') {
        await widget.backend.foxRequest('POST', '/api/accounts/${Uri.encodeComponent(id)}/enabled', {'enabled': account['enabled'] != true});
      } else if (action == 'refresh') {
        await widget.backend.foxRequest('POST', '/api/accounts/${Uri.encodeComponent(id)}/refresh', {});
      }
      await refresh();
    } catch (e) {
      if (mounted) setState(() { loading = false; error = e.toString(); });
    }
  }

  Future<void> pingLocations() async {
    setState(() { loading = true; error = null; });
    try {
      await widget.backend.foxRequest('POST', '/api/locations/ping', {});
      await refresh();
    } catch (e) {
      if (mounted) setState(() { loading = false; error = e.toString(); });
    }
  }

  Future<void> remove(Map<String, dynamic> account) async {
    final id = account['id'];
    if (id is! String || id.isEmpty) return;
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Remove account?'),
      content: Text('Remove ${account['email'] ?? 'this account'} from OryvexVPN?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
      ],
    ));
    if (yes != true || !mounted) return;
    setState(() { loading = true; error = null; });
    try {
      await widget.backend.foxRequest('DELETE', '/api/accounts/${Uri.encodeComponent(id)}');
      await refresh();
    } catch (e) {
      if (mounted) setState(() { loading = false; error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedExists = selected.isEmpty || selected == 'fastest' ||
        locations.any((item) => (item['code'] as String? ?? '').toUpperCase() == selected);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Firefox Account', style: Ox.body(15, weight: FontWeight.w500)),
      const SizedBox(height: 5),
      Text('Unofficial client. Mozilla VPN service access is required.', style: Ox.body(13, color: Ox.secondary)),
      if (loading) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
      if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      if (accounts.isEmpty && !loading) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No accounts added yet.')),
      for (final account in accounts)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(account['active'] == true ? Icons.check_circle : Icons.account_circle_outlined),
          title: Text('${account['email'] ?? account['name'] ?? 'Firefox Account'}', overflow: TextOverflow.ellipsis),
          subtitle: Text('${account['status'] ?? ''}${account['active'] == true ? ' · active' : ''}'),
          trailing: PopupMenuButton<String>(
            enabled: !loading,
            tooltip: 'Manage account',
            onSelected: (action) => unawaited(manage(account, action)),
            itemBuilder: (_) => [
              if (account['active'] != true && account['enabled'] == true) const PopupMenuItem(value: 'activate', child: Text('Use this account')),
              PopupMenuItem(value: 'toggle', child: Text(account['enabled'] == true ? 'Disable account' : 'Enable account')),
              const PopupMenuItem(value: 'refresh', child: Text('Refresh usage')),
              const PopupMenuItem(value: 'remove', child: Text('Remove account')),
            ],
          ),
        ),
      Wrap(spacing: 8, children: [
        OutlinedButton.icon(onPressed: loading ? null : addAccount, icon: const Icon(Icons.person_add_alt_1), label: const Text('Sign in with Mozilla')),
        TextButton(onPressed: loading ? null : () async {
          await showDialog<void>(context: context, builder: (_) => _FoxSignIn(backend: widget.backend));
          if (mounted) await refresh();
        }, child: const Text('Other sign-in')),
        TextButton.icon(onPressed: loading ? null : refresh, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
      ]),
      const SizedBox(height: 16),
      Text('Country', style: Ox.body(15, weight: FontWeight.w500)),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        value: selectedExists ? selected : '',
        isExpanded: true,
        decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
        items: [
          const DropdownMenuItem(value: '', child: Text('Recommended')),
          const DropdownMenuItem(value: 'fastest', child: Text('Fastest')),
          for (final item in locations)
            if ((item['code'] as String? ?? '').isNotEmpty)
              DropdownMenuItem(value: (item['code'] as String).toUpperCase(), child: Row(children: [
                CountryFlag(code: (item['code'] as String).toLowerCase(), size: 24),
                const SizedBox(width: 10),
                Expanded(child: Text('${item['name'] ?? item['code']}', overflow: TextOverflow.ellipsis)),
                if (item['ping_ms'] is num && (item['ping_ms'] as num) > 0) Text('${item['ping_ms']} ms'),
              ])),
        ],
        onChanged: loading ? null : (v) { if (v != null) unawaited(changeLocation(v)); },
      ),
      if (locations.isNotEmpty) Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(onPressed: loading ? null : pingLocations, icon: const Icon(Icons.speed), label: const Text('Test country latency')),
      ),
      if (!selectedExists) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Selected country $selected is not in the current list.', style: Ox.body(13, color: Ox.secondary))),
      const SizedBox(height: 8),
      Text('Available countries come from Mozilla. Windows uses a local SOCKS5 proxy; Android can use whole-device VPN.', style: Ox.body(13, color: Ox.secondary)),
      const SizedBox(height: 18),
      _FoxRelaySection(backend: widget.backend),
    ]);
  }
}

class _FoxRelaySection extends StatefulWidget {
  const _FoxRelaySection({required this.backend});
  final CoreBackend backend;

  @override
  State<_FoxRelaySection> createState() => _FoxRelaySectionState();
}

class _FoxRelaySectionState extends State<_FoxRelaySection> {
  List<CloudflareRelayRecord> _records = const [];
  FoxRelayInfo? _active;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final records = await CloudflareRelayStore.load();
      FoxRelayInfo? active;
      String? error;
      try {
        active = await CloudflareRelayClient.readFoxRelay(widget.backend);
      } catch (_) {
        error = 'Could not load the current Fox relay status.';
      }
      if (mounted) setState(() { _active = active; _records = records; _error = error; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the local relay list. Try refreshing.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addRelay() async {
    await showCloudflareRelaySetup(context, backend: widget.backend);
    if (mounted) await _refresh();
  }

  Future<void> _manageRelays() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _FoxRelayManager(backend: widget.backend),
    );
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: Text('My relays', style: Ox.body(15, weight: FontWeight.w600))),
            if (_loading)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              IconButton(
                tooltip: 'Refresh relays',
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 19),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(_error!, style: Ox.body(13, color: Ox.warn)),
          ),
        if (!_loading && _records.isEmpty && _active == null)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text('No relays added yet. Add a personal Cloudflare relay for Fox.', style: Ox.body(13, color: Ox.secondary)),
          ),
        if (_active != null && !_records.any((relay) => relay.endpointKey == _active!.endpointKey))
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_active!.enabled ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                color: _active!.enabled ? Ox.success : Ox.tertiary),
            title: Text(_active!.displayAddress, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(_active!.enabled ? 'Active for Fox requests' : 'Saved, currently disabled'),
          ),
        if (_records.isNotEmpty)
          for (final relay in _records)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(
                _active?.endpointKey == relay.endpointKey ? Icons.check_circle_outline_rounded : Icons.cloud_outlined,
                color: _active?.endpointKey == relay.endpointKey ? Ox.success : Ox.tertiary,
              ),
              title: Text(relay.scriptName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                _active?.endpointKey == relay.endpointKey ? 'Active' : Uri.tryParse(relay.publicUrl)?.host ?? relay.publicUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              onPressed: _loading ? null : _addRelay,
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('Add relay'),
            ),
            TextButton.icon(
              onPressed: _manageRelays,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Manage relays'),
            ),
          ],
        ),
        Text(
          'Fox relays carry account and service requests only, not general VPN traffic.',
          style: Ox.body(12, color: Ox.tertiary),
        ),
      ],
    );
  }
}

class _FoxRelayManager extends StatefulWidget {
  const _FoxRelayManager({required this.backend});
  final CoreBackend backend;

  @override
  State<_FoxRelayManager> createState() => _FoxRelayManagerState();
}

class _FoxRelayManagerState extends State<_FoxRelayManager> {
  List<CloudflareRelayRecord> _records = const [];
  FoxRelayInfo? _active;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _health;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final records = await CloudflareRelayStore.load();
      FoxRelayInfo? active;
      String? error;
      try {
        active = await CloudflareRelayClient.readFoxRelay(widget.backend);
      } catch (_) {
        error = 'Could not load the current Fox relay status.';
      }
      if (mounted) setState(() { _active = active; _records = records; _error = error; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load the local relay list.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setEnabled(bool enabled) async {
    setState(() { _busy = true; _error = null; });
    try {
      await CloudflareRelayClient.setFoxRelayEnabled(widget.backend, enabled);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not update the Fox relay setting.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testRelay() async {
    setState(() { _busy = true; _health = null; _error = null; });
    try {
      final result = await widget.backend.foxRequest('POST', '/api/relay/test', {});
      if (mounted) setState(() => _health = result['ok'] == true
          ? 'Relay health check passed from this device.'
          : 'The relay did not confirm that it is reachable.');
    } catch (_) {
      if (mounted) setState(() => _health = 'Could not finish the relay health check.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlinkRelay() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove relay from Fox?'),
        content: const Text('This clears Fox’s saved relay address. It does not delete the Worker from Cloudflare.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Remove from Fox')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      await CloudflareRelayClient.clearFoxRelay(widget.backend);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not remove the relay from Fox.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forget(CloudflareRelayRecord relay) async {
    try {
      await CloudflareRelayStore.forget(relay.scriptName);
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not remove this entry from the local list.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height - 48),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Icon(Icons.cloud_sync_outlined, color: Ox.blue),
                const SizedBox(width: 10),
                Expanded(child: Text('Manage Fox relays', style: Ox.headline(22))),
                IconButton(
                  tooltip: 'Close',
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
              Text(
                'Fox can use one relay at a time. The local list stores public Worker names only; relay secrets and Cloudflare API tokens are not saved here.',
                style: Ox.body(13, color: Ox.secondary),
              ),
              if (_loading) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: Ox.body(13, color: Ox.warn))),
              if (active != null) ...[
                const SizedBox(height: 18),
                Text('Current Fox relay', style: Ox.body(15, weight: FontWeight.w600)),
                const SizedBox(height: 4),
                SelectableText(active.displayAddress, style: Ox.code(13)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use relay for Fox requests'),
                  subtitle: Text(active.enabled ? 'Enabled' : 'Disabled'),
                  value: active.enabled,
                  onChanged: _busy ? null : _setEnabled,
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _testRelay,
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text('Test relay'),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _unlinkRelay,
                      icon: const Icon(Icons.link_off_rounded),
                      label: const Text('Remove from Fox'),
                    ),
                  ],
                ),
                if (_health != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_health!, style: Ox.body(13, color: Ox.secondary))),
              ] else if (!_loading) ...[
                const SizedBox(height: 16),
                Text('No relay is currently configured in Fox.', style: Ox.body(14, color: Ox.secondary)),
              ],
              const SizedBox(height: 18),
              Text('My relays', style: Ox.body(15, weight: FontWeight.w600)),
              if (_records.isEmpty)
                Padding(padding: const EdgeInsets.only(top: 8), child: Text('No relays have been deployed from this device yet.', style: Ox.body(13, color: Ox.secondary))),
              for (final relay in _records)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    active?.endpointKey == relay.endpointKey ? Icons.check_circle_outline_rounded : Icons.cloud_outlined,
                    color: active?.endpointKey == relay.endpointKey ? Ox.success : Ox.tertiary,
                  ),
                  title: Text(relay.scriptName, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    active?.endpointKey == relay.endpointKey
                        ? (active.enabled ? 'Active' : 'Current, disabled')
                        : Uri.tryParse(relay.publicUrl)?.host ?? relay.publicUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Forget from this device',
                    onPressed: _busy ? null : () => _forget(relay),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ),
              if (_records.isNotEmpty)
                Text(
                  'Forgetting an entry only removes it from this device. Delete the Worker in your Cloudflare dashboard if you want to shut it down.',
                  style: Ox.body(12, color: Ox.tertiary),
                ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : () => openExternal('https://dash.cloudflare.com'),
                  icon: const Icon(Icons.open_in_new_rounded, size: 17),
                  label: const Text('Open Cloudflare dashboard'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FoxSignIn extends StatefulWidget {
  const _FoxSignIn({required this.backend});
  final CoreBackend backend;
  @override
  State<_FoxSignIn> createState() => _FoxSignInState();
}

class _FoxSignInState extends State<_FoxSignIn> {
  final email = TextEditingController();
  final password = TextEditingController();
  final answer = TextEditingController();
  Map<String, dynamic>? session;
  String? error;
  bool busy = false;
  Timer? poll;
  bool polling = false;

  @override
  void dispose() {
    poll?.cancel();
    final id = session?['id'];
    final step = session?['step'];
    if (id is String && !const ['done', 'failed', 'cancelled'].contains(step)) {
      unawaited(widget.backend.foxRequest('DELETE', '/api/signin/${Uri.encodeComponent(id)}').catchError((_) => <String, dynamic>{}));
    }
    email.dispose(); password.dispose(); answer.dispose();
    super.dispose();
  }

  void apply(Map<String, dynamic> next) {
    if (!mounted) return;
    setState(() { session = next; busy = false; error = next['error'] as String?; });
    if (const ['done', 'failed', 'cancelled'].contains(next['step'])) poll?.cancel();
  }

  Future<void> start() async {
    if (email.text.trim().isEmpty || password.text.isEmpty) {
      setState(() => error = 'Enter your email and password.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final result = await widget.backend.foxRequest('POST', '/api/signin', {'email': email.text.trim(), 'password': password.text});
      if (!mounted) {
        final id = result['id'];
        if (id is String && !const ['done', 'failed', 'cancelled'].contains(result['step'])) {
          unawaited(widget.backend.foxRequest('DELETE', '/api/signin/${Uri.encodeComponent(id)}').catchError((_) => <String, dynamic>{}));
        }
        return;
      }
      password.clear();
      apply(result);
      poll?.cancel();
      if (!const ['done', 'failed', 'cancelled'].contains(result['step'])) {
        poll = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(check()));
        unawaited(check());
      }
    } catch (e) {
      if (mounted) {
        password.clear();
        setState(() { busy = false; error = e.toString(); });
      }
    }
  }

  Future<void> check() async {
    final id = session?['id'];
    if (polling || busy || id is! String || !mounted) return;
    polling = true;
    try { apply(await widget.backend.foxRequest('GET', '/api/signin/${Uri.encodeComponent(id)}')); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { polling = false; }
  }

  Future<void> submit() async {
    final id = session?['id'];
    if (id is! String) return;
    final value = session?['step'] == 'need_email_link' ? 'continue' : answer.text.trim();
    if (value.isEmpty) { setState(() => error = 'Enter the requested code.'); return; }
    setState(() { busy = true; error = null; });
    try {
      final next = await widget.backend.foxRequest('POST', '/api/signin/${Uri.encodeComponent(id)}', {'value': value});
      answer.clear();
      apply(next);
      unawaited(check());
    } catch (e) { if (mounted) setState(() { busy = false; error = e.toString(); }); }
  }

  Uint8List? captchaBytes() {
    final data = session?['captcha'];
    if (data is! String || !data.startsWith('data:image/')) return null;
    final comma = data.indexOf(',');
    if (comma < 0 || !data.substring(0, comma).contains(';base64')) return null;
    try { return base64Decode(data.substring(comma + 1)); } catch (_) { return null; }
  }

  @override
  Widget build(BuildContext context) {
    final step = session?['step'] as String?;
    final needsAnswer = step?.startsWith('need_') == true;
    final captcha = captchaBytes();
    return AlertDialog(
      title: const Text('Add Firefox Account'),
      content: SingleChildScrollView(child: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Unofficial client. Your account is sent to Mozilla for sign-in.'),
        const SizedBox(height: 14),
        if (session == null) ...[
          TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Email')),
          TextField(controller: password, obscureText: true, autofillHints: const [AutofillHints.password], decoration: const InputDecoration(labelText: 'Password'), onSubmitted: (_) => busy ? null : start()),
        ] else ...[
          Text('${session?['message'] ?? 'Signing in…'}'),
          if (step == 'working') const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          if (captcha != null) Padding(padding: const EdgeInsets.only(top: 12), child: Image.memory(captcha, height: 80, errorBuilder: (_, __, ___) => const Text('Could not display CAPTCHA.'))),
          if (needsAnswer && step != 'need_email_link') TextField(controller: answer, decoration: const InputDecoration(labelText: 'Verification code or answer'), onSubmitted: (_) => busy ? null : submit()),
        ],
        if (error != null && error!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(step == 'done' ? 'Close' : 'Cancel')),
        if (session == null) FilledButton(onPressed: busy ? null : start, child: const Text('Sign in')),
        if (needsAnswer) FilledButton(onPressed: busy ? null : submit, child: Text(step == 'need_email_link' ? 'I opened the link' : 'Continue')),
      ],
    );
  }
}
