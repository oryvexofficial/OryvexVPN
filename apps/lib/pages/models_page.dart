import 'package:flutter/material.dart';

import '../api/vexo_api.dart';
import '../widgets/vexo_theme.dart';

class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key, required this.api, required this.onSignIn});
  final VexoApi api;
  final VoidCallback onSignIn;

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  final _search = TextEditingController();
  String _gender = 'women';
  int _page = 1;
  List<Map<String, dynamic>> _models = [];
  bool _loading = true;
  bool _hasMore = false;
  ApiException? _apiError;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _apiError = null;
    });
    try {
      final result = asMap(await widget.api.get('/models', query: {'gender': _gender, 'search': _search.text.trim(), 'page': _page}, authenticated: true));
      _models = asList(result['models'] ?? result['results'] ?? result['items'] ?? result['data']).map(asMap).toList();
      _hasMore = result['has_more'] == true || result['hasMore'] == true;
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

  void _open(Map<String, dynamic> model) {
    final slug = firstText(model, const ['slug', 'id']);
    if (slug.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModelProfilePage(api: widget.api, slug: slug, initial: model)));
  }

  @override
  Widget build(BuildContext context) => PageBody(children: [
        const PageHeading(kicker: 'Directory', title: 'Models', subtitle: 'Popular performers, sorted by popularity.'),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              onSubmitted: (_) {
                setState(() => _page = 1);
                _load();
              },
              decoration: const InputDecoration(hintText: 'Search by name', prefixIcon: Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.search_rounded))),
            ),
          ),
          const SizedBox(width: 12),
          PillTabs<String>(
            items: const [('women', 'Women'), ('both', 'Both'), ('men', 'Men')],
            value: _gender,
            onChanged: (g) {
              setState(() {
                _gender = g;
                _page = 1;
              });
              _load();
            },
          ),
        ]),
        const SizedBox(height: 28),
        if (_error != null)
          SizedBox(
            height: 380,
            child: ErrorPanel(
              message: _error!,
              onRetry: _load,
              action: _apiError?.needsLogin == true ? FilledButton(onPressed: widget.onSignIn, child: const Text('Log in')) : null,
            ),
          )
        else if (!_loading && _models.isEmpty)
          const SizedBox(height: 300, child: ErrorPanel(title: 'No models found.', message: 'Try another name or filter.', icon: Icons.person_search_rounded))
        else
          LayoutBuilder(builder: (context, c) {
            final cols = gridColumns(c.maxWidth, min: 190);
            final w = (c.maxWidth - 18 * (cols - 1)) / cols;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _loading ? 12 : _models.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 18, mainAxisSpacing: 26, mainAxisExtent: w * 4 / 3 + 58),
              itemBuilder: (context, i) {
                if (_loading) {
                  return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(aspectRatio: 3 / 4), SizedBox(height: 14), Skeleton(height: 12, width: 120, radius: 999)]);
                }
                final m = _models[i];
                return _ModelCard(api: widget.api, model: m, onTap: () => _open(m));
              },
            );
          }),
        if (_error == null && !_loading && _models.isNotEmpty) ...[
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            OutlinedButton(
                onPressed: _page > 1
                    ? () {
                        setState(() => _page--);
                        _load();
                      }
                    : null,
                child: const Text('Previous')),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 18), child: Text('Page $_page', style: Vx.mono(size: 13, color: Vx.text2))),
            OutlinedButton(
                onPressed: _hasMore
                    ? () {
                        setState(() => _page++);
                        _load();
                      }
                    : null,
                child: const Text('Next')),
          ]),
        ],
      ]);
}

class _ModelCard extends StatefulWidget {
  const _ModelCard({required this.api, required this.model, required this.onTap});
  final VexoApi api;
  final Map<String, dynamic> model;
  final VoidCallback onTap;
  @override
  State<_ModelCard> createState() => _ModelCardState();
}

class _ModelCardState extends State<_ModelCard> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    final name = firstText(m, const ['name', 'title'], fallback: 'Profile');
    final image = widget.api.imageUrl(firstText(m, const ['image_url', 'image', 'thumbnail_url', 'thumbnail', 'photo', 'avatar', 'picture']));
    final country = firstText(m, const ['country_name', 'country']);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Vx.radiusXl),
              child: Stack(fit: StackFit.expand, children: [
                const ColoredBox(color: Vx.well),
                if (image.isNotEmpty)
                  AnimatedScale(
                    scale: _hover ? 1.05 : 1,
                    duration: const Duration(milliseconds: 900),
                    curve: Vx.ease,
                    child: Image.network(image, headers: widget.api.imageHeaders, fit: BoxFit.cover, alignment: Alignment.topCenter, errorBuilder: (_, __, ___) => const Icon(Icons.person_outline_rounded, size: 46, color: Vx.text3)),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _hover ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(color: Vx.glass, borderRadius: BorderRadius.circular(999)),
                        child: Text('View profile', style: Vx.sans(size: 13, weight: FontWeight.w500, color: Colors.white)),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(Vx.radiusXl), border: Border.all(color: _hover ? Vx.ringStrong : Vx.ring)))),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Vx.sans(size: 16, weight: FontWeight.w600, color: _hover ? Vx.blue : Vx.text)),
          if (country.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(country, maxLines: 1, overflow: TextOverflow.ellipsis, style: Vx.sans(size: 13, color: Vx.text3))),
        ]),
      ),
    );
  }
}

