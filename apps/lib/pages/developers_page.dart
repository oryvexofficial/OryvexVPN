import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/vexo_api.dart';
import '../widgets/vexo_theme.dart';

class DevelopersPage extends StatefulWidget {
  const DevelopersPage({super.key, required this.api});
  final VexoApi api;
  @override
  State<DevelopersPage> createState() => _DevelopersPageState();
}

class _DevelopersPageState extends State<DevelopersPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { _data = asMap(await widget.api.get('/developers')); if (mounted) setState(() => _loading = false); }
    catch (e) { if (mounted) setState(() { _error = e.toString(); _loading = false; }); }
  }
  Future<void> _copy(String value) async { await Clipboard.setData(ClipboardData(text: value)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard'))); }

  @override
  Widget build(BuildContext context) => PageBody(maxWidth: 980, children: [
        const PageHeading(kicker: 'Developers', title: 'Embed the player', subtitle: 'Embed snippets and documented endpoints for VexoStream.'),
        if (_loading) const SizedBox(height: 200, child: PageLoader())
        else if (_error != null) ErrorPanel(message: _error!, onRetry: _load)
        else ...[
          Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Embed player', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 10),
            SelectableText((_data['embed'] ?? '<iframe src="https://vexostream.bond/embed?url=VIDEO_URL"></iframe>').toString(), style: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['Cascadia Mono'], color: Vx.text2, height: 1.45)),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () => _copy((_data['embed'] ?? '').toString()), icon: const Icon(Icons.copy_rounded), label: const Text('Copy snippet')),
          ]))),
          const SizedBox(height: 18),
          const Text('API endpoints', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          const SizedBox(height: 8),
          ...asList(_data['endpoints']).map((entry) { final e = asMap(entry); return Card(child: ListTile(leading: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), decoration: BoxDecoration(color: Vx.blue.withValues(alpha: .18), borderRadius: BorderRadius.circular(6)), child: Text((e['method'] ?? 'GET').toString(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))), title: SelectableText('https://api.vexostream.bond${e['path'] ?? ''}', style: const TextStyle(fontFamily: 'Consolas', fontFamilyFallback: ['Cascadia Mono'], fontSize: 13)), subtitle: Text('Auth: ${e['auth'] == false ? 'not required' : e['auth']}', style: const TextStyle(color: Vx.text3)))); }),
          const SizedBox(height: 14),
          const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('The Worker keeps EDGE_TOKEN private. Native app sessions use revocable bearer tokens. Catalog and stream extraction also require the configured VexoStream Core backend.', style: TextStyle(color: Vx.text2, height: 1.45)))),
        ],
      ]);
}
