import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../api/provider_embed.dart';
import '../api/vexo_api.dart';

class EmbeddedPlayerQuality {
  const EmbeddedPlayerQuality({
    required this.index,
    required this.label,
    required this.format,
  });

  final int index;
  final String label;
  final String format;
}

class EmbeddedPlaybackProgress {
  const EmbeddedPlaybackProgress({
    required this.positionSeconds,
    required this.durationSeconds,
  });

  final double positionSeconds;
  final double durationSeconds;

  static EmbeddedPlaybackProgress? parseScriptResult(Object? result) {
    if (result == null) return null;
    dynamic decoded = result;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return null;
      }
    }
    if (decoded is! Map) return null;
    final position = double.tryParse(decoded['position']?.toString() ?? '');
    final duration = double.tryParse(decoded['duration']?.toString() ?? '');
    if (position == null || !position.isFinite || position <= 0) return null;
    return EmbeddedPlaybackProgress(
      positionSeconds: position,
      durationSeconds:
          duration != null && duration.isFinite && duration > 0 ? duration : 0,
    );
  }
}

class EmbeddedQualityState {
  const EmbeddedQualityState({
    this.options = const [],
    this.isAuto = true,
    this.currentIndex,
    this.currentLabel,
    this.title = '',
    this.provider = '',
    this.thumbnail = '',
  });

  final List<EmbeddedPlayerQuality> options;
  final bool isAuto;
  final int? currentIndex;
  final String? currentLabel;
  final String title;
  final String provider;
  final String thumbnail;

  static EmbeddedQualityState? parseScriptResult(Object? result) {
    if (result == null) return null;
    dynamic decoded = result;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return null;
      }
    }
    if (decoded is! Map) return null;

    final options = <EmbeddedPlayerQuality>[];
    final rawOptions = decoded['qualities'];
    if (rawOptions is List) {
      for (final raw in rawOptions) {
        if (raw is! Map || raw['visible'] == false) continue;
        final index = int.tryParse(raw['index']?.toString() ?? '');
        final label = (raw['label'] ?? '').toString().trim();
        if (index == null || label.isEmpty) continue;
        options.add(EmbeddedPlayerQuality(
          index: index,
          label: label,
          format: (raw['format'] ?? '').toString(),
        ));
      }
    }

    final currentIndex = int.tryParse(decoded['current']?.toString() ?? '');
    final current = options.where((quality) => quality.index == currentIndex);
    return EmbeddedQualityState(
      options: options,
      isAuto: decoded['auto'] == true,
      currentIndex: currentIndex,
      currentLabel: current.isEmpty ? null : current.first.label,
      title: decoded['title']?.toString().trim() ?? '',
      provider: decoded['provider']?.toString().trim() ?? '',
      thumbnail: decoded['thumbnail']?.toString().trim() ?? '',
    );
  }
}

class VexoEmbedView extends StatefulWidget {
  const VexoEmbedView({
    super.key,
    required this.embed,
    required this.video,
    required this.api,
    required this.onBack,
    required this.onSignIn,
    required this.onQualityStateChanged,
  });

  final ProviderEmbedInfo embed;
  final Map<String, dynamic> video;
  final VexoApi api;
  final VoidCallback onBack;
  final Future<void> Function() onSignIn;
  final ValueChanged<EmbeddedQualityState> onQualityStateChanged;

  @override
  State<VexoEmbedView> createState() => VexoEmbedViewState();
}

