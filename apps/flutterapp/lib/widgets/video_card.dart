import 'package:flutter/material.dart';

import '../api/vexo_api.dart';
import 'vexo_theme.dart';

/// Site ".vcard": 16:9 rounded thumbnail with a hairline ring, glass duration
/// pill, blue play button on hover, two-line title, provider meta.
class VideoCard extends StatefulWidget {
  const VideoCard({super.key, required this.api, required this.video, required this.onTap, this.poster, this.progress});
  final VexoApi api;
  final Map<String, dynamic> video;
  final String? poster;
  final double? progress;
  final VoidCallback onTap;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final title = firstText(video, const ['title', 'name', 'video_title'], fallback: 'Untitled video');
    final listing = videoThumbnail(video);
    final images = <String>{
      if ((widget.poster ?? '').isNotEmpty) widget.poster!,
      if (listing.isNotEmpty) listing,
    }.map(widget.api.imageUrl).where((u) => u.isNotEmpty).toList();
    final duration = formatDuration(video['duration'] ?? video['length']);
    final provider = firstText(video, const ['provider', 'source']);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Vx.ease,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Vx.radiusXl),
                boxShadow: _hover ? const [BoxShadow(color: Color(0xE6000000), blurRadius: 44, offset: Offset(0, 22), spreadRadius: -22)] : const [],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Vx.radiusXl),
                child: Stack(fit: StackFit.expand, children: [
                  const ColoredBox(color: Vx.well),
                  if (images.isNotEmpty)
                    AnimatedScale(
                      scale: _hover ? 1.045 : 1,
                      duration: const Duration(milliseconds: 900),
                      curve: Vx.ease,
                      child: _FallbackNetworkImage(
                        sources: images,
                        headers: widget.api.imageHeaders,
                      ),
                    )
                  else
                    const _ThumbFallback(),
                  AnimatedOpacity(
                    opacity: _hover ? 1 : 0,
                    duration: const Duration(milliseconds: 350),
                    child: const ColoredBox(color: Color(0x52050811)),
                  ),
                  Center(
                    child: AnimatedScale(
                      scale: _hover ? 1 : .6,
                      duration: const Duration(milliseconds: 450),
                      curve: Vx.pop,
                      child: AnimatedOpacity(
                        opacity: _hover ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Vx.blue,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: Vx.blue.withValues(alpha: .25), spreadRadius: 8),
                              const BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 12), spreadRadius: -8),
                            ],
                          ),
                          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 30),
                        ),
                      ),
                    ),
                  ),
                  if (duration.isNotEmpty)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Vx.glass, borderRadius: BorderRadius.circular(999)),
                        child: Text(duration, style: Vx.mono(size: 12, color: Colors.white)),
                      ),
                    ),
                  if (widget.progress != null && widget.progress! > 0)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: widget.progress!.clamp(0.0, 1.0).toDouble(),
                          minHeight: 3,
                          backgroundColor: const Color(0x66000000),
                          valueColor: const AlwaysStoppedAnimation<Color>(Vx.blue),
                        ),
                      ),
                    ),
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Vx.radiusXl),
                        border: Border.all(color: _hover ? Vx.ringStrong : Vx.ring),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 12),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: Vx.sans(size: 15, weight: FontWeight.w500, color: _hover ? Vx.blue : Vx.text, height: 1.35, spacing: -.08),
            child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          if (provider.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_cap(provider), maxLines: 1, overflow: TextOverflow.ellipsis, style: Vx.sans(size: 13, color: Vx.text2)),
          ],
        ]),
      ),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _FallbackNetworkImage extends StatefulWidget {
  const _FallbackNetworkImage({required this.sources, required this.headers});
  final List<String> sources;
  final Map<String, String> headers;

  @override
  State<_FallbackNetworkImage> createState() => _FallbackNetworkImageState();
}

class _FallbackNetworkImageState extends State<_FallbackNetworkImage> {
  int _sourceIndex = 0;
  bool _advanceScheduled = false;

