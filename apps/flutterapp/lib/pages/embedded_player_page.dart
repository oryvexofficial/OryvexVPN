import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/provider_embed.dart';
import '../api/vexo_api.dart';
import '../api/watch_history.dart';
import '../widgets/provider_embed_view.dart';
import '../widgets/android_embed_view.dart';
import '../widgets/vexo_theme.dart';
import '../widgets/video_card.dart';

String recommendationQuery(String title) {
  if (title.trim().isEmpty || title == 'VexoStream player') return 'trending';
  final words = title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+')).where((word) => word.length > 3).take(3).join(' ');
  return words.isEmpty ? 'trending' : words;
}

bool appRequiresMemberLogin(Map<String, dynamic> config) {
  final access = asMap(config['access']);
  return access['requireLogin'] == true;
}

/// The app's playback surface is VexoStream's own web player, hosted in a
/// first-party WebView. There is no native media-kit playback path.
class PlayerPage extends StatefulWidget {
  const PlayerPage({
    super.key,
    required this.api,
    required this.video,
    required this.onSignIn,
  });

  final VexoApi api;
  final Map<String, dynamic> video;
  final Future<void> Function() onSignIn;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final GlobalKey<VexoEmbedViewState> _embedKey = GlobalKey<VexoEmbedViewState>();
  final GlobalKey<AndroidEmbedViewState> _androidEmbedKey = GlobalKey<AndroidEmbedViewState>();
  EmbeddedQualityState _qualityState = const EmbeddedQualityState();
  List<Map<String, dynamic>> _related = [];
  bool _relatedLoading = true;
  String? _relatedError;
  String _relatedQuery = '';
  String _resolvedTitle = '';
  String _resolvedProvider = '';
  String _resolvedThumbnail = '';
  Timer? _historyTimer;
  bool _savingHistory = false;
  bool _isFullscreen = false;
  bool _accessChecking = true;
  bool _requiresMemberLogin = false;
  String? _accessError;