class ModelProfilePage extends StatefulWidget {
  const ModelProfilePage({super.key, required this.api, required this.slug, required this.initial});
  final VexoApi api;
  final String slug;
  final Map<String, dynamic> initial;

  @override
  State<ModelProfilePage> createState() => _ModelProfilePageState();
}

class _ModelProfilePageState extends State<ModelProfilePage> {
  late Map<String, dynamic> _model = widget.initial;
  bool _loading = true;
  String? _error;
  int _photo = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.api.get('/models/${Uri.encodeComponent(widget.slug)}', authenticated: true);
      final map = asMap(result);
      _model = asMap(map['model'] ?? map['profile'] ?? result);
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

  List<String> get _photos {
    final list = asList(_model['gallery'] ?? _model['images'] ?? _model['photos'])
        .map((e) => e is Map ? (e['url'] ?? e['image_url'] ?? '').toString() : e.toString())
        .where((e) => e.startsWith('http') || e.startsWith('//'))
        .toList();
    final main = firstText(_model, const ['image_url', 'image', 'thumbnail_url', 'thumbnail', 'photo', 'avatar', 'picture']);
    if (main.isNotEmpty && !list.contains(main)) list.insert(0, main);
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final name = firstText(_model, const ['name', 'title'], fallback: 'Model profile');
    final summary = firstText(_model, const ['description', 'bio', 'about']);
    const hidden = {'image_url', 'image', 'thumbnail_url', 'thumbnail', 'photo', 'avatar', 'picture', 'gallery', 'images', 'photos', 'description', 'bio', 'about', 'slug', 'id', 'name', 'title', 'url', 'country_flag'};
    final details = _model.entries.where((e) => !hidden.contains(e.key) && e.value != null && e.value is! Map && e.value is! List && e.value.toString().trim().isNotEmpty).toList();
    final photos = _photos;
    final current = photos.isEmpty ? '' : widget.api.imageUrl(photos[_photo.clamp(0, photos.length - 1)]);

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: _loading
          ? const PageLoader(label: 'Loading profile…')
          : _error != null
              ? ErrorPanel(message: _error!, onRetry: _load)
              : PageBody(maxWidth: 1180, children: [
                  LayoutBuilder(builder: (context, c) {
                    final wide = c.maxWidth > 820;
                    final gallery = Column(children: [
                      AspectRatio(
                        aspectRatio: 3 / 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(Vx.radius2xl),
                          child: ColoredBox(
                            color: Vx.well,
                            child: current.isEmpty
                                ? const Icon(Icons.person_rounded, size: 80, color: Vx.text3)
                                : AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 400),
                                    child: Image.network(current, key: ValueKey(current), headers: widget.api.imageHeaders, fit: BoxFit.cover, alignment: Alignment.topCenter, width: double.infinity, height: double.infinity),
                                  ),
                          ),
                        ),
                      ),
                      if (photos.length > 1) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 74,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: photos.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (_, i) => GestureDetector(
                              onTap: () => setState(() => _photo = i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 56,
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(Vx.radiusMd), border: Border.all(color: i == _photo ? Vx.blue : Vx.line, width: 2)),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(Vx.radiusSm),
                                  child: Image.network(widget.api.imageUrl(photos[i]), headers: widget.api.imageHeaders, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Vx.well)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ]);
                    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('PROFILE', style: Vx.mono(size: 12, spacing: 1.4)),
                      const SizedBox(height: 10),
                      Text(name, style: Theme.of(context).textTheme.displayMedium?.copyWith(fontSize: 48)),
                      if (summary.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(summary, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Vx.text2)),
                      ],
                      const SizedBox(height: 24),
                      Container(
                        decoration: Vx.surface(),
                        child: Column(children: [
                          for (var i = 0; i < details.length; i++) ...[
                            if (i > 0) const Divider(),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                              child: Row(children: [
                                SizedBox(width: 150, child: Text(_label(details[i].key), style: Vx.sans(size: 14, color: Vx.text3))),
                                Expanded(child: Text(details[i].value.toString(), style: Vx.sans(size: 14, weight: FontWeight.w500))),
                              ]),
                            ),
                          ],
                          if (details.isEmpty) Padding(padding: const EdgeInsets.all(18), child: Text('No public details.', style: Vx.sans(size: 14, color: Vx.text3))),
                        ]),
                      ),
                    ]);
                    if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [gallery, const SizedBox(height: 28), info]);
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 380, child: gallery), const SizedBox(width: 40), Expanded(child: info)]);
                  }),
                ]),
    );
  }

  String _label(String value) => value
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .split(' ')
      .map((s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}')
      .join(' ');
}
