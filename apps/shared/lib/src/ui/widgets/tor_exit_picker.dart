import 'package:flutter/material.dart';

import '../../core/controller.dart';
import '../../core/settings.dart';
import '../../core/tor_exits.dart';
import '../theme.dart';
import 'motion.dart';
import 'section.dart';

/// "Auto exit", "Fastest exit", "Exit in Germany": what the Tor route is set to leave from.
String torExitLabel(CoreController c) {
  final exit = c.settings.torExit;
  return switch (exit) {
    'auto' => 'Automatic exit',
    'fastest' => 'Fastest exit',
    _ => 'Exit in ${c.torExits.nameOf(exit)}',
  };
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// "74 countries · 1,312 exit relays · updated 2 h ago" or the bundled-list note.
String torDirectoryNote(TorExitDirectory dir) {
  if (dir.isBundled || dir.updated == null) {
    return 'Using the bundled list of ${dir.countries.length} exit countries. A live directory is '
        'fetched through Tor when you connect for the first time.';
  }
  return '${dir.countries.length} countries · ${dir.totalRelays} exit relays · '
      'Directory updated ${_ago(dir.updated!)}';
}

/// Where Tor leaves from: Auto, Fastest, or a country. Country shows the best-served countries
/// as tiles (two or three across, by width) and every other one in a list below.
class TorExitPicker extends StatelessWidget {
  const TorExitPicker({super.key, required this.controller, this.quickCount = 9});

  final CoreController controller;

  /// How many countries get a tile of their own before the full list.
  final int quickCount;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.settings;
    final dir = c.torExits;
    final mode = Choices.torExitMode(s.torExit);

    void pickMode(String v) {
      c.updateSettings((x) {
        if (v != 'country') {
          x.torExit = v;
        } else if (Choices.torExitMode(x.torExit) != 'country') {
          x.torExit = dir.countries.isEmpty ? 'de' : dir.countries.first.code;
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Tor exit country', style: Ox.body(15, weight: FontWeight.w500))),
            _InUse(controller: c),
          ],
        ),
        const SizedBox(height: 10),
        Segmented(options: Choices.torExitModes, value: mode, onChanged: pickMode),
        const SizedBox(height: 10),
        Text(Choices.torExitHints[mode] ?? '', style: Ox.body(14, color: Ox.secondary)),
        AnimatedSize(
          duration: Ox.medium,
          curve: Ox.easeOut,
          alignment: Alignment.topCenter,
          child: mode != 'country'
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Countries(controller: c, quickCount: quickCount),
                      const SizedBox(height: 14),
                      _BestNode(controller: c),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Text(torDirectoryNote(dir), style: Ox.body(13, color: Ox.tertiary)),
      ],
    );
  }
}

/// The exit the running proxy settled on, as a small capsule. Nothing while disconnected.
class _InUse extends StatelessWidget {
  const _InUse({required this.controller});

  final CoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final exit = c.torExitInUse;
    final String? text;
    if (exit == null) {
      text = c.isActive ? 'Choosing…' : null;
    } else if (exit == 'auto') {
      text = 'In use: Tor\'s pick';
    } else {
      text = 'In use: ${exit.toUpperCase()}${c.torExitMs == null ? '' : ' · ${c.torExitMs} ms'}';
    }
    return AnimatedSwitcher(
      duration: Ox.medium,
      child: text == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : Container(
              key: ValueKey<String>(text),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Ox.blueWash,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(text, style: Ox.body(13, weight: FontWeight.w600, color: Ox.link)),
            ),
    );
  }
}

class _Countries extends StatelessWidget {
  const _Countries({required this.controller, required this.quickCount});

  final CoreController controller;
  final int quickCount;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final chosen = c.settings.torExit;
    final all = c.torExits.countries;
    final quick = all.take(quickCount).toList();
    final inQuick = quick.any((x) => x.code == chosen);

