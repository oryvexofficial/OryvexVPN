import 'package:flutter/material.dart';

import '../api/vexo_api.dart';
import '../widgets/vexo_theme.dart';
import '../widgets/video_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.api, required this.onPlay, required this.onBrowse, required this.onSearch});
  final VexoApi api;
  final ValueChanged<Map<String, dynamic>> onPlay;
  final ValueChanged<String> onBrowse;
  final void Function(String query, String provider) onSearch;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _link = TextEditingController();
  List<Map<String, dynamic>> _videos = [];
  List<Map<String, dynamic>> _providers = [];
  String _provider = '';
  String _defaultQuery = 'trending';
  String? _error;
  String? _hint;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final config = asMap(await widget.api.get('/config'));
      _providers = asList(config['providers']).map(asMap).toList();
      _provider = (config['defaultProvider'] ?? '').toString();
      _defaultQuery = defaultSearchQuery(config);
      if (_provider.isNotEmpty) {
        _videos = videoItems(await widget.api.get('/catalog', query: {'provider': _provider, 'q': _defaultQuery, 'page': 1})).take(16).toList();
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  void _play() {
    var value = _link.text.trim();
    if (value.isEmpty) {
      setState(() => _hint = 'Paste a link or a viewkey first.');
      return;
    }
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(value)) {
      final m = RegExp(r'viewkey=([a-zA-Z0-9]+)').firstMatch(value) ?? RegExp(r'^([a-zA-Z0-9]{8,24})$').firstMatch(value);
      if (m == null) {
        setState(() => _hint = 'That doesn’t look like a link or a viewkey.');
        return;
      }
      value = 'https://www.pornhub.com/view_video.php?viewkey=${m.group(1)}';
    }
    setState(() => _hint = null);
    widget.onPlay({'url': value, 'title': 'VexoStream player'});
  }

  @override
  Widget build(BuildContext context) {
    final live = _providers.where((p) => p['available'] == true).toList();
    return PageBody(children: [
      _hero(context, live),
      const SizedBox(height: 72),
      PageHeading(
        title: _defaultQuery.toLowerCase() == 'trending' ? 'Trending now' : '$_defaultQuery picks',
        subtitle: _provider.isEmpty ? null : 'Fresh from ${_nameOf(_provider)}.',
        large: false,
        trailing: OutlinedButton(onPressed: () => widget.onBrowse(_provider), child: const Text('See all')),
      ),
      if (_error != null)
        SizedBox(height: 300, child: ErrorPanel(message: _error!, onRetry: _load))
      else if (!_loading && _videos.isEmpty)
        Container(
          padding: const EdgeInsets.all(28),
          decoration: Vx.surface(),
          child: Text('Nothing trending right now. The catalogue may be paused or the backend is offline.', style: Theme.of(context).textTheme.bodyMedium),
        )
      else
        VideoGrid(api: widget.api, items: _videos, onPlay: widget.onPlay, loading: _loading, skeletons: 8),
      if (_providers.isNotEmpty) ...[
        const SizedBox(height: 64),
        const PageHeading(title: 'Libraries', subtitle: 'Every source, one player.', large: false),
        _libraries(),
      ],
    ]);
  }

  String _nameOf(String id) {
    for (final p in _providers) {
      if (p['id'] == id) return (p['name'] ?? id).toString();
    }
    return id;
  }

  Widget _hero(BuildContext context, List<Map<String, dynamic>> live) {
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, c) {
      final size = c.maxWidth > 1100 ? 96.0 : c.maxWidth > 720 ? 72.0 : 48.0;
      return Padding(
        padding: const EdgeInsets.only(top: 40),
        child: Column(children: [
          const StatusPill(label: 'Free, ad-free HD player'),
          const SizedBox(height: 28),
          Text.rich(
            TextSpan(children: const [
              TextSpan(text: 'Paste a link. '),
              TextSpan(text: 'Press play.', style: TextStyle(color: Vx.blue)),
            ]),
            textAlign: TextAlign.center,
            style: Vx.sans(size: size, weight: FontWeight.w600, height: .98, spacing: -size * .055),
          ),
          const SizedBox(height: 22),
          Text('Every quality, no ads, streamed straight from the edge.', textAlign: TextAlign.center, style: t.bodyLarge?.copyWith(fontSize: 20, color: Vx.text2)),
          const SizedBox(height: 40),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Container(
              height: 64,
              padding: const EdgeInsets.only(left: 22, right: 8),
              decoration: BoxDecoration(
                color: Vx.panel,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Vx.line),
                boxShadow: [BoxShadow(color: Vx.blue.withValues(alpha: .22), blurRadius: 60, offset: const Offset(0, 24), spreadRadius: -32)],
              ),
              child: Row(children: [
                const Icon(Icons.link_rounded, color: Vx.text3, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _link,
                    onSubmitted: (_) => _play(),
                    onChanged: (_) {
                      if (_hint != null) setState(() => _hint = null);
                    },
                    style: Vx.sans(size: 17),
                    decoration: const InputDecoration(
                      hintText: 'Paste a link or viewkey',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _play,
                  style: FilledButton.styleFrom(minimumSize: const Size(112, 48)),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Play'),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text(_hint ?? 'Works with links from every library below.', style: t.bodySmall?.copyWith(fontSize: 14, color: _hint == null ? Vx.text3 : Vx.red)),
          if (live.isNotEmpty) ...[
            const SizedBox(height: 26),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              for (final p in live) _SourceChip(id: (p['id'] ?? '').toString(), name: (p['name'] ?? '').toString(), onTap: () => widget.onBrowse((p['id'] ?? '').toString())),
            ]),
          ],
        ]),
      );
    });
  }

  Widget _libraries() => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 1000 ? 3 : c.maxWidth > 620 ? 2 : 1;
        final w = (c.maxWidth - 14 * (cols - 1)) / cols;
        return Wrap(spacing: 14, runSpacing: 14, children: [
          for (final p in _providers) SizedBox(width: w, child: _LibraryTile(provider: p, onTap: () => widget.onBrowse((p['id'] ?? '').toString()))),
        ]);
      });
}

