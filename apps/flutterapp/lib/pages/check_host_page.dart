import 'package:flutter/material.dart';

import '../api/vexo_api.dart';
import '../widgets/vexo_theme.dart';

class CheckHostPage extends StatefulWidget {
  const CheckHostPage({super.key, required this.api});
  final VexoApi api;
  @override
  State<CheckHostPage> createState() => _CheckHostPageState();
}

class _CheckHostPageState extends State<CheckHostPage> {
  final _host = TextEditingController(text: 'vexostream.bond');
  final _port = TextEditingController();
  static const _countries = <(String, String)>[
    ('ir', 'Iran'), ('us', 'United States'), ('de', 'Germany'),
    ('gb', 'United Kingdom'), ('fr', 'France'), ('nl', 'Netherlands'),
  ];
  final Set<String> _selectedCountries = {'ir', 'us', 'de', 'gb', 'fr', 'nl'};
  String _type = 'http';
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _result = {};
  @override
  void dispose() { _host.dispose(); _port.dispose(); super.dispose(); }

  Future<void> _run() async {
    if (_busy) return;
    if (_host.text.trim().isEmpty) { setState(() => _error = 'Enter a domain or URL.'); return; }
    final port = _port.text.trim();
    if (_type == 'tcp' && port.isNotEmpty && (int.tryParse(port) == null || int.parse(port) < 1 || int.parse(port) > 65535)) {
      setState(() => _error = 'Port must be between 1 and 65535.');
      return;
    }
    setState(() { _busy = true; _error = null; _result = {}; });
    try {
      final result = asMap(await widget.api.get('/check-host/start', query: {
        'host': _host.text.trim(), 'type': _type,
        'cc': _selectedCountries.join(','),
        if (_type == 'tcp' && port.isNotEmpty) 'port': port,
      }));
      final combined = <String, dynamic>{...result, 'target': result['target'] ?? _host.text.trim(), 'results': <String, dynamic>{}};
      if (mounted) setState(() => _result = Map<String, dynamic>.from(combined));
      final id = (result['id'] ?? '').toString();
      if (id.isNotEmpty) {
        final regionalResults = <String, dynamic>{};
        var failures = 0;
        var complete = false;
        for (var i = 0; i < 19; i++) {
          await Future<void>.delayed(Duration(milliseconds: i < 4 ? 800 : 1300));
          if (!mounted) return;
          try {
            final update = asMap(await widget.api.get('/check-host/result', query: {'id': id, 'type': _type}));
            if (update['ok'] != true) throw ApiException((update['error'] ?? 'Regional request failed.').toString());
            failures = 0;
            regionalResults.addAll(asMap(update['results']));
            final nodes = asList(update['nodes']);
            if (nodes.isNotEmpty) combined['nodes'] = nodes;
            combined['results'] = {...regionalResults};
            final currentNodes = asList(combined['nodes']).map(asMap).toList();
            final allDone = currentNodes.isNotEmpty && currentNodes.every((node) => asMap(regionalResults[(node['id'] ?? '').toString()])['done'] == true);
            complete = update['done'] == true && (allDone || currentNodes.isEmpty);
            if (complete && currentNodes.isEmpty) combined['notice'] = 'No regional probes were assigned. Showing the edge result.';
            if (mounted) setState(() => _result = Map<String, dynamic>.from(combined));
            if (complete) break;
          } catch (e) {
            failures++;
            if (failures >= 3) {
              combined['notice'] = 'Regional results could not be loaded after repeated attempts: $e';
              break;
            }
          }
        }
        if (!complete && failures < 3) combined['notice'] = 'Some regional probes did not finish before the timeout.';
      }
      if (mounted) setState(() { _result = combined; _busy = false; });
    } catch (e) { if (mounted) setState(() { _error = e.toString(); _busy = false; }); }
  }

