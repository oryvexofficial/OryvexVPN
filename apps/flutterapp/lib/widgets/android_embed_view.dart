import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/provider_embed.dart';
import '../api/vexo_api.dart';
import 'provider_embed_view.dart'
    show EmbeddedPlaybackProgress, EmbeddedQualityState;

/// Android's system WebView renders the first-party embed, not WebView2.
class AndroidEmbedView extends StatefulWidget {
  const AndroidEmbedView({super.key, required this.embed, required this.video, required this.api, required this.onBack, required this.onSignIn, required this.onQualityStateChanged});
  final ProviderEmbedInfo embed;
  final Map<String, dynamic> video;
  final VexoApi api;
  final VoidCallback onBack;
  final Future<void> Function() onSignIn;
  final ValueChanged<EmbeddedQualityState> onQualityStateChanged;

  @override
  State<AndroidEmbedView> createState() => AndroidEmbedViewState();
}

class AndroidEmbedViewState extends State<AndroidEmbedView> {
  late final WebViewController _controller;
  Timer? _poll;
  String? _error;
  bool _needsSignIn = false;
  bool _ready = false;
  bool _reading = false;
  bool _genericEmbedFallbackTried = false;
  String? _signature;
  Uri? _genericEmbedFallback;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          if (!request.isMainFrame || request.url == 'about:blank' || isAllowedProviderEmbedNavigation(request.url)) {
            return NavigationDecision.navigate;
          }
          return NavigationDecision.prevent;
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame != true || !mounted) return;
          _poll?.cancel();
          if (!_genericEmbedFallbackTried && _genericEmbedFallback != null) {
            _genericEmbedFallbackTried = true;
            unawaited(_loadGenericEmbedFallback());
            return;
          }
          _showLoadError();
        },
        onPageFinished: (_) {
          _poll?.cancel();
          unawaited(_readQuality());
          _poll = Timer.periodic(const Duration(seconds: 1), (_) => unawaited(_readQuality()));
        },
      ));
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      final resumeAt = int.tryParse(widget.video['resumeAt']?.toString() ?? '') ?? 0;
      final playerParams = <String, String>{
        if (videoThumbnail(widget.video).isNotEmpty)
          'app_thumb': videoThumbnail(widget.video),
        if (resumeAt > 0) 'app_resume': '$resumeAt',
      };
      var target = widget.embed.appEmbedUri.replace(queryParameters: playerParams);
      if (!isAllowedProviderEmbedNavigation(target.toString())) throw const ApiException('Unsupported embed link.');
      if (widget.api.hasToken) {
        final result = asMap(await widget.api.post('/embed/grant', body: {'url': widget.embed.sourceUri.toString()}, authenticated: true));
        final grant = firstText(result, const ['grant']);
        if (grant.isEmpty) throw const ApiException('Could not authorize the embedded player.');
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
      }
      // Keep the grant and poster when an older Worker lacks the app route.
      _genericEmbedFallback = widget.embed.embedUri.replace(
        queryParameters: target.queryParameters,
      );
      _genericEmbedFallbackTried = false;
      if (!isAllowedProviderEmbedNavigation(_genericEmbedFallback.toString())) {
        throw const ApiException('Unsupported embed link.');
      }
      if (!mounted) return;
      setState(() { _ready = true; _error = null; _needsSignIn = false; });
      await _controller.loadRequest(target);
    } on ApiException catch (e) {
      if (mounted) setState(() { _error = e.message; _needsSignIn = e.needsLogin; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open the player. Check the connection and try again.');
    }
  }

  Future<void> _loadGenericEmbedFallback() async {
    final fallback = _genericEmbedFallback;
    if (fallback == null) {
      _showLoadError();
      return;
    }
    try {
      await _controller.loadRequest(fallback);
    } catch (_) {
      _showLoadError();
    }
  }

  void _showLoadError() {
    if (!mounted) return;
    _poll?.cancel();
    setState(() {
      _error = 'The player page could not connect. Check your connection, then try again.';
      _ready = false;
    });
  }

  Future<void> _readQuality() async {
    if (!mounted || !_ready || _reading) return;
    _reading = true;
    try {
      final result = await _controller.runJavaScriptReturningResult(r'''
        (function () {
          var p = window.VXPlayer;
          if (!p) return null;
          var metadata = typeof p.metadata === 'function' ? p.metadata() : {};
          var queue = typeof p.queue === 'function' ? p.queue() || [] : [];
          var appVideo = document.getElementById('vxVideo');
          var resumeAt = Number(new URLSearchParams(location.search).get('app_resume'));
          if (resumeAt > 0 && !window.__vexoAppResumeApplied && appVideo &&
              appVideo.readyState >= 1 && isFinite(appVideo.duration) &&
              appVideo.duration > resumeAt + 2) {
            appVideo.currentTime = resumeAt;
            window.__vexoAppResumeApplied = true;
          }
          return JSON.stringify({auto: typeof p.isAuto === 'function' ? !!p.isAuto() : true,
            current: typeof p.current === 'function' ? p.current() : -1,
            title: String(metadata.title || ''),
            provider: String(metadata.provider || ''),
            thumbnail: String(metadata.thumbnail || ''),
            qualities: queue.map(function(item, index) {
              return {index: index, label: String(item.label || ''),
                format: item.isHls ? 'HLS' : 'MP4', visible: item.visible !== false};
            })});
        })()
      ''');
      Object? value = result;
      if (value is String) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is String) value = decoded;
        } catch (_) {}
      }
      final state = EmbeddedQualityState.parseScriptResult(value);
      if (!mounted || state == null) return;
      final signature = '${state.isAuto}:${state.currentIndex}:${state.title}:${state.provider}:${state.thumbnail}:${state.options.map((q) => '${q.index}:${q.label}:${q.format}').join('|')}';
      if (signature != _signature) {
        _signature = signature;
        widget.onQualityStateChanged(state);
      }
    } catch (_) {
      // The page can be navigating or the player can still be starting.
    } finally {
      _reading = false;
    }
  }

  Future<void> selectQuality(int? index) async {
    if (!_ready) return;
    try {
      await _controller.runJavaScript(index == null
          ? 'if (window.VXPlayer) window.VXPlayer.auto();'
          : 'if (window.VXPlayer) window.VXPlayer.select($index);');
      await _readQuality();
    } catch (_) {}
  }

  Future<EmbeddedPlaybackProgress?> readPlaybackProgress() async {
    if (!_ready) return null;
    try {
      final result = await _controller.runJavaScriptReturningResult(r'''
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

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: SingleChildScrollView(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          Wrap(alignment: WrapAlignment.center, children: [
            if (_needsSignIn) TextButton(onPressed: () async { await widget.onSignIn(); if (mounted) await _open(); }, child: const Text('Sign in')),
            TextButton(onPressed: _open, child: const Text('Try again')),
            TextButton(onPressed: widget.onBack, child: const Text('Back')),
          ]),
        ]),
      )));
    }
    if (!_ready) return const ColoredBox(color: Colors.black);
    return Stack(fit: StackFit.expand, children: [
      WebViewWidget(controller: _controller),
      Positioned(right: 8, top: 8, child: IconButton(
        tooltip: 'Back to videos',
        onPressed: widget.onBack,
        icon: const Icon(Icons.close, color: Colors.white),
      )),
    ]);
  }
}
