import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// An available interface does not guarantee internet access.
class OfflineMonitor extends StatefulWidget {
  const OfflineMonitor({super.key, required this.child, this.onReconnected});
  final Widget child;
  final VoidCallback? onReconnected;

  @override
  State<OfflineMonitor> createState() => _OfflineMonitorState();
}

class _OfflineMonitorState extends State<OfflineMonitor> with WidgetsBindingObserver {
  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _offline = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = _connectivity.onConnectivityChanged.listen(_update);
    unawaited(_check());
  }

  Future<void> _check() async {
    try {
      _update(await _connectivity.checkConnectivity());
    } catch (_) {
      // Unknown network state is not necessarily offline.
    }
  }

  void _update(List<ConnectivityResult> results) {
    if (!mounted) return;
    final offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    final reconnected = _offline && !offline;
    if (offline != _offline) setState(() {
      _offline = offline;
      if (!offline) _dismissed = false;
    });
    if (reconnected) widget.onReconnected?.call();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        reverseDuration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: Tween<double>(begin: .88, end: 1).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn)), child: child),
        ),
        child: _offline && !_dismissed
            ? Material(
                key: const ValueKey('offline'),
                color: Colors.black54,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Card(
                      margin: const EdgeInsets.all(24),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.wifi_off_rounded, size: 44),
                          const SizedBox(height: 18),
                          Text('No internet connection', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          const Text('Connect to Wi-Fi or mobile data, then try again.', textAlign: TextAlign.center),
                          const SizedBox(height: 20),
                          FilledButton.icon(onPressed: _check, icon: const Icon(Icons.refresh), label: const Text('Check again')),
                          TextButton(onPressed: () => setState(() => _dismissed = true), child: const Text('Dismiss')),
                        ]),
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(key: ValueKey('online')),
      ),
    ],
  );
}
