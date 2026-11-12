import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/vexo_api.dart';
import '../widgets/vexo_theme.dart';

class SocialPage extends StatefulWidget {
  const SocialPage({super.key, required this.api});
  final VexoApi api;
  @override
  State<SocialPage> createState() => _SocialPageState();
}

class _SocialPageState extends State<SocialPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _social = {};
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { _social = asMap(await widget.api.get('/social')); if (mounted) setState(() => _loading = false); }
    catch (e) { if (mounted) setState(() { _error = e.toString(); _loading = false; }); }
  }
  Future<void> _copy(String value) async { await Clipboard.setData(ClipboardData(text: value)); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied'))); }

  @override
  Widget build(BuildContext context) {
    final channel = asMap(_social['channel']);
    final channelUrl = (channel['url'] ?? '').toString();
    return PageBody(maxWidth: 980, children: [
      const PageHeading(kicker: 'Community', title: 'Social media', subtitle: 'Official community, social profiles, and VexoStream bots.'),
      if (_loading) const SizedBox(height: 200, child: PageLoader())
      else if (_error != null) ErrorPanel(message: _error!, onRetry: _load)
      else if (_social['enabled'] != true) const Card(child: Padding(padding: EdgeInsets.all(22), child: Text('The social page is currently hidden.')))
      else ...[
        if (channelUrl.isNotEmpty) Card(child: ListTile(leading: const Icon(Icons.forum_rounded, color: Vx.blue), title: Text((channel['title'] ?? 'VexoStream community').toString()), subtitle: Text(channelUrl), trailing: IconButton(onPressed: () => _copy(channelUrl), icon: const Icon(Icons.copy_rounded)))),
        const SizedBox(height: 10),
        _section('Social profiles', _linkWidgets(asMap(_social['links']))),
        const SizedBox(height: 16),
        _section('Bots and community tools', asList(_social['bots']).map((item) { final b = asMap(item); return Card(child: ListTile(leading: const Icon(Icons.smart_toy_outlined), title: Text((b['label'] ?? b['platform'] ?? 'Bot').toString()), subtitle: Text((b['url'] ?? '').toString(), maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(onPressed: () => _copy((b['url'] ?? '').toString()), icon: const Icon(Icons.copy_rounded)))); }).toList()),
      ],
    ]);
  }

  List<Widget> _linkWidgets(Map<String, dynamic> links) => links.entries.map((entry) => Card(child: ListTile(leading: const Icon(Icons.open_in_new_rounded), title: Text(_title(entry.key)), subtitle: Text(entry.value.toString(), maxLines: 1, overflow: TextOverflow.ellipsis), trailing: IconButton(onPressed: () => _copy(entry.value.toString()), icon: const Icon(Icons.copy_rounded))))).toList();
  Widget _section(String title, List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), const SizedBox(height: 8), if (children.isEmpty) const Text('No links configured yet.', style: TextStyle(color: Vx.text3)) else ...children]);
  String _title(String value) => value[0].toUpperCase() + value.substring(1);
}
