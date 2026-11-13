import 'package:flutter/material.dart';

import '../api/vexo_api.dart';
import '../widgets/vexo_theme.dart';
import 'model_profile_data.dart';

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
        else ...[
          if (!_loading && _page == 1 && _search.text.trim().isEmpty && _models.length >= 3) ...[
            Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Vx.line),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF14213A), Vx.panel, Vx.panel],
                  ),
                ),
                child: Column(children: [
                  Text('THE LEADERBOARD', textAlign: TextAlign.center, style: Vx.sans(size: 12, weight: FontWeight.w700, color: Vx.blue, spacing: 1.6)),
                  const SizedBox(height: 8),
                  Text('Most popular', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 5),
                  Text('Top three profiles right now', textAlign: TextAlign.center, style: Vx.sans(size: 14, color: Vx.text2)),
                  const SizedBox(height: 24),
                  LayoutBuilder(builder: (context, c) {
                    final width = (c.maxWidth - 20) / 3;
                    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      for (final index in [1, 0, 2]) ...[
                        if (index != 1) const SizedBox(width: 10),
                        SizedBox(
                          width: width,
                          child: _PodiumCard(api: widget.api, model: _models[index], rank: index + 1, onTap: () => _open(_models[index])),
                        ),
                      ],
                    ]);
                  }),
                ]),
              ),
            )),
            const SizedBox(height: 36),
            if (_models.length > 3) ...[
              Text('More profiles', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 18),
            ],
          ],
          LayoutBuilder(builder: (context, c) {
            final cols = gridColumns(c.maxWidth, min: 190);
            final w = (c.maxWidth - 18 * (cols - 1)) / cols;
            final skipTop = !_loading && _page == 1 && _search.text.trim().isEmpty && _models.length >= 3 ? 3 : 0;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _loading ? 12 : _models.length - skipTop,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: cols, crossAxisSpacing: 18, mainAxisSpacing: 26, mainAxisExtent: w * 4 / 3 + 58),
              itemBuilder: (context, i) {
                if (_loading) {
                  return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Skeleton(aspectRatio: 3 / 4), SizedBox(height: 14), Skeleton(height: 12, width: 120, radius: 999)]);
                }
                final m = _models[i + skipTop];
                return _ModelCard(api: widget.api, model: m, onTap: () => _open(m));
              },
            );
          }),
        ],
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

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({required this.api, required this.model, required this.rank, required this.onTap});
  final VexoApi api;
  final Map<String, dynamic> model;
  final int rank;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metal = rank == 1 ? const Color(0xFFEBC46C) : rank == 2 ? const Color(0xFFB8C4D5) : const Color(0xFFC89170);
    final name = firstText(model, const ['name', 'title'], fallback: 'Profile');
    final country = firstText(model, const ['country_name', 'country']);
    final image = api.imageUrl(firstText(model, const ['image_url', 'image', 'thumbnail_url', 'thumbnail', 'photo', 'avatar', 'picture']));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('●  RANK $rank', maxLines: 1, overflow: TextOverflow.ellipsis, style: Vx.sans(size: 11, color: metal, weight: FontWeight.w700, spacing: .5)),
      const SizedBox(height: 8),
      Semantics(
        button: true,
        label: 'Rank $rank, $name. View profile',
        child: Material(
          color: Vx.well,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AspectRatio(
                aspectRatio: rank == 1 ? 3 / 4.05 : 3 / 3.55,
                child: image.isEmpty
                    ? const ColoredBox(color: Vx.well2, child: Icon(Icons.person_outline_rounded, color: Vx.text3))
                    : Image.network(image, headers: api.imageHeaders, fit: BoxFit.cover, alignment: Alignment.topCenter,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: Vx.well2, child: Icon(Icons.person_outline_rounded, color: Vx.text3))),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 10, 9, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: Vx.sans(size: 14, weight: FontWeight.w700)),
                  if (country.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(country, maxLines: 1, overflow: TextOverflow.ellipsis, style: Vx.sans(size: 12, color: Vx.text2)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Container(
        height: rank == 1 ? 62 : rank == 2 ? 46 : 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(10), bottom: Radius.circular(3)),
          border: Border.all(color: metal.withValues(alpha: .35)),
          gradient: LinearGradient(colors: [metal.withValues(alpha: .25), Vx.well]),
        ),
        alignment: Alignment.centerLeft,
        child: Text('$rank', style: Vx.sans(size: 23, weight: FontWeight.w700, color: metal)),
      ),
    ]);
  }
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
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final result = await widget.api.get('/models/${Uri.encodeComponent(widget.slug)}', authenticated: true);
      if (mounted) setState(() {
        _model = {...widget.initial, ...unwrapModelProfile(result)};
        _photo = 0;
        _loading = false;
      });
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
    return modelProfilePhotos(_model);
  }

  @override
  Widget build(BuildContext context) {
    final name = firstText(_model, const ['name', 'title'], fallback: 'Model profile');
    final summary = firstText(_model, const ['description', 'bio', 'about']);
    final personal = modelProfileDetails(_model, 'personal_details');
    final physical = modelProfileDetails(_model, 'physical_attributes');
    const hidden = {'image_url', 'image', 'thumbnail_url', 'thumbnail', 'photo', 'avatar', 'picture', 'gallery', 'images', 'photos', 'description', 'bio', 'about', 'slug', 'id', 'name', 'title', 'url', 'country_flag', 'country_name', 'profile_url', 'model', 'profile', 'data', 'result', 'personal_details', 'physical_attributes', 'age', 'gender', 'career', 'country', 'birth_date', 'height', 'hair_color', 'eye_color', 'ethnicity', 'measurements', 'breast_type', 'piercings'};
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
                          child: Stack(fit: StackFit.expand, children: [
                            ColoredBox(
                              color: Vx.well,
                              child: current.isEmpty
                                ? const Icon(Icons.person_rounded, size: 80, color: Vx.text3)
                                : AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 400),
                                    child: Image.network(current, key: ValueKey(current), headers: widget.api.imageHeaders, fit: BoxFit.cover, alignment: Alignment.topCenter, width: double.infinity, height: double.infinity, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined, size: 48, color: Vx.text3))),
                                  ),
                            ),
                            if (photos.length > 1) ...[
                              Positioned(left: 8, top: 0, bottom: 0, child: Center(child: IconButton.filledTonal(tooltip: 'Previous photo', onPressed: () => setState(() => _photo = (_photo - 1 + photos.length) % photos.length), icon: const Icon(Icons.chevron_left)))),
                              Positioned(right: 8, top: 0, bottom: 0, child: Center(child: IconButton.filledTonal(tooltip: 'Next photo', onPressed: () => setState(() => _photo = (_photo + 1) % photos.length), icon: const Icon(Icons.chevron_right)))),
                              Positioned(bottom: 12, right: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Vx.glass, borderRadius: BorderRadius.circular(999)), child: Text('${_photo + 1} / ${photos.length}', style: Vx.sans(size: 13)))),
                            ],
                          ]),
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
                      if (personal.isNotEmpty) _detailGroup('Personal details', personal),
                      if (physical.isNotEmpty) _detailGroup('Physical attributes', physical),
                      if (details.isNotEmpty) _detailGroup('More details', {for (final item in details) item.key: item.value.toString()}),
                      if (personal.isEmpty && physical.isEmpty && details.isEmpty)
                        Text('No public details listed yet.', style: Vx.sans(size: 14, color: Vx.text3)),
                    ]);
                    if (!wide) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [gallery, const SizedBox(height: 28), info]);
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 380, child: gallery), const SizedBox(width: 40), Expanded(child: info)]);
                  }),
                ]),
    );
  }

  Widget _detailGroup(String title, Map<String, String> details) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(title, style: Vx.sans(size: 18, weight: FontWeight.w700))),
          Container(
            decoration: Vx.surface(),
            child: Column(children: [
              for (final (i, entry) in details.entries.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 130, child: Text(_label(entry.key), style: Vx.sans(size: 14, color: Vx.text3))),
                    Expanded(child: SelectableText(entry.value, style: Vx.sans(size: 14, weight: FontWeight.w500))),
                  ]),
                ),
              ],
            ]),
          ),
        ]),
      );

  String _label(String value) => value
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .split(' ')
      .map((s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}')
      .join(' ');
}
