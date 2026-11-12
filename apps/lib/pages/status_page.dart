import 'package:flutter/material.dart';

import '../api/vexo_api.dart';
import '../widgets/vexo_theme.dart';

class StatusPage extends StatefulWidget {
  const StatusPage({super.key, required this.api});
  final VexoApi api;
  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _status = {};

  static const _labels = {'edge': 'Edge network', 'extract': 'Video API', 'proxy': 'Stream proxy', 'telegram': 'Telegram bot', 'admin': 'Accounts & database'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _status = asMap(await widget.api.get('/status'));
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final overall = (_status['overall'] ?? 'operational').toString();
    return PageBody(maxWidth: 980, children: [
      PageHeading(
        kicker: 'Status',
        title: 'System status',
        subtitle: 'Live health for every part of VexoStream.',
        trailing: OutlinedButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded, size: 18), label: const Text('Refresh')),
      ),
      if (_loading)
        const SizedBox(height: 260, child: PageLoader(label: 'Checking VexoStream…'))
      else if (_error != null)
        SizedBox(height: 320, child: ErrorPanel(message: _error!, onRetry: _load))
      else ...[
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _color(overall).withValues(alpha: .08),
            borderRadius: BorderRadius.circular(Vx.radius2xl),
            border: Border.all(color: _color(overall).withValues(alpha: .3)),
          ),
          child: Row(children: [
            Icon(overall == 'operational' ? Icons.check_circle_rounded : Icons.error_rounded, color: _color(overall), size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(overall == 'operational' ? 'All systems operational' : _human(overall), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Checked ${_time(_status['checked_at'])}', style: Vx.mono(size: 12)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 24),
        Container(
          decoration: Vx.surface(),
          child: Column(children: [
            for (final (i, entry) in _status.entries.where((e) => _labels.containsKey(e.key)).indexed) ...[
              if (i > 0) const Divider(),
              _row(_labels[entry.key]!, entry.value.toString()),
            ],
          ]),
        ),
        const SizedBox(height: 32),
        const PageHeading(title: 'Libraries', large: false),
        Container(
          decoration: Vx.surface(),
          child: Column(children: [
            for (final (i, raw) in asList(_status['providers']).indexed) ...[
              if (i > 0) const Divider(),
              Builder(builder: (_) {
                final p = asMap(raw);
                final on = p['available'] == true;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  child: Row(children: [
                    ProviderIcon(id: (p['id'] ?? '').toString(), name: (p['name'] ?? '').toString(), size: 30),
                    const SizedBox(width: 14),
                    Expanded(child: Text((p['name'] ?? p['id'] ?? 'Library').toString(), style: Vx.sans(size: 15, weight: FontWeight.w500))),
                    StatusPill(label: on ? 'Operational' : 'Unavailable', color: on ? Vx.green : Vx.amber, dense: true),
                  ]),
                );
              }),
            ],
          ]),
        ),
      ],
    ]);
  }

  Widget _row(String name, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        child: Row(children: [
          Expanded(child: Text(name, style: Vx.sans(size: 15, weight: FontWeight.w500))),
          StatusPill(label: _human(value), color: _color(value), dense: true),
        ]),
      );

  String _human(String value) => value.replaceAll('_', ' ').split(' ').map((x) => x.isEmpty ? x : '${x[0].toUpperCase()}${x.substring(1)}').join(' ');
  Color _color(String value) => switch (value) {
        'operational' => Vx.green,
        'degraded' => Vx.amber,
        _ => Vx.red,
      };
  String _time(dynamic value) {
    final date = value is num ? DateTime.fromMillisecondsSinceEpoch(value.toInt()) : DateTime.tryParse((value ?? '').toString());
    if (date == null) return 'just now';
    final l = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }
}