    void pick(String code) => c.updateSettings((x) => x.torExit = code);

    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final cols = box.maxWidth >= 600 ? 3 : (box.maxWidth >= 300 ? 2 : 1);
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final x in quick)
                  SizedBox(
                    width: w,
                    child: _CountryTile(country: x, selected: x.code == chosen, onTap: () => pick(x.code)),
                  ),
              ],
            ),
            if (all.length > quick.length) ...[
              const SizedBox(height: 10),
              _AllCountries(
                countries: all,
                value: inQuick ? null : (all.any((x) => x.code == chosen) ? chosen : null),
                onChanged: pick,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A country's flag picture (assets/flags), on every platform: Windows draws no flag emoji.
/// Codes without a picture fall back to the two-letter badge.
class CountryFlag extends StatelessWidget {
  const CountryFlag({super.key, required this.code, this.size = 34, this.selected = false});

  final String code;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (!hasFlagAsset(code)) return CountryCodeBadge(code: code, selected: selected, size: size);
    return SizedBox(
      width: size * 1.34,
      height: size,
      child: Image.asset(
        flagAsset(code),
        package: 'oryvex_shared',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: code.toUpperCase(),
        errorBuilder: (context, error, stack) => CountryCodeBadge(code: code, selected: selected, size: size),
      ),
    );
  }
}

/// A two-letter badge, for codes without a flag picture.
class CountryCodeBadge extends StatelessWidget {
  const CountryCodeBadge({super.key, required this.code, this.selected = false, this.size = 34});

  final String code;
  final bool selected;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Ox.medium,
      curve: Ox.easeOut,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? Ox.blueCta : Ox.tileHi,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        code.toUpperCase(),
        style: Ox.code(size * 0.38, weight: FontWeight.w700, height: 1.0, color: selected ? Colors.white : Ox.text),
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({required this.country, required this.selected, required this.onTap});

  final TorExitCountry country;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final detail = country.detail;
    return Pressable(
      onTap: onTap,
      scale: 0.97,
      semanticLabel: 'Leave Tor from ${country.name}',
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: Ox.medium,
        curve: Ox.easeOut,
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        decoration: BoxDecoration(
          color: selected ? Ox.blue.withValues(alpha: 0.12) : Ox.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? Ox.blueCta : Ox.hairlineSoft, width: selected ? 1.5 : 1),
        ),
        child: Row(
          children: [
            CountryFlag(code: country.code, selected: selected),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(country.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Ox.body(14, weight: FontWeight.w600)),
                  if (detail.isNotEmpty)
                    Text(detail,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: Ox.body(12.5, color: Ox.secondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllCountries extends StatelessWidget {
  const _AllCountries({required this.countries, required this.value, required this.onChanged});

  final List<TorExitCountry> countries;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final sorted = List<TorExitCountry>.of(countries)..sort((a, b) => a.name.compareTo(b.name));
    final selected = sorted.where((x) => x.code == value).firstOrNull;
    return Pressable(
      onTap: () async {
        final code = await showDialog<String>(
          context: context,
          builder: (_) => _TorCountryPickerDialog(countries: sorted, value: value),
        );
        if (code != null) onChanged(code);
      },
      borderRadius: BorderRadius.circular(14),
      semanticLabel: 'Browse all ${countries.length} Tor exit countries',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Ox.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Ox.hairlineSoft),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: Ox.link),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(selected == null ? 'Browse all countries' : selected.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: Ox.body(15, weight: FontWeight.w600)),
                  Text('${countries.length} available Tor exit countries',
                      style: Ox.body(12.5, color: Ox.secondary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Ox.secondary),
          ],
        ),
      ),
    );
  }
}

class _TorCountryPickerDialog extends StatefulWidget {
  const _TorCountryPickerDialog({required this.countries, required this.value});

  final List<TorExitCountry> countries;
  final String? value;

  @override
  State<_TorCountryPickerDialog> createState() => _TorCountryPickerDialogState();
}

class _TorCountryPickerDialogState extends State<_TorCountryPickerDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final matches = widget.countries.where((country) {
      final query = _query.trim().toLowerCase();
      return query.isEmpty || country.name.toLowerCase().contains(query) || country.code.toLowerCase().contains(query);
    }).toList();
    return Dialog(
      backgroundColor: Ox.card,
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Ox.hairlineSoft),
      ),
      child: SizedBox(
        width: size.width < 560 ? size.width - 44 : 500,
        height: size.height < 700 ? size.height - 60 : 620,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 10, 12),
              child: Row(
                children: [
                  Expanded(child: Text('Choose a Tor exit country', style: Ox.headline(20, weight: FontWeight.w600))),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: Ox.secondary),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (text) => setState(() => _query = text),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Search country or code',
                  filled: true,
                  fillColor: Ox.field,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            Expanded(
              child: matches.isEmpty
                  ? Center(child: Text('No matching countries', style: Ox.body(14, color: Ox.secondary)))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final country = matches[index];
                        final selected = country.code == widget.value;
                        return Material(
                          color: selected ? Ox.blue.withValues(alpha: 0.12) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            leading: CountryFlag(code: country.code, size: 26, selected: selected),
                            title: Text(country.name, style: Ox.body(14, weight: selected ? FontWeight.w600 : FontWeight.w500)),
                            subtitle: country.detail.isEmpty ? null : Text(country.detail, style: Ox.body(12, color: Ox.secondary)),
                            trailing: selected ? Icon(Icons.check_circle_rounded, color: Ox.link) : null,
                            onTap: () => Navigator.of(context).pop(country.code),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Best exit node": measure several exits in the chosen country and keep the quickest
/// circuit, with the country's strongest relays from the Tor directory below.
class _BestNode extends StatelessWidget {
  const _BestNode({required this.controller});

  final CoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.settings;
    final country = c.torExits.find(s.torExit);
    final name = c.torExits.nameOf(s.torExit);
    final top = country?.top ?? const <TorExitRelay>[];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: Ox.field,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: s.torExitBest ? Ox.blueCta.withValues(alpha: 0.55) : Ox.hairlineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_rounded, size: 20, color: Ox.link),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Find the best exit in $name', style: Ox.body(15, weight: FontWeight.w600)),
                    Text(
                      'Compare ${Choices.torExitBestProbes} relays in parallel and use the fastest circuit.',
                      style: Ox.body(13, color: Ox.secondary),
                    ),
                  ],
                ),
              ),
              Switch(value: s.torExitBest, onChanged: (v) => c.updateSettings((x) => x.torExitBest = v)),
            ],
          ),
          if (top.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Top relays in $name', style: Ox.body(13, weight: FontWeight.w600, color: Ox.tertiary)),
            const SizedBox(height: 4),
            for (var i = 0; i < top.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 22, child: Text('${i + 1}', style: Ox.code(13, color: Ox.tertiary))),
                    Expanded(
                      child: Text(top[i].nickname,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: Ox.body(14, weight: FontWeight.w500)),
                    ),
                    Text(top[i].shortFingerprint, style: Ox.code(12, color: Ox.tertiary)),
                    const SizedBox(width: 10),
                    Text(formatBandwidth(top[i].bandwidth), style: Ox.code(12, color: Ox.secondary)),
                  ],
                ),
              ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Relay names appear after OryvexVPN loads the live Tor directory on your first Tor connection.',
                  style: Ox.body(13, color: Ox.tertiary)),
            ),
        ],
      ),
    );
  }
}
