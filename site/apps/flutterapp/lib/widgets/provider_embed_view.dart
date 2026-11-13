import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_windows/webview_windows.dart';

import '../api/provider_embed.dart';
import '../api/vexo_api.dart';

class VexoEmbedView extends StatefulWidget {
  const VexoEmbedView({
    super.key,
    required this.embed,
    required this.api,
    required this.onBack,
    required this.onSignIn,
  });

  final ProviderEmbedInfo embed;
  final VexoApi api;
  final VoidCallback onBack;
  final Future<void> Function() onSignIn;

  @override
  State<VexoEmbedView> createState() => _VexoEmbedViewState();
}

class _VexoEmbedViewState extends State<VexoEmbedView> {
  final WebviewController _controller = WebviewController();
  StreamSubscription<String>? _urlSubscription;
  StreamSubscription<dynamic>? _loadingSubscription;
  StreamSubscription<dynamic>? _errorSubscription;
  bool _loading = true;
  bool _loadRequested = false;
  bool _controllerInitialized = false;
  bool _needsSignIn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      if (!isAllowedProviderEmbedNavigation(widget.embed.embedUri.toString())) {
        if (!mounted) return;
        setState(() {
          _error = 'This VexoStream embed link is not allowlisted. '
              'Copy the link and open it in your browser.';
          _loading = false;
        });
        return;
      }
      var target = widget.embed.embedUri;
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
          target = target.replace(queryParameters: {'app_grant': grant});
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
        });
        _errorSubscription = _controller.onLoadError.listen((_) {
          if (!mounted) return;
          setState(() {
            _error = 'The VexoStream embed page could not be loaded. Check the connection '
                'or copy its link and open it in your browser.';
            _loading = false;
          });
        });
      }
      _loadRequested = true;
      await _controller.loadUrl(target.toString());
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'The VexoStream embed could not be opened in WebView2. '
            'Copy the embed link or original video link and open it in your browser.';
        _loading = false;
      });
    }
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
        if (_loading)
          const ColoredBox(
            color: Color(0x66000000),
            child: Center(child: CircularProgressIndicator()),
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