class _SourceChip extends StatefulWidget {
  const _SourceChip({required this.id, required this.name, required this.onTap});
  final String id;
  final String name;
  final VoidCallback onTap;
  @override
  State<_SourceChip> createState() => _SourceChipState();
}

class _SourceChipState extends State<_SourceChip> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 38,
            padding: const EdgeInsets.only(left: 6, right: 15),
            decoration: BoxDecoration(
              color: _hover ? Vx.well : Vx.panel,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _hover ? Vx.blue.withValues(alpha: .5) : Vx.line),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ProviderIcon(id: widget.id, name: widget.name, size: 26),
              const SizedBox(width: 9),
              Text(widget.name, style: Vx.sans(size: 14, weight: FontWeight.w500)),
            ]),
          ),
        ),
      );
}

class _LibraryTile extends StatefulWidget {
  const _LibraryTile({required this.provider, required this.onTap});
  final Map<String, dynamic> provider;
  final VoidCallback onTap;
  @override
  State<_LibraryTile> createState() => _LibraryTileState();
}

class _LibraryTileState extends State<_LibraryTile> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final id = (p['id'] ?? '').toString();
    final name = (p['name'] ?? id).toString();
    final live = p['available'] == true;
    return MouseRegion(
      cursor: live ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: live ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _hover && live ? Vx.well : Vx.panel,
            borderRadius: BorderRadius.circular(Vx.radiusXl),
            border: Border.all(color: _hover && live ? Vx.ringStrong : Vx.line),
          ),
          child: Row(children: [
            ProviderIcon(id: id, name: name, size: 44),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: Vx.sans(size: 16, weight: FontWeight.w600)),
                const SizedBox(height: 3),
                Text(live ? (p['domain'] ?? '').toString() : 'Currently unavailable', style: Vx.sans(size: 13, color: Vx.text3)),
              ]),
            ),
            StatusPill(label: live ? 'On air' : 'Off air', color: live ? Vx.green : Vx.text3, dense: true),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: _hover && live ? Vx.text : Vx.text3),
          ]),
        ),
      ),
    );
  }
}
