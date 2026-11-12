import 'dart:convert';

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
  String _type = 'http';
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _result = {};
  @override
  void dispose() { _host.dispose(); super.dispose(); }

  Future<void> _run() async {
    if (_host.text.trim().isEmpty) { setState(() => _error = 'Enter a domain or URL.'); return; }
    setState(() { _busy = true; _error = null; _result = {}; });
    try {
      var result = asMap(await widget.api.get('/check-host/start', query: {'host': _host.text.trim(), 'type': _type}));
      final id = (result['id'] ?? '').toString();
      if (id.isNotEmpty) {
        for (var i = 0; i < 7 && result['done'] != true; i++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          result = asMap(await widget.api.get('/check-host/result', query: {'id': id, 'type': _type}));
        }
      }
      if (mounted) setState(() { _result = result; _busy = false; });
    } catch (e) { if (mounted) setState(() { _error = e.toString(); _busy = false; }); }
  }

  @override
  Widget build(BuildContext context) => PageBody(maxWidth: 980, children: [
        const PageHeading(kicker: 'Diagnostics', title: 'Check host', subtitle: 'Run safe diagnostics only on VexoStream-owned or explicitly authorized hosts.'),
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: TextField(controller: _host, onSubmitted: (_) => _run(), decoration: const InputDecoration(labelText: 'Authorized host or URL', prefixIcon: Icon(Icons.dns_outlined)))), const SizedBox(width: 12), SizedBox(width: 170, child: DropdownButtonFormField<String>(value: _type, decoration: const InputDecoration(labelText: 'Check type'), items: const [DropdownMenuItem(value: 'http', child: Text('HTTP')), DropdownMenuItem(value: 'ping', child: Text('Ping')), DropdownMenuItem(value: 'tcp', child: Text('TCP')), DropdownMenuItem(value: 'dns', child: Text('DNS'))], onChanged: (v) => setState(() => _type = v ?? 'http'))), const SizedBox(width: 12), FilledButton.icon(onPressed: _busy ? null : _run, icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.play_arrow_rounded), label: const Text('Run check'))]),
          const SizedBox(height: 12),
          const Text('The API blocks private, local, reserved, and non-allowlisted targets. By default only vexostream.bond and its subdomains are allowed.', style: TextStyle(color: Vx.text3, height: 1.4)),
        ]))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: const TextStyle(color: Vx.red))))),
        if (_result.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((_result['ok'] == true ? 'Check complete' : 'Check result'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _line('Target', (_result['target'] ?? _result['host'] ?? 'Unknown').toString()),
            _line('Type', (_result['type'] ?? _type).toString().toUpperCase()),
            _line('Regional provider', (_result['providerName'] ?? _result['provider'] ?? 'Edge only').toString()),
            if ((_result['notice'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_result['notice'].toString(), style: const TextStyle(color: Vx.amber))),
            if ((_result['error'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_result['error'].toString(), style: const TextStyle(color: Vx.red))),
            const Divider(height: 26),
            const Text('Edge result', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SelectableText(_pretty(_result['edge'] ?? _result['results'] ?? _result), style: const TextStyle(color: Vx.text2, fontFamily: 'Consolas', fontFamilyFallback: ['Cascadia Mono'], height: 1.4)),
          ]))),
        ],
      ]);

  Widget _line(String title, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [SizedBox(width: 145, child: Text(title, style: const TextStyle(color: Vx.text3))), Expanded(child: Text(value))]));
  String _pretty(dynamic value) { try { return value is String ? value : const JsonEncoder.withIndent('  ').convert(value); } catch (_) { return value.toString(); } }
}
