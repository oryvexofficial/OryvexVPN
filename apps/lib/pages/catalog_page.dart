import 'package:flutter/material.dart';

import '../api/vexo_api.dart';
import '../widgets/vexo_theme.dart';
import '../widgets/video_card.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, required this.api, required this.onPlay, this.initialQuery = '', this.initialProvider = ''});
  final VexoApi api;
  final ValueChanged<Map<String, dynamic>> onPlay;
  final String initialQuery;
  final String initialProvider;

  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _videos = [];
  String _provider = '';
  String _q = '';
  String _defaultQuery = 'trending';
  int _page = 1;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _q = widget.initialQuery;
    _query.text = _q;
    _provider = widget.initialProvider;
    _init();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final config = asMap(await widget.api.get('/config'));
      _providers = asList(config['providers']).map(asMap).where((p) => p['available'] == true).toList();
      _defaultQuery = defaultSearchQuery(config);
      if (_q.isEmpty) {
        _q = _defaultQuery;
        _query.text = _q;
      }
      if (_provider.isEmpty || !_providers.any((p) => p['id'] == _provider)) _provider = (config['defaultProvider'] ?? '').toString();
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _load() async {
    if (_provider.isEmpty) {
      setState(() {
        _loading = false;
        _videos = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.api.get('/catalog', query: {'provider': _provider, 'q': _q.isEmpty ? _defaultQuery : _q, 'page': _page});
      _videos = videoItems(result);
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

  void _search() {
    setState(() {
      _q = _query.text.trim().isEmpty ? _defaultQuery : _query.text.trim();
      _query.text = _q;
      _page = 1;
    });
    _load();
  }

  String get _providerName {
    for (final p in _providers) {
      if (p['id'] == _provider) return (p['name'] ?? _provider).toString();
    }
    return _provider;
  }

  @override
  Widget build(BuildContext context) {
    final searching = _q.isNotEmpty;
    return PageBody(children: [
      PageHeading(
        kicker: searching ? 'Search' : 'Browse',
        title: searching ? '“$_q”' : 'Trending on $_providerName',
        subtitle: searching ? 'Results from $_providerName · page $_page' : 'No ads, every quality from 240p to 4K · page $_page',
      ),
      Row(children: [
        Expanded(
          child: TextField(
            controller: _query,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: 'Search videos',
              prefixIcon: const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.search_rounded)),
              suffixIcon: _q.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Restore default search',
                      onPressed: () {
                        _query.clear();
                        _search();
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        FilledButton(onPressed: _search, style: FilledButton.styleFrom(minimumSize: const Size(110, 52)), child: const Text('Search')),
      ]),
      const SizedBox(height: 16),
      if (_providers.length > 1)
        Align(
          alignment: Alignment.centerLeft,
          child: PillTabs<String>(
            items: [for (final p in _providers) ((p['id'] ?? '').toString(), (p['name'] ?? '').toString())],
            value: _provider,
            iconFor: (id) => ProviderIcon(id: id, name: id, size: 22),
            onChanged: (id) {
              setState(() {
                _provider = id;
                _page = 1;
              });
              _load();
            },
          ),
        ),
      const SizedBox(height: 28),
      if (_error != null)
        SizedBox(height: 360, child: ErrorPanel(message: _error!, onRetry: _load))
      else if (!_loading && _videos.isEmpty)
        const SizedBox(height: 300, child: ErrorPanel(title: 'Nothing here.', message: 'Try another search or library.', icon: Icons.video_library_outlined))
      else
        VideoGrid(api: widget.api, items: _videos, onPlay: widget.onPlay, loading: _loading),
      if (_error == null && (_videos.isNotEmpty || _page > 1)) ...[
        const SizedBox(height: 36),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          OutlinedButton.icon(
            onPressed: _page > 1 && !_loading
                ? () {
                    setState(() => _page--);
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_left_rounded),
            label: const Text('Previous'),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Text('Page $_page', style: Vx.mono(size: 13, color: Vx.text2))),
          OutlinedButton.icon(
            onPressed: _videos.isNotEmpty && !_loading
                ? () {
                    setState(() => _page++);
                    _load();
                  }
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
            label: const Text('Next'),
            iconAlignment: IconAlignment.end,
          ),
        ]),
      ],
    ]);
  }
}
