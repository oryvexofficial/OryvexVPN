import 'package:flutter/material.dart';

import '../api/vexo_api.dart';
import '../widgets/vexo_theme.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key, required this.api, required this.onSignIn, required this.onSignedOut, required this.onOpenAdmin});
  final VexoApi api;
  final VoidCallback onSignIn;
  final VoidCallback onSignedOut;
  final VoidCallback onOpenAdmin;
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _loading = true;
  String? _error;
  ApiException? _apiError;
  Map<String, dynamic> _account = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.api.hasToken) {
      setState(() {
        _loading = false;
        _error = 'Log in to see your account.';
        _apiError = const ApiException('', statusCode: 401);
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = asMap(await widget.api.get('/account', authenticated: true));
      _account = asMap(response['account']);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _apiError = e is ApiException ? e : null;
          _loading = false;
        });
      }
    }
  }

  Future<void> _signOut() async {
    try {
      await widget.api.post('/auth/logout', authenticated: true);
    } catch (_) {}
    await widget.api.clearToken();
    widget.onSignedOut();
  }

  @override
  Widget build(BuildContext context) {
    final name = (_account['username'] ?? 'Member').toString();
    final role = (_account['role'] ?? 'Member').toString();
    return PageBody(maxWidth: 760, children: [
      const PageHeading(kicker: 'Account', title: 'Your account', subtitle: 'Signed in on this computer.'),
      if (_loading)
        const SizedBox(height: 240, child: PageLoader(label: 'Loading account…'))
      else if (_error != null)
        SizedBox(
          height: 340,
          child: ErrorPanel(
            message: _error!,
            onRetry: _apiError?.needsLogin == true ? null : _load,
            action: _apiError?.needsLogin == true
                ? FilledButton(onPressed: widget.onSignIn, child: const Text('Log in'))
                : OutlinedButton(onPressed: _load, child: const Text('Try again')),
          ),
        )
      else
        Container(
          decoration: Vx.surface(radius: Vx.radius2xl),
          padding: const EdgeInsets.all(26),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: Vx.blue, borderRadius: BorderRadius.circular(18)),
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: Vx.sans(size: 24, weight: FontWeight.w700, color: Colors.white)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 6),
                  StatusPill(label: role, dense: true),
                ]),
              ),
            ]),
            const SizedBox(height: 22),
            const Divider(),
            _row('Account ID', (_account['id'] ?? '').toString()),
            _row('Joined', _accountDate('createdAt', 'Unknown')),
            _row('Last sign-in', _accountDate('lastLoginAt', 'Not available')),
            const SizedBox(height: 18),
            Text('App sessions last 30 days. Logging out ends this session right away.', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 18),
            if (_account['isOwner'] == true || role == 'Owner' || role == 'Admin') ...[
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: widget.onOpenAdmin, icon: const Icon(Icons.admin_panel_settings_outlined), label: const Text('Open Admin panel'))),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(onPressed: _signOut, icon: const Icon(Icons.logout_rounded, size: 18), label: const Text('Log out')),
          ]),
        ),
    ]);
  }

  String _accountDate(String key, String fallback) {
    final value = (_account[key] ?? '').toString().trim();
    return '${value.isEmpty ? fallback : value} UTC';
  }

  Widget _row(String title, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          SizedBox(width: 140, child: Text(title, style: Vx.sans(size: 14, color: Vx.text3))),
          Expanded(child: Text(value, style: Vx.mono(size: 13, color: Vx.text))),
        ]),
      );
}