  @override
  void initState() {
    super.initState();
    unawaited(_checkAccess());
    _loadRelated();
    _historyTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => unawaited(_savePlaybackProgress()),
    );
  }

  Future<void> _checkAccess() async {
    if (mounted) {
      setState(() {
        _accessChecking = true;
        _accessError = null;
      });
    }
    if (providerEmbedForVideo(widget.video) == null) {
      if (mounted) {
        setState(() {
          _accessChecking = false;
          _requiresMemberLogin = false;
        });
      }
      return;
    }
    try {
      final config = asMap(await widget.api.get('/config'));
      final access = asMap(config['access']);
      if (!access.containsKey('requireLogin')) {
        throw const ApiException('The server did not return playback access settings.');
      }
      if (!mounted) return;
      setState(() {
        _requiresMemberLogin = appRequiresMemberLogin(config);
        _accessChecking = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _accessError = error.message;
        _accessChecking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _accessError = 'Could not verify playback access. Check your connection and try again.';
        _accessChecking = false;
      });
    }
  }

  Future<void> _loadRelated() async {
    final embed = providerEmbedForVideo(widget.video);
    if (embed == null) {
      if (mounted) setState(() => _relatedLoading = false);
      return;
    }
    final query = recommendationQuery(_title);
    if (_relatedQuery == query) return;
    _relatedQuery = query;
    if (mounted) {
      setState(() {
        _relatedLoading = true;
        _relatedError = null;
      });
    }
    try {
      final data = await widget.api.get('/catalog', query: {
        'provider': embed.provider,
        'q': query,
        'page': 1,
      });
      if (mounted) setState(() {
        _related = videoItems(data).where((item) => videoTarget(item) != _target).take(8).toList();
        _relatedLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() { _relatedError = 'Recommendations could not be loaded.'; _relatedLoading = false; });
    }
  }

  String get _title {
    final supplied = firstText(widget.video, const ['title', 'name', 'video_title']);
    if (supplied.isNotEmpty && supplied.toLowerCase() != 'vexostream player') {
      return supplied;
    }
    return _resolvedTitle.isNotEmpty ? _resolvedTitle : supplied;
  }
  String get _target => firstText(widget.video, const ['url', 'video_url', 'link', 'href']);

  void _updateQualityState(EmbeddedQualityState state) {
    if (!mounted) return;
    final previousTitle = _resolvedTitle;
    setState(() {
      _qualityState = state;
      if (state.title.isNotEmpty) _resolvedTitle = state.title;
      if (state.provider.isNotEmpty) _resolvedProvider = state.provider;
      if (state.thumbnail.isNotEmpty) _resolvedThumbnail = state.thumbnail;
    });
    if (_resolvedTitle.isNotEmpty && _resolvedTitle != previousTitle) {
      unawaited(_loadRelated());
    }
  }

  Future<void> _selectQuality(int? index) async {
    if (Platform.isAndroid) {
      await _androidEmbedKey.currentState?.selectQuality(index);
    } else {
      await _embedKey.currentState?.selectQuality(index);
    }
  }

  Future<void> _savePlaybackProgress() async {
    if (_savingHistory) return;
    _savingHistory = true;
    try {
      final progress = Platform.isAndroid
          ? await _androidEmbedKey.currentState?.readPlaybackProgress()
          : await _embedKey.currentState?.readPlaybackProgress();
      if (progress == null || progress.positionSeconds <= 0) return;
      final target = _target;
      final targetUri = Uri.tryParse(target);
      if (targetUri == null ||
          (targetUri.scheme != 'https' && targetUri.scheme != 'http') ||
          targetUri.host.isEmpty) {
        return;
      }
      await WatchHistoryStore.save(WatchHistoryEntry(
        url: target,
        title: _title.isEmpty ? 'VexoStream Player' : _title,
        provider: firstText(widget.video, const ['provider', 'source']),
        thumbnail: videoThumbnail(widget.video).isNotEmpty
            ? videoThumbnail(widget.video)
            : _resolvedThumbnail,
        position: progress.positionSeconds.floor(),
        duration: progress.durationSeconds.floor(),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ));
    } finally {
      _savingHistory = false;
    }
  }

  Future<void> _copy(BuildContext context, String value, String message) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setFullscreen(bool fullscreen) async {
    if (_isFullscreen == fullscreen) return;
    if (Platform.isAndroid) {
      try {
        if (fullscreen) {
          await SystemChrome.setPreferredOrientations(const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
          await SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.immersiveSticky,
          );
        } else {
          await _restoreSystemUi();
        }
      } catch (_) {
        // Keep the in-app fullscreen surface usable if a device rejects a
        // system orientation or UI-mode change.
      }
    }
    if (mounted) setState(() => _isFullscreen = fullscreen);
  }

  Future<void> _restoreSystemUi() async {
    await SystemChrome.setPreferredOrientations(const []);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  @override
  Widget build(BuildContext context) {
    final embed = providerEmbedForVideo(widget.video);
    final title = _title.isEmpty ? 'VexoStream Player' : _title;
    final sourceProvider = firstText(widget.video, const ['provider']);
    final provider = sourceProvider.isNotEmpty ? sourceProvider : _resolvedProvider;

    return PopScope<Object?>(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) unawaited(_setFullscreen(false));
      },
      child: _isFullscreen
          ? Scaffold(
              backgroundColor: Colors.black,
              body: SizedBox.expand(child: _playerSurface(embed)),
            )
          : Scaffold(
              appBar: AppBar(
                title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                actions: [
                  if (embed != null)
                    IconButton(
                      tooltip: 'Share or embed this video',
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => _ShareEmbedDialog(
                          sourceUrl: embed.sourceUri.toString(),
                          embedUrl: embed.embedUri.toString(),
                        ),
                      ),
                      icon: const Icon(Icons.ios_share_rounded),
                    ),
                  if (embed != null)
                    IconButton(
                      tooltip: 'Copy VexoStream embed link',
                      onPressed: () => _copy(context, embed.embedUri.toString(), 'VexoStream embed link copied'),
                      icon: const Icon(Icons.link_rounded),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
              body: PageBody(
                maxWidth: 1240,
                padding: MediaQuery.sizeOf(context).width < 600
                    ? const EdgeInsets.fromLTRB(16, 16, 16, 28)
                    : const EdgeInsets.fromLTRB(28, 24, 28, 40),
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: _playerSurface(embed),
                  ),
                  if (embed != null) ...[
                    const SizedBox(height: 20),
                    _qualityCard(),
                  ],
                  const SizedBox(height: 20),
                  Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 24)),
                  const SizedBox(height: 10),
                  LayoutBuilder(builder: (context, constraints) {
                    final compact = constraints.maxWidth < 480;
                    final providerInfo = provider.isEmpty
                        ? const SizedBox.shrink()
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            ProviderIcon(id: provider.toLowerCase(), name: provider, size: 22),
                            const SizedBox(width: 8),
                            Text(
                              provider[0].toUpperCase() + provider.substring(1),
                              style: Vx.sans(size: 14, color: Vx.text2, weight: FontWeight.w500),
                            ),
                          ]);
                    final copyButton = TextButton.icon(
                      onPressed: () => _copy(context, _target, 'Original video link copied'),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy link'),
                    );
                    final targetText = Text(
                      _target,
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: Vx.mono(size: 12),
                    );
                    if (compact) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (provider.isNotEmpty) ...[
                            providerInfo,
                            const SizedBox(height: 6),
                          ],
                          targetText,
                          Align(alignment: Alignment.centerRight, child: copyButton),
                        ],
                      );
                    }
                    return Row(children: [
                      if (provider.isNotEmpty) ...[
                        providerInfo,
                        const SizedBox(width: 14),
                      ],
                      Expanded(child: targetText),
                      copyButton,
                    ]);
                  }),
                  const SizedBox(height: 32),
                  _shortcuts(),
                  const SizedBox(height: 32),
                  const PageHeading(title: 'More like this', large: false),
                  if (_relatedError != null)
                    Text(_relatedError!, style: Vx.sans(size: 14, color: Vx.text2))
                  else if (!_relatedLoading && _related.isEmpty)
                    Text('No similar videos found.', style: Vx.sans(size: 14, color: Vx.text2))
                  else
                    VideoGrid(
                      api: widget.api, items: _related, loading: _relatedLoading, skeletons: 4,
                      onPlay: (video) => Navigator.of(context).pushReplacement(MaterialPageRoute(
                        builder: (_) => PlayerPage(api: widget.api, video: video, onSignIn: widget.onSignIn),
                      )),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _playerSurface(ProviderEmbedInfo? embed) {
    if (_accessChecking) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_accessError != null) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline_rounded, size: 34, color: Colors.white70),
              const SizedBox(height: 10),
              Text(
                'Could not verify playback access',
                textAlign: TextAlign.center,
                style: Vx.sans(size: 18, color: Colors.white, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(_accessError!, textAlign: TextAlign.center, style: Vx.sans(size: 13, color: Vx.text2)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _checkAccess,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Try again'),
              ),
            ]),
          ),
        ),
      );
    }
    if (_requiresMemberLogin && !widget.api.hasToken) {
      return ColoredBox(
        color: Colors.black,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline_rounded, size: 34, color: Colors.white70),
              const SizedBox(height: 10),
              Text(
                'You must log in to continue',
                textAlign: TextAlign.center,
                style: Vx.sans(size: 18, color: Colors.white, weight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to your VexoStream account to watch this video.',
                textAlign: TextAlign.center,
                style: Vx.sans(size: 13, color: Vx.text2),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () async {
                  await widget.onSignIn();
                  if (mounted && widget.api.hasToken) await _checkAccess();
                },
                icon: const Icon(Icons.login_rounded, size: 16),
                label: const Text('Log in'),
              ),
            ]),
          ),
        ),
      );
    }
    return Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: _isFullscreen
                ? BorderRadius.zero
                : BorderRadius.circular(Vx.radiusXl),
            child: ColoredBox(
              color: Colors.black,
              child: embed == null
                  ? _unsupportedSource(context)
                  : Platform.isAndroid
                      ? AndroidEmbedView(
                          key: _androidEmbedKey,
                          embed: embed,
                          video: widget.video,
                          api: widget.api,
                          onBack: () => Navigator.of(context).maybePop(),
                          onSignIn: widget.onSignIn,
                          onQualityStateChanged: _updateQualityState,
                        )
                      : VexoEmbedView(
                          key: _embedKey,
                          embed: embed,
                          video: widget.video,
                          api: widget.api,
                          onBack: () => Navigator.of(context).maybePop(),
                          onSignIn: widget.onSignIn,
                          onQualityStateChanged: _updateQualityState,
                        ),
            ),
          ),
          if (embed != null)
            Positioned(
              top: 10,
              left: 10,
              child: Material(
                color: Colors.black.withValues(alpha: .68),
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: _isFullscreen ? 'Exit full screen' : 'Full screen',
                  onPressed: () => unawaited(_setFullscreen(!_isFullscreen)),
                  icon: Icon(
                    _isFullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      );
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    if (_isFullscreen && Platform.isAndroid) {
      unawaited(_restoreSystemUi());
    }
    super.dispose();
  }

  Widget _shortcuts() => Container(
    padding: const EdgeInsets.all(18),
    decoration: Vx.surface(),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Shortcuts', style: Vx.sans(size: 15, weight: FontWeight.w600)),
      const SizedBox(height: 12),
      Text('When the player has keyboard focus:', style: Vx.sans(size: 13, color: Vx.text2)),
      const SizedBox(height: 10),
      Wrap(spacing: 18, runSpacing: 8, children: [
        for (final item in const ['K  Play / pause', 'F  Full screen', '← / →  5 seconds', 'J / L  10 seconds', 'M  Mute', 'T  Theater'])
          Text(item, style: Vx.sans(size: 13, color: Vx.text2)),
      ]),
    ]),
  );

  Widget _qualityCard() {
    final state = _qualityState;
    final options = state.options;
    final selectedResolution = state.currentLabel;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: Vx.surface(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.high_quality_outlined, color: Vx.blue, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('Playback quality', style: Vx.sans(size: 15, weight: FontWeight.w600))),
              if (options.isEmpty)
                Flexible(child: Text('Loading options…', overflow: TextOverflow.ellipsis, style: Vx.sans(size: 12, color: Vx.text3)))
              else
                Flexible(child: Text(
                  state.isAuto && selectedResolution != null
                      ? 'Auto · $selectedResolution'
                      : (selectedResolution ?? 'Choose a resolution'),
                  overflow: TextOverflow.ellipsis,
                  style: Vx.mono(size: 11, color: Vx.text2),
                )),
            ],
          ),
          const SizedBox(height: 14),
          if (options.isEmpty)
            Row(
              children: [
                const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(
                  'Waiting for the embedded player’s stream options.',
                  style: Vx.sans(size: 12, color: Vx.text2),
                )),
              ],
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Auto'),
                  selected: state.isAuto,
                  onSelected: (_) => _selectQuality(null),
                ),
                for (final quality in options)
                  ChoiceChip(
                    label: Text(quality.label),
                    selected: !state.isAuto && state.currentIndex == quality.index,
                    onSelected: (_) => _selectQuality(quality.index),
                    avatar: quality.format.isEmpty
                        ? null
                        : Text(
                            quality.format,
                            style: Vx.mono(size: 8, color: Vx.text2),
                          ),
                  ),
              ],
            ),
          if (options.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Changes here control the VexoStream embedded player.',
              style: Vx.sans(size: 12, color: Vx.text3),
            ),
          ],
        ],
      ),
    );
  }

  Widget _unsupportedSource(BuildContext context) => ColoredBox(
        color: Colors.black,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.link_off_rounded, size: 36, color: Colors.white70),
                const SizedBox(height: 10),
                Text(
                  'Unsupported video link',
                  textAlign: TextAlign.center,
                  style: Vx.sans(size: 18, color: Colors.white, weight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'This link does not match a supported provider video page, so it cannot be opened in the VexoStream player.',
                  textAlign: TextAlign.center,
                  style: Vx.sans(size: 13, color: Vx.text2),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => _copy(context, _target, 'Original link copied'),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy original link'),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ShareEmbedDialog extends StatefulWidget {
  const _ShareEmbedDialog({
    required this.sourceUrl,
    required this.embedUrl,
  });

  final String sourceUrl;
  final String embedUrl;

  @override
  State<_ShareEmbedDialog> createState() => _ShareEmbedDialogState();
}

class _ShareEmbedDialogState extends State<_ShareEmbedDialog> {
  bool _useWebComponent = false;

  String get _embedCode {
    final origin = Uri.parse(widget.embedUrl).origin;
    if (_useWebComponent) {
      return '<script src="$origin/embed.js"></script>\n'
          '<vexo-player src="${widget.sourceUrl}"></vexo-player>';
    }
    return '<div style="position:relative;padding-top:56.25%">\n'
        '  <iframe src="${widget.embedUrl}" '
        'style="position:absolute;inset:0;width:100%;height:100%;border:0" '
        'allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>\n'
        '</div>';
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Share or embed this video'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('iframe')),
                  ButtonSegment(value: true, label: Text('Web component')),
                ],
                selected: {_useWebComponent},
                onSelectionChanged: (value) =>
                    setState(() => _useWebComponent = value.first),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: Vx.surface(color: Vx.well),
                child: SelectableText(
                  _embedCode,
                  style: Vx.mono(size: 12, color: Vx.text2),
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                widget.embedUrl,
                style: Vx.mono(size: 11, color: Vx.text3),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          OutlinedButton(
            onPressed: () => _copy(widget.embedUrl, 'Embed link'),
            child: const Text('Copy VexoStream link'),
          ),
          FilledButton.icon(
            onPressed: () => _copy(_embedCode, 'Embed code'),
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy code'),
          ),
        ],
      );
}
