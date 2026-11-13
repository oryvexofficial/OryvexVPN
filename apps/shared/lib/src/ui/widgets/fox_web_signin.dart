import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/backend.dart';

// Mozilla's account page uses Firefox's WebChannel. The bridge answers only
// the capability questions and forwards only login events, never passwords.
// The Go service exchanges the session token and waits for email verification.
const _channelScript = r'''
(function () {
  if (window.top !== window || location.origin !== 'https://accounts.firefox.com') return;
  if (window.__oryvexChannelInstalled) return;
  window.__oryvexChannelInstalled = true;
  let pending = null;
  function deliver() {
    if (!pending || !window.flutter_inappwebview || !window.flutter_inappwebview.callHandler) return;
    const value = pending; pending = null;
    window.flutter_inappwebview.callHandler('firefoxAccountLogin', value).catch(function(){});
  }
  window.addEventListener('flutterInAppWebViewPlatformReady', deliver);
  window.addEventListener('WebChannelMessageToChrome', function (event) {
    let detail = event.detail;
    if (typeof detail === 'string') { try { detail = JSON.parse(detail); } catch (_) { return; } }
    if (!detail || detail.id !== 'account_updates' || !detail.message) return;
    const message = detail.message;
    const cmd = message.command;
    if (cmd === 'fxaccounts:fxa_status' || cmd === 'fxaccounts:can_link_account') {
      const data = cmd === 'fxaccounts:can_link_account' ? {ok: true} :
        {signedInUser: null, capabilities: {engines: [], choose_what_to_sync: false, multiService: false, pairing: false}};
      const reply = {id: 'account_updates', message: {command: cmd, messageId: message.messageId, data: data}};
      window.dispatchEvent(new CustomEvent('WebChannelMessageToContent', {detail: reply}));
    }
    if ((cmd === 'fxaccounts:login' || cmd === 'fxaccounts:verified') && message.data) {
      const email = message.data.email, token = message.data.sessionToken;
      if (typeof email === 'string' && typeof token === 'string' && /^[0-9a-fA-F]{64}$/.test(token)) {
        pending = {email: email, sessionToken: token};
        deliver();
      }
    }
  }, true);
})();
''';

/// An in-app Mozilla-hosted sign-in, not the removed local web dashboard.
class FoxWebSignIn extends StatefulWidget {
  const FoxWebSignIn({super.key, required this.backend});
  final CoreBackend backend;

  @override
  State<FoxWebSignIn> createState() => _FoxWebSignInState();
}

