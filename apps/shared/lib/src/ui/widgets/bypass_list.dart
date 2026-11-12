import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/bypass_services.dart';
import '../theme.dart';

/// Opens the Bypass list: the services the engine has built-in handling for.
Future<void> showBypassList(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Bypass list',
    barrierColor: Colors.black.withValues(alpha: 0.58),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, animation, secondaryAnimation) => const _BypassListDialog(),
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(curved), child: child),
      );
    },
  );
}

class _BypassListDialog extends StatelessWidget {
  const _BypassListDialog();

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 460,
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
                padding: const EdgeInsets.fromLTRB(24, 22, 12, 0),
                child: Row(
                  children: [
                    Expanded(child: Text('Bypass list', style: Ox.headline(22))),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: Ox.secondary),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 14),
                child: Text(
                  'Built-in handling for these services. Works where the network filters site names or DNS, not where it blocks addresses.',
                  style: Ox.body(14, color: Ox.secondary),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  itemCount: bypassServices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) => _ServiceRow(service: bypassServices[i]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 20),
                child: Text('Other sites are tried automatically too.', style: Ox.body(14, color: Ox.tertiary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service});

  final BypassService service;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${service.name}. ${service.note}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: Ox.nav,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Ox.hairlineSoft),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SvgPicture.asset(service.icon, package: 'oryvex_shared', width: 36, height: 36),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service.name, style: Ox.body(15, weight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(service.note, style: Ox.body(14, color: service.limited ? Ox.warn : Ox.secondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              service.limited ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              size: 20,
              color: service.limited ? Ox.warn : Ox.success,
            ),
          ],
        ),
      ),
    );
  }
}