class VexoEmbedViewState extends State<VexoEmbedView> {
  final WebviewController _controller = WebviewController();
  StreamSubscription<String>? _urlSubscription;
  StreamSubscription<dynamic>? _loadingSubscription;
  StreamSubscription<dynamic>? _errorSubscription;
  Timer? _qualityPoll;
  bool _loading = true;
  bool _loadRequested = false;
  bool _controllerInitialized = false;
  bool _needsSignIn = false;
  bool _readingQualityState = false;
  bool _genericEmbedFallbackTried = false;
  String? _lastQualitySignature;
  String? _error;
  Uri? _genericEmbedFallback;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (!isAllowedProviderEmbedNavigation(widget.embed.embedUri.toString()) ||
          !isAllowedProviderEmbedNavigation(widget.embed.appEmbedUri.toString())) {
        if (!mounted) return;
        setState(() {
          _error = 'This VexoStream embed link is not allowlisted. '
              'Copy the link and open it in your browser.';
          _loading = false;
        });
        return;
      }
      final resumeAt = int.tryParse(widget.video['resumeAt']?.toString() ?? '') ?? 0;
      final playerParams = <String, String>{
        if (videoThumbnail(widget.video).isNotEmpty)
          'app_thumb': videoThumbnail(widget.video),
        if (resumeAt > 0) 'app_resume': '$resumeAt',
      };
      var target = widget.embed.appEmbedUri.replace(queryParameters: playerParams);
      if (widget.api.hasToken) {
        try {
          final grantResponse = asMap(await widget.api.post(
            '/embed/grant',
            body: {'url': widget.embed.sourceUri.toString()},
            authenticated: true,
          ));
          final grant = firstText(grantResponse, const ['grant']);
          if (grant.isEmpty) {
            throw const ApiException('Could not authorize the embedded player.');
          }
          target = target.replace(queryParameters: {
            ...playerParams,
            'app_grant': grant,
          });
          if (!playerParams.containsKey('app_thumb')) {
            final poster = (await widget.api.posters([
              widget.embed.sourceUri.toString(),
            ]))[widget.embed.sourceUri.toString()];
            if (poster != null && poster.isNotEmpty) {
              target = target.replace(queryParameters: {
                ...target.queryParameters,
                'app_thumb': poster,
              });
            }
          }
        } on ApiException catch (error) {
          if (!mounted) return;
          setState(() {
            _error = error.needsLogin
                ? 'Your app sign-in has expired. Sign in again to open the embedded player.'
                : error.message;
            _needsSignIn = error.needsLogin;
            _loading = false;
          });
          return;
        }
      }
      // Keep the grant and poster when an older Worker lacks the app route.
      _genericEmbedFallback = widget.embed.embedUri.replace(
        queryParameters: target.queryParameters,
      );
      _genericEmbedFallbackTried = false;
      if (!_controllerInitialized) {
        final runtime = await WebviewController.getWebViewVersion();
        if (!mounted) return;
        if (runtime == null) {
          setState(() {
            _error = 'Microsoft Edge WebView2 Runtime is not installed. '
                'Install the runtime, or copy the VexoStream embed link and open it in your browser.';
            _loading = false;
          });
          return;
        }

        await _controller.initialize();
        _controllerInitialized = true;
        if (!mounted) return;
        await _controller.setBackgroundColor(Colors.black);
        await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
        _urlSubscription = _controller.url.listen(_checkNavigation);
        _loadingSubscription = _controller.loadingState.listen((state) {
          if (!mounted) return;
          setState(() => _loading = state == LoadingState.loading);
          if (state != LoadingState.loading) _startQualityPolling();
        });
        _errorSubscription = _controller.onLoadError.listen((_) {
          if (!mounted) return;
          _qualityPoll?.cancel();
          if (!_genericEmbedFallbackTried && _genericEmbedFallback != null) {
            _genericEmbedFallbackTried = true;
            unawaited(_loadGenericEmbedFallback());
            return;
          }
          _showLoadError();
        });
      }
      _loadRequested = true;
      await _controller.loadUrl(target.toString());
      if (!mounted) return;
      setState(() => _loading = false);
      _startQualityPolling();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'The VexoStream embed could not be opened in WebView2. '
            'Copy the embed link or original video link and open it in your browser.';
        _loading = false;
      });
    }
  }

  Future<void> _loadGenericEmbedFallback() async {
    final fallback = _genericEmbedFallback;
    if (fallback == null) {
      _showLoadError();
      return;
    }
    try {
      await _controller.loadUrl(fallback.toString());
      if (mounted) _startQualityPolling();
    } catch (_) {
      _showLoadError();
    }
  }

  void _showLoadError() {
    if (!mounted) return;
    _qualityPoll?.cancel();
    setState(() {
      _error = 'The player page could not connect. Check your connection, then try again.';
      _loading = false;
    });
  }

  void _retry() {
    if (!mounted) return;
    setState(() {
      _error = null;
      _needsSignIn = false;
      _loading = true;
    });
    unawaited(_initialize());
  }

  void _startQualityPolling() {
    if (_qualityPoll?.isActive == true) return;
    unawaited(_readQualityState());
    _qualityPoll = Timer.periodic(
      const Duration(milliseconds: 900),
      (_) => unawaited(_readQualityState()),
    );
  }

  Future<void> _readQualityState() async {
    if (!_controllerInitialized || _readingQualityState || !mounted) return;
    _readingQualityState = true;
    try {
      final result = await _controller.executeScript(r'''
        (function () {
          var player = window.VXPlayer;
          if (!player) return null;
          var metadata = typeof player.metadata === 'function' ? player.metadata() : {};
          var queue = typeof player.queue === 'function' ? player.queue() || [] : [];
          var appVideo = document.getElementById('vxVideo');
          var resumeAt = Number(new URLSearchParams(location.search).get('app_resume'));
          if (resumeAt > 0 && !window.__vexoAppResumeApplied && appVideo &&
              appVideo.readyState >= 1 && isFinite(appVideo.duration) &&
              appVideo.duration > resumeAt + 2) {
            appVideo.currentTime = resumeAt;
            window.__vexoAppResumeApplied = true;
          }
          return JSON.stringify({
            auto: typeof player.isAuto === 'function' ? !!player.isAuto() : true,
            current: typeof player.current === 'function' ? player.current() : -1,
            title: String(metadata.title || ''),
            provider: String(metadata.provider || ''),
            thumbnail: String(metadata.thumbnail || ''),
            qualities: queue.map(function (item, index) {
              return {
                index: index,
                label: String(item.label || ''),
                format: item.isHls ? 'HLS' : 'MP4',
                visible: item.visible !== false
              };
            }).filter(function (item) {
              return item.visible && item.label;
            })
          });
        })()
      ''');
      if (!mounted) return;
      final state = EmbeddedQualityState.parseScriptResult(result);
      if (state == null) return;
      final signature = [
        state.isAuto,
        state.currentIndex,
        state.currentLabel,
        state.title,
        state.provider,
        state.thumbnail,
        ...state.options.map((quality) => '${quality.index}:${quality.label}:${quality.format}'),
      ].join('|');
      if (signature == _lastQualitySignature) return;
      _lastQualitySignature = signature;
      widget.onQualityStateChanged(state);
    } catch (_) {
      // The embed initializes its player asynchronously. Poll again next tick.
    } finally {
      _readingQualityState = false;
    }
  }

  Future<void> selectQuality(int? index) async {
    if (!_controllerInitialized) return;
    try {
      final script = index == null
          ? 'if (window.VXPlayer) window.VXPlayer.auto();'
          : 'if (window.VXPlayer) window.VXPlayer.select($index);';
      await _controller.executeScript(script);
      await _readQualityState();
    } catch (_) {
      // The WebView may still be navigating or the player may be refreshing.
    }
  }

  Future<EmbeddedPlaybackProgress?> readPlaybackProgress() async {
    if (!_controllerInitialized) return null;
    try {
      final result = await _controller.executeScript(r'''
        (function () {
          var video = document.getElementById('vxVideo') || document.querySelector('video');
          if (!video) return null;
          return JSON.stringify({position: video.currentTime || 0, duration: video.duration || 0});
        })()
      ''');
      return EmbeddedPlaybackProgress.parseScriptResult(result);
    } catch (_) {
      return null;
    }
  }

  void _checkNavigation(String rawUrl) {
    if (rawUrl == 'about:blank') return;
    if (isAllowedProviderEmbedNavigation(rawUrl)) {
      return;
    }
    if (!_loadRequested) return;
    unawaited(_controller.stop());
    if (!mounted || _error != null) return;
    setState(() {
      _error = 'The WebView left VexoStream’s embedded-player route, so navigation was stopped. '
          'Copy the embed link or original video link and open it in your browser.';
      _loading = false;
    });
  }

  Future<void> _copyEmbedLink() async {
    await Clipboard.setData(ClipboardData(text: widget.embed.embedUri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('VexoStream embed link copied')),
    );
  }

  Future<void> _copySourceLink() async {
    await Clipboard.setData(ClipboardData(text: widget.embed.sourceUri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Original video link copied')),
    );
  }

  @override
  void dispose() {
    _qualityPoll?.cancel();
    unawaited(_urlSubscription?.cancel());
    unawaited(_loadingSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    if (_controllerInitialized) unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _message(
        icon: Icons.open_in_browser_rounded,
        title: 'VexoStream embed unavailable',
        message: _error!,
        showCopy: true,
      );
    }
    if (!_controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Webview(
          _controller,
          permissionRequested: (_, __, ___) => WebviewPermissionDecision.deny,
        ),
        Positioned(
          right: 12,
          top: 12,
          child: Material(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(10),
            child: IconButton(
              tooltip: 'Back to videos',
              onPressed: widget.onBack,
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _message({
    required IconData icon,
    required String title,
    required String message,
    required bool showCopy,
  }) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 38, color: Colors.white70),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  if (showCopy)
                    OutlinedButton.icon(
                      onPressed: _copyEmbedLink,
                      icon: const Icon(Icons.link_rounded, size: 16),
                      label: const Text('Copy VexoStream embed link'),
                    ),
                  if (showCopy)
                    OutlinedButton.icon(
                      onPressed: _copySourceLink,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy original video link'),
                    ),
                  if (_needsSignIn)
                    FilledButton.icon(
                      onPressed: () async {
                        await widget.onSignIn();
                        if (mounted && widget.api.hasToken) _retry();
                      },
                      icon: const Icon(Icons.login_rounded, size: 16),
                      label: const Text('Sign in'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Try again'),
                  ),
                  TextButton(
                    onPressed: widget.onBack,
                    child: const Text('Back to videos'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