class _FoxWebSignInState extends State<FoxWebSignIn> {
  static final _start = WebUri('https://accounts.firefox.com/?context=fx_desktop_v3&service=sync');
  static const _firefoxUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0';
  WebViewEnvironment? environment;
  bool initializing = true;
  bool ready = false;
  bool submitting = false;
  bool polling = false;
  bool closing = false;
  String? error;
  String message = 'Sign in on Mozilla’s page. Keep this screen open for verification.';
  String? sessionId;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    unawaited(initialize());
  }

  Future<void> initialize() async {
    try {
      // Start and verify the app-only local service before opening the page.
      await widget.backend.foxRequest('GET', '/api/status');
      WebViewEnvironment? env;
      if (Platform.isWindows) {
        final version = await WebViewEnvironment.getAvailableVersion();
        if (version == null) throw Exception('Microsoft Edge WebView2 Runtime is required on Windows.');
        final base = Platform.environment['LOCALAPPDATA'];
        if (base == null || base.isEmpty) throw Exception('Windows app data folder is unavailable.');
        env = await WebViewEnvironment.create(settings: WebViewEnvironmentSettings(
          userDataFolder: '$base\\OryvexVPN\\MozillaSignIn',
        ));
      }
      if (!mounted) return;
      setState(() { environment = env; initializing = false; ready = true; });
    } catch (e) {
      if (mounted) setState(() { error = 'Could not open sign-in: $e'; initializing = false; });
    }
  }

  // Only the Mozilla account page in the main frame may hand off a session.
  Future<void> acceptLogin(JavaScriptHandlerFunctionData call) async {
    final origin = call.origin;
    final source = call.requestUrl;
    if (!call.isMainFrame || origin.scheme != 'https' || origin.host != 'accounts.firefox.com' ||
        (origin.hasPort && origin.port != 443) || source.scheme != 'https' ||
        source.host != 'accounts.firefox.com' || (source.hasPort && source.port != 443) ||
        call.args.length != 1 || call.args.first is! Map || submitting || sessionId != null || closing) return;
    final payload = Map<String, dynamic>.from(call.args.first as Map);
    final email = payload['email'];
    final token = payload['sessionToken'];
    if (email is! String || email.trim().isEmpty || email.length > 320 || token is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(token)) return;
    setState(() { submitting = true; error = null; message = 'Checking your Mozilla account. Complete any verification on this page.'; });
    try {
      final response = await widget.backend.foxRequest('POST', '/api/signin/browser', {
        'email': email.trim(), 'session_token': token,
      });
      final id = response['id'];
      if (id is! String || !RegExp(r'^[a-fA-F0-9]+$').hasMatch(id)) throw Exception('Invalid sign-in response.');
      if (!mounted || closing) {
        unawaited(widget.backend.foxRequest('DELETE', '/api/signin/$id').catchError((_) => <String, dynamic>{}));
        return;
      }
      sessionId = id;
      timer?.cancel();
      timer = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(check()));
      unawaited(check());
    } catch (_) {
      if (mounted) setState(() { submitting = false; error = 'Could not complete sign-in. Check the connection and try again.'; });
    }
  }

  Future<void> check() async {
    final id = sessionId;
    if (id == null || polling || closing || !mounted) return;
    polling = true;
    try {
      final state = await widget.backend.foxRequest('GET', '/api/signin/$id');
      if (!mounted || closing) return;
      final step = state['step'];
      if (step == 'done') {
        timer?.cancel();
        sessionId = null;
        closing = true;
        Navigator.of(context).pop();
        return;
      }
      if (step == 'failed' || step == 'cancelled') {
        timer?.cancel();
        sessionId = null;
        setState(() {
          submitting = false;
          error = (state['error'] as String?) ?? 'Mozilla could not complete sign-in.';
          message = 'Try again or use Other sign-in in the Route card.';
        });
      } else {
        setState(() { message = (state['message'] as String?) ?? 'Waiting for verification…'; });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Could not check sign-in. Retrying…');
    } finally { polling = false; }
  }

  @override
  void dispose() {
    closing = true;
    timer?.cancel();
    final id = sessionId;
    if (id != null) unawaited(widget.backend.foxRequest('DELETE', '/api/signin/$id').catchError((_) => <String, dynamic>{}));
    super.dispose();
  }

  bool _allowedNavigation(Uri uri) {
    if (uri.scheme != 'https' || (uri.hasPort && uri.port != 443)) return false;
    final host = uri.host.toLowerCase();
    return host == 'accounts.firefox.com' || host == 'accounts.google.com' ||
        host == 'appleid.apple.com';
  }

  @override
  Widget build(BuildContext context) {
    // Android requires origin rules; WebView2 uses regex for the same option.
    final bridgeOrigin = Platform.isAndroid
        ? 'https://accounts.firefox.com'
        : r'^https://accounts\.firefox\.com$';
    return Scaffold(
      appBar: AppBar(title: const Text('Mozilla account sign-in')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 8), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(message),
          if (submitting || initializing) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ])),
        if (ready && (environment != null || Platform.isAndroid))
          Expanded(child: InAppWebView(
            webViewEnvironment: environment,
            initialUrlRequest: URLRequest(url: _start),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              userAgent: _firefoxUserAgent,
              useShouldOverrideUrlLoading: true,
              javaScriptBridgeForMainFrameOnly: true,
              javaScriptHandlersForMainFrameOnly: true,
              javaScriptBridgeOriginAllowList: {bridgeOrigin},
              javaScriptHandlersOriginAllowList: {r'^https://accounts\.firefox\.com$'},
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(source: _channelScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: true),
            ]),
            onWebViewCreated: (controller) {
              controller.addJavaScriptHandler(handlerName: 'firefoxAccountLogin', callback: (JavaScriptHandlerFunctionData call) {
                unawaited(acceptLogin(call));
                return null;
              });
            },
            shouldOverrideUrlLoading: (controller, action) async {
              final url = action.request.url;
              if (url == null || !_allowedNavigation(url)) return NavigationActionPolicy.CANCEL;
              return NavigationActionPolicy.ALLOW;
            },
            onReceivedError: (controller, request, failure) {
              if (request.isForMainFrame == true && mounted) {
                setState(() => error = 'Could not load the sign-in page. Check your connection.');
              }
            },
          ))
        else if (!initializing)
          const Expanded(child: Center(child: Text('Sign-in is unavailable. Return to the Route card to retry.'))),
      ])),
    );
  }
}
