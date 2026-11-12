import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/controller.dart';
import '../core/log_line.dart';
import 'theme.dart';
import 'widgets/motion.dart';
import 'widgets/section.dart';

/// Activity: the core's own log, live. Level tags, folded repeats, a filter, one-tap copy.
/// It follows new lines until you scroll up, then offers a way back to the newest.
class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.controller});

  final CoreController controller;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final _scroll = ScrollController();
  bool _follow = true;
  String _filter = 'core';
  int _seenRevision = -1;

  static const _filters = <String, String>{'core': 'Core', 'problems': 'Problems', 'all': 'All activity'};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Color _color(LogLevel l) => switch (l) {
        LogLevel.error => Ox.danger,
        LogLevel.warn => Ox.warn,
        LogLevel.info => Ox.text,
        LogLevel.plain => Ox.secondary,
        _ => Ox.tertiary,
      };

  List<LogLine> _visible() {
    final all = widget.controller.logs;
    return switch (_filter) {
      'problems' => all.where((l) => l.isProblem).toList(growable: false),
      'all' => List<LogLine>.of(all, growable: false),
      _ => all.where((l) => !l.isNoise).toList(growable: false),
    };
  }

  void _toBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final max = _scroll.position.maxScrollExtent;
      final gap = max - _scroll.offset;
      if (gap <= 0.5) return;
      if (!animate || gap > 1600 || context.reduceMotion) {
        _scroll.jumpTo(max);
      } else {
        _scroll.animateTo(max, duration: const Duration(milliseconds: 260), curve: Ox.easeOut);
      }
    });
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      final atBottom = n.metrics.pixels >= n.metrics.maxScrollExtent - 24;
      if (_follow && !atBottom && (n.scrollDelta ?? 0) < 0) {
        setState(() => _follow = false);
      } else if (!_follow && atBottom) {
        setState(() => _follow = true);
      }
    }
    return false;
  }

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, pad.top + 10, 20, pad.bottom + 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageTitle(
                eyebrow: 'Connection details',
                title: 'Activity',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ToolButton(
                      icon: Icons.copy_all_rounded,
                      tooltip: 'Copy activity',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: widget.controller.exportLogs()));
                        _snack('Activity copied to clipboard.');
                      },
                    ),
                    const SizedBox(width: 8),
                    _ToolButton(
                      icon: Icons.delete_sweep_rounded,
                      tooltip: 'Clear activity',
                      onTap: widget.controller.clearLogs,
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Segmented(
                    options: _filters,
                    value: _filter,
                    onChanged: (v) => setState(() {
                      _filter = v;
                      _follow = true;
                      _seenRevision = -1;
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Ox.radiusGroup),
                  child: ColoredBox(
                    color: Ox.tile,
                    child: ListenableBuilder(
                      listenable: widget.controller,
                      builder: (context, _) => _list(context),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final lines = _visible();
    final rev = widget.controller.logRevision;
    if (_follow && rev != _seenRevision) {
      _seenRevision = rev;
      _toBottom(animate: lines.length > 1);
    }

    final Widget body;
    if (lines.isEmpty) {
      body = Center(
        key: const ValueKey('empty'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_rounded, size: 34, color: Ox.tertiary),
              const SizedBox(height: 12),
              Text(_filter == 'problems' ? 'No issues found.' : 'No activity yet.', style: Ox.headline(22, weight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                _filter == 'problems'
                    ? 'Warnings and errors will appear here if something needs attention.'
                    : 'Connect to see live details as OryvexVPN builds your route.',
                textAlign: TextAlign.center,
                style: Ox.body(15, color: Ox.secondary),
              ),
            ],
          ),
        ),
      );
    } else {
      body = NotificationListener<ScrollNotification>(
        key: const ValueKey('list'),
        onNotification: _onScroll,
        child: Scrollbar(
          controller: _scroll,
          child: SelectionArea(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              itemCount: lines.length,
              itemBuilder: (context, i) => _line(lines[i]),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedSwitcher(duration: Ox.medium, child: body),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 14,
          child: Center(
            child: AnimatedSlide(
              offset: _follow || lines.isEmpty ? const Offset(0, 1.6) : Offset.zero,
              duration: Ox.medium,
              curve: Ox.easeOut,
              child: AnimatedOpacity(
                opacity: _follow || lines.isEmpty ? 0 : 1,
                duration: Ox.fast,
                child: Pressable(
                  onTap: _follow
                      ? null
                      : () {
                          setState(() => _follow = true);
                          _toBottom();
                        },
                  semanticLabel: 'Jump to latest',
                  borderRadius: BorderRadius.circular(99),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(color: Ox.blueCta, borderRadius: BorderRadius.circular(99)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.arrow_downward_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Text('Jump to latest', style: Ox.body(14, weight: FontWeight.w600, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _line(LogLine l) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${l.clock}  ', style: TextStyle(color: Ox.tertiary)),
          TextSpan(
            text: '${l.levelTag.padRight(5)} ',
            style: TextStyle(color: _color(l.level), fontWeight: FontWeight.w700),
          ),
          TextSpan(
            text: l.text,
            style: TextStyle(color: l.kind == LogKind.success ? Ox.blueSoft : _color(l.level)),
          ),
          if (l.repeat > 1) TextSpan(text: '  ×${l.repeat}', style: TextStyle(color: Ox.tertiary)),
        ]),
        style: Ox.code(13.5, height: 1.42),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Pressable(
        onTap: onTap,
        semanticLabel: tooltip,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: Ox.tile, shape: BoxShape.circle),
          child: Icon(icon, size: 19, color: Ox.blue),
        ),
      ),
    );
  }
}
