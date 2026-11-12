import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/backend.dart';
import '../../core/route_about.dart';
import '../theme.dart';
import 'section.dart';

/// "About this connection": what the route is, how it works, what it is good and bad at, and
/// where it runs. [backend] is only needed for MITM, whose certificate it installs.
Future<void> showRouteAbout(BuildContext context, String protocol, {CoreBackend? backend}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'About this connection',
    barrierColor: Colors.black.withValues(alpha: 0.58),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondaryAnimation) => _RouteAboutDialog(protocol: protocol, backend: backend),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(curved), child: child),
      );
    },
  );
}

class _RouteAboutDialog extends StatefulWidget {
  const _RouteAboutDialog({required this.protocol, this.backend});

  final String protocol;
  final CoreBackend? backend;

  @override
  State<_RouteAboutDialog> createState() => _RouteAboutDialogState();
}

class _RouteAboutDialogState extends State<_RouteAboutDialog> {
  bool _busy = false;
  String? _result;

  Future<void> _install() async {
    final backend = widget.backend;
    if (backend == null) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    String message;
    try {
      message = await backend.installMitmCertificate();
    } catch (e) {
      message = 'Could not install the certificate: $e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final about = routeAbout[widget.protocol];
    final size = MediaQuery.sizeOf(context);
    final icon = protocolIcons[widget.protocol];
    if (about == null) return const SizedBox.shrink();
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 500,
          constraints: BoxConstraints(maxHeight: size.height - 48),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Ox.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Ox.hairlineSoft),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 48, offset: const Offset(0, 20))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: SvgPicture.asset(icon, package: 'oryvex_shared', width: 36, height: 36),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(child: Text(about.title, style: Ox.headline(22))),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: Ox.secondary),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(about.summary, style: Ox.body(15)),
                      const SizedBox(height: 18),
                      _Heading('How it works'),
                      for (var i = 0; i < about.how.length; i++) _Step(number: i + 1, text: about.how[i]),
                      const SizedBox(height: 14),
                      _Heading('Good at'),
                      for (final t in about.good) _Bullet(text: t, color: Ox.success, icon: Icons.check_circle_rounded),
                      const SizedBox(height: 14),
                      _Heading('Keep in mind'),
                      for (final t in about.limits) _Bullet(text: t, color: Ox.warn, icon: Icons.error_outline_rounded),
                      const SizedBox(height: 14),
                      _Heading('Runs on'),
                      Text(about.platforms, style: Ox.body(14, color: Ox.secondary)),
                      if (widget.protocol == 'mitm' && widget.backend != null) ...[
                        const SizedBox(height: 20),
                        _Heading('Certificate'),
                        Text(
                          'Install it once. It was made on this device and only trusts the sites above. Never share the .key file or install a certificate someone else gave you.',
                          style: Ox.body(14, color: Ox.secondary),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _busy ? null : _install,
                          icon: _busy
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.verified_user_rounded),
                          label: const Text('Install certificate'),
                        ),
                        if (_result != null) ...[
                          const SizedBox(height: 12),
                          SelectableText(_result!, style: Ox.body(14, color: Ox.secondary)),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: Ox.body(14, weight: FontWeight.w700, color: Ox.tertiary)),
      );
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 24, child: Text('$number.', style: Ox.body(14, weight: FontWeight.w700, color: Ox.blue))),
            Expanded(child: Text(text, style: Ox.body(14))),
          ],
        ),
      );
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, required this.color, required this.icon});

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: color)),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: Ox.body(14))),
          ],
        ),
      );
}