  @override
  void didUpdateWidget(covariant _FallbackNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sources.join('\n') != widget.sources.join('\n')) {
      _sourceIndex = 0;
      _advanceScheduled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_sourceIndex >= widget.sources.length) return const _ThumbFallback();
    final src = widget.sources[_sourceIndex];
    return Image.network(
      src,
      key: ValueKey(src),
      headers: widget.headers,
      fit: BoxFit.cover,
      frameBuilder: (context, child, frame, sync) => sync
          ? child
          : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 500), curve: Vx.ease, child: child),
      errorBuilder: (_, __, ___) {
        if (_sourceIndex < widget.sources.length - 1 && !_advanceScheduled) {
          _advanceScheduled = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _sourceIndex++;
              _advanceScheduled = false;
            });
          });
        }
        if (_sourceIndex < widget.sources.length - 1) return const ColoredBox(color: Vx.well);
        return const _ThumbFallback();
      },
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();
  @override
  Widget build(BuildContext context) => const ColoredBox(
        color: Vx.well,
        child: Center(child: Icon(Icons.play_circle_outline_rounded, size: 40, color: Vx.text3)),
      );
}

/// Skeleton matching the card's footprint.
class VideoCardSkeleton extends StatelessWidget {
  const VideoCardSkeleton({super.key});
  @override
  Widget build(BuildContext context) => const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Skeleton(aspectRatio: 16 / 9),
        SizedBox(height: 14),
        Skeleton(height: 12, radius: 999, width: 220),
        SizedBox(height: 10),
        Skeleton(height: 12, radius: 999, width: 120),
      ]);
}

/// Responsive grid of video cards with real-poster upgrades (like the site).
class VideoGrid extends StatefulWidget {
  const VideoGrid({super.key, required this.api, required this.items, required this.onPlay, this.loading = false, this.skeletons = 12, this.progressByUrl = const {}});
  final VexoApi api;
  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>> onPlay;
  final bool loading;
  final int skeletons;
  final Map<String, double> progressByUrl;

  @override
  State<VideoGrid> createState() => _VideoGridState();
}

class _VideoGridState extends State<VideoGrid> {
  final Map<String, String> _posters = {};

  @override
  void initState() {
    super.initState();
    _fetchPosters();
  }

  @override
  void didUpdateWidget(covariant VideoGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.items, widget.items)) _fetchPosters();
  }

  Future<void> _fetchPosters() async {
    final urls = widget.items.map((v) => firstText(v, const ['url', 'video_url', 'link'])).where((u) => u.isNotEmpty && !_posters.containsKey(u)).toList();
    for (var i = 0; i < urls.length; i += 24) {
      final batch = urls.sublist(i, i + 24 > urls.length ? urls.length : i + 24);
      final found = await widget.api.posters(batch);
      if (!mounted) return;
      if (found.isNotEmpty) setState(() => _posters.addAll(found));
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final cols = gridColumns(constraints.maxWidth, min: 270);
        final count = widget.loading ? widget.skeletons : widget.items.length;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 20,
            mainAxisSpacing: 34,
            mainAxisExtent: (constraints.maxWidth - 20 * (cols - 1)) / cols * 9 / 16 + 86,
          ),
          itemBuilder: (context, i) {
            if (widget.loading) return const VideoCardSkeleton();
            final item = widget.items[i];
            final url = firstText(item, const ['url', 'video_url', 'link', 'href']);
            final poster = _posters[url];
            return VideoCard(
              api: widget.api,
              video: item,
              poster: poster,
              progress: widget.progressByUrl[url],
              onTap: () {
                final playable = Map<String, dynamic>.from(item);
                if ((poster ?? '').isNotEmpty) playable['thumbnail'] = poster;
                widget.onPlay(playable);
              },
            );
          },
        );
      });
}

String videoTarget(Map<String, dynamic> item) => firstText(item, const ['url', 'video_url', 'link', 'href']);