  @override
  Widget build(BuildContext context) => PageBody(maxWidth: 980, children: [
        const PageHeading(kicker: 'Diagnostics', title: 'Check host', subtitle: 'Run safe diagnostics only on VexoStream-owned or explicitly authorized hosts.'),
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _host, enabled: !_busy, onSubmitted: (_) => _run(), decoration: const InputDecoration(labelText: 'Authorized host or URL', prefixIcon: Icon(Icons.dns_outlined))),
          const SizedBox(height: 14),
          Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 170, child: DropdownButtonFormField<String>(value: _type, decoration: const InputDecoration(labelText: 'Check type'), items: const [DropdownMenuItem(value: 'http', child: Text('HTTP')), DropdownMenuItem(value: 'ping', child: Text('Ping')), DropdownMenuItem(value: 'tcp', child: Text('TCP')), DropdownMenuItem(value: 'dns', child: Text('DNS'))], onChanged: _busy ? null : (v) => setState(() => _type = v ?? 'http'))),
            FilledButton.icon(onPressed: _busy ? null : _run, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded), label: const Text('Run check')),
          ]),
          if (_type == 'tcp') ...[
            const SizedBox(height: 16),
            TextField(controller: _port, keyboardType: TextInputType.number, maxLength: 5, decoration: const InputDecoration(labelText: 'TCP port', hintText: '443')),
          ],
          const SizedBox(height: 16),
          Text('Probe countries', style: Vx.sans(size: 14, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (code, name) in _countries)
              FilterChip(
                avatar: _flag(code),
                label: Text(name, style: TextStyle(
                  color: _selectedCountries.contains(code) ? const Color(0xFF071C38) : Vx.text,
                  fontWeight: FontWeight.w600,
                )),
                selected: _selectedCountries.contains(code),
                selectedColor: Vx.blue,
                backgroundColor: Vx.well,
                onSelected: _busy ? null : (selected) => setState(() {
                  if (selected) {
                    _selectedCountries.add(code);
                  } else if (_selectedCountries.length > 1) {
                    _selectedCountries.remove(code);
                  }
                }),
              ),
          ]),
          const SizedBox(height: 12),
          const Text('The API blocks private, local, reserved, and non-allowlisted targets. By default only vexostream.bond and its subdomains are allowed.', style: TextStyle(color: Vx.text2, height: 1.4)),
        ]))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Vx.red))))),
        if (_result.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_busy ? 'Checking regions…' : 'Check results', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _line('Target', (_result['target'] ?? _result['host'] ?? 'Unknown').toString()),
            _line('Type', (_result['type'] ?? _type).toString().toUpperCase()),
            _line('Regional provider', (_result['providerName'] ?? _result['provider'] ?? 'Edge only').toString()),
            if ((_result['notice'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_result['notice'].toString(), style: const TextStyle(color: Vx.amber))),
            if ((_result['error'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_result['error'].toString(), style: const TextStyle(color: Vx.red))),
            const Divider(height: 26),
            _beacons(),
            const SizedBox(height: 18),
            const Text('Regional probes', style: TextStyle(fontWeight: FontWeight.w700)),
            if (asList(_result['nodes']).isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_busy ? 'Assigning regional probes…' : 'No regional probes available.', style: const TextStyle(color: Vx.text3))),
            for (final raw in asList(_result['nodes']))
              Builder(builder: (context) {
                final node = asMap(raw);
                final data = asMap(asMap(_result['results'])[(node['id'] ?? '').toString()]);
                return _resultRow('${node['country'] ?? node['cc'] ?? 'Region'}${(node['city'] ?? '').toString().isEmpty ? '' : ', ${node['city']}'}', (node['label'] ?? '').toString(), data, country: (node['cc'] ?? '').toString().toLowerCase());
              }),
            if (asMap(_result['edge']).isNotEmpty) ...[
              const Divider(height: 30),
              _resultRow('VexoStream edge', 'Cloudflare${(_result['edge']['colo'] ?? '').toString().isEmpty ? '' : ' · ${_result['edge']['colo']}'}', asMap(_result['edge'])),
            ],
          ]))),
        ],
      ]);

  Widget _line(String title, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [SizedBox(width: 145, child: Text(title, style: const TextStyle(color: Vx.text3))), Expanded(child: Text(value))]));
  String _verdict(Map<String, dynamic> data) {
    if (data['supported'] == false) return 'Not supported at edge';
    if (data['done'] != true) return _busy ? 'Checking' : 'No result';
    if ((data['error'] ?? '').toString().isNotEmpty && data['ok'] != true) return data['error'].toString();
    if (_type == 'http') {
      final code = int.tryParse('${data['code'] ?? ''}');
      return code == null ? 'Failed' : '$code ${data['message'] ?? ''}'.trim();
    }
    if (_type == 'ping') return '${data['recv'] ?? 0} / ${data['sent'] ?? 0} replies';
    if (_type == 'dns') return '${asList(data['A']).length + asList(data['AAAA']).length} records';
    return data['ok'] == true ? 'Connected' : 'Failed';
  }

  bool _healthy(Map<String, dynamic> data) {
    if (data['done'] != true || data['ok'] != true) return false;
    if (_type == 'http') return (int.tryParse('${data['code'] ?? ''}') ?? 999) < 400;
    return true;
  }

  String _time(dynamic value) {
    final n = value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
    return n == null ? '—' : '${(n * 1000).toStringAsFixed(0)} ms';
  }

  String _detail(Map<String, dynamic> data) {
    if (data['supported'] == false) return (data['error'] ?? '').toString();
    if (data['done'] != true) return '';
    if (_type == 'dns') {
      final records = [...asList(data['A']), ...asList(data['AAAA'])].join(', ');
      return '$records${data['ttl'] == null ? '' : ' · TTL ${data['ttl']} s'}';
    }
    final timing = _type == 'ping' ? '${_time(data['min'])} / ${_time(data['avg'])} / ${_time(data['max'])}' : _time(data['time']);
    return '$timing${(data['ip'] ?? '').toString().isEmpty ? '' : ' · ${data['ip']}'}';
  }

  Widget _flag(String code) {
    if (!_countries.any((country) => country.$1 == code)) {
      return const Icon(Icons.public_rounded, size: 18);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Image.asset('assets/flags/$code.png', width: 24, height: 16, fit: BoxFit.cover, excludeFromSemantics: true),
    );
  }

  Widget _resultRow(String location, String subtitle, Map<String, dynamic> data, {String country = ''}) {
    final pending = data['done'] != true && data['supported'] != false;
    final color = pending ? Vx.text3 : _healthy(data) ? Vx.green : Vx.red;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (country.isNotEmpty) _flag(country) else Icon(Icons.public_rounded, color: color, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(location, style: const TextStyle(fontWeight: FontWeight.w700)),
        if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(color: Vx.text3)),
        if (_detail(data).isNotEmpty) SelectableText(_detail(data), style: const TextStyle(color: Vx.text2)),
      ])),
      const SizedBox(width: 12),
      Flexible(child: Text(_verdict(data), textAlign: TextAlign.right, style: TextStyle(color: color, fontWeight: FontWeight.w700))),
    ]));
  }

  Widget _beacons() {
    final nodes = asList(_result['nodes']).map(asMap).toList();
    final results = asMap(_result['results']);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final (code, name) in _countries)
        Builder(builder: (context) {
          final mine = nodes.where((n) => n['cc'] == code).toList();
          final done = mine.where((n) => asMap(results[(n['id'] ?? '').toString()])['done'] == true).length;
          final up = mine.where((n) => _healthy(asMap(results[(n['id'] ?? '').toString()]))).length;
          final state = !_selectedCountries.contains(code) ? 'off' : mine.isEmpty ? (_busy ? 'checking' : 'no server') : done < mine.length ? '$done/${mine.length} checking' : '$up/${mine.length} up';
          final color = mine.isEmpty || done < mine.length ? Vx.text2 : up > 0 ? Vx.green : Vx.red;
          return Chip(
            avatar: _flag(code),
            label: RichText(text: TextSpan(style: Vx.sans(size: 13, color: Vx.text), children: [
              TextSpan(text: '$name · '),
              TextSpan(text: state, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ])),
          );
        }),
    ]);
  }
}
