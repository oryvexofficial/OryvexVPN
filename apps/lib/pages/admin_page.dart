import 'package:flutter/material.dart';

import '../api/vexo_api.dart';
import '../widgets/vexo_theme.dart';

class AdminPage extends StatefulWidget {
  const AdminPage({super.key, required this.api});
  final VexoApi api;

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _query = TextEditingController();
  final _backend = TextEditingController();
  List<Map<String, dynamic>> _providers = [];
  String _provider = '';
  bool _maintenance = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _saved;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _backend.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; _saved = null; });
    try {
      final data = asMap(await widget.api.get('/admin', authenticated: true));
      _providers = asList(data['providers']).map(asMap).toList();
      _query.text = (data['defaultQuery'] ?? '').toString();
      _backend.text = (data['backendUrl'] ?? '').toString();
      _provider = (data['defaultProvider'] ?? '').toString();
      _maintenance = data['maintenanceOn'] == true;
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _save({bool? maintenance}) async {
    setState(() { _saving = true; _error = null; _saved = null; });
    try {
      final data = asMap(await widget.api.post('/admin/settings', authenticated: true, body: {
        'defaultQuery': _query.text.trim(),
        'defaultProvider': _provider,
        'maintenanceOn': maintenance ?? _maintenance,
        'backendUrl': _backend.text.trim(),
      }));
      _maintenance = data['maintenanceOn'] == true;
      _provider = (data['defaultProvider'] ?? _provider).toString();
      _query.text = (data['defaultQuery'] ?? _query.text).toString();
      _backend.text = (data['backendUrl'] ?? _backend.text).toString();
      if (mounted) setState(() { _saving = false; _saved = 'Owner settings saved.'; });
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(maxWidth: 900, children: [
        const PageHeading(kicker: 'Owner', title: 'Admin dashboard', subtitle: 'Manage the Core backend, maintenance mode, and default browsing settings.'),
        if (_loading)
          const SizedBox(height: 260, child: PageLoader(label: 'Loading owner settings…'))
        else if (_error != null && _providers.isEmpty)
          SizedBox(height: 320, child: ErrorPanel(message: _error!, onRetry: _load))
        else ...[
          Container(
            padding: const EdgeInsets.all(22),
            decoration: Vx.surface(radius: Vx.radius2xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('SITE MODE', style: Vx.mono(size: 12, spacing: 1.3)),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _maintenance,
                onChanged: _saving ? null : (value) { setState(() => _maintenance = value); _save(maintenance: value); },
                title: Text(_maintenance ? 'Maintenance is on' : 'Site is live', style: Vx.sans(size: 16, weight: FontWeight.w600)),
                subtitle: const Text('When enabled, visitors see the maintenance page. Owner API access remains available.'),
                secondary: Icon(_maintenance ? Icons.build_circle_outlined : Icons.check_circle_outline_rounded, color: _maintenance ? Vx.amber : Vx.green),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: Vx.surface(radius: Vx.radius2xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CORE BACKEND', style: Vx.mono(size: 12, spacing: 1.3)),
              const SizedBox(height: 12),
              TextField(controller: _backend, maxLength: 240, decoration: const InputDecoration(labelText: 'Backend URL', hintText: 'https://your-core-service.example')),
              const SizedBox(height: 8),
              Text('Use your public VexoStream Core origin. Private and local addresses are blocked.', style: Vx.sans(size: 13, color: Vx.text3)),
            ]),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(22),
            decoration: Vx.surface(radius: Vx.radius2xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('DEFAULT BROWSING', style: Vx.mono(size: 12, spacing: 1.3)),
              const SizedBox(height: 18),
              TextField(controller: _query, maxLength: 100, decoration: const InputDecoration(labelText: 'Default search word', hintText: 'e.g. trending')),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _provider.isEmpty ? null : _provider,
                decoration: const InputDecoration(labelText: 'Default provider'),
                items: [for (final provider in _providers) DropdownMenuItem(value: (provider['id'] ?? '').toString(), child: Text('${(provider['name'] ?? provider['id'] ?? '').toString()}${provider['mode'] == 'live' ? '' : ' (${provider['mode']})'}'))],
                onChanged: _saving ? null : (value) { if (value != null) setState(() => _provider = value); },
              ),
              const SizedBox(height: 18),
              Row(children: [
                FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Saving…' : 'Save settings')),
                const SizedBox(width: 14),
                if (_saved != null) Expanded(child: Text(_saved!, style: Vx.sans(size: 13, color: Vx.green))),
              ]),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(_error!, style: Vx.sans(size: 13, color: Vx.red))),
            ]),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(onPressed: _saving ? null : _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Reload settings')),
        ],
      ]);
}
