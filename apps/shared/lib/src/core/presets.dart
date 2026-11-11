import 'settings.dart';

/// One-tap setups for the usual situations. Each touches only the route options it names, so
/// ports, proxies and app behaviour stay as the user left them.
class RoutePreset {
  const RoutePreset({
    required this.id,
    required this.title,
    required this.tagline,
    required this.apply,
    required this.matches,
  });

  final String id;
  final String title;
  final String tagline;
  final void Function(CoreSettings s) apply;
  final bool Function(CoreSettings s) matches;

  static final all = <RoutePreset>[
    RoutePreset(
      id: 'everyday',
      title: 'Everyday',
      tagline: 'Auto route, HTTP/2, balanced scan',
      apply: (s) {
        s.protocol = 'auto';
        s.scan = 'balanced';
        s.transport = 'h2';
        s.noize = 'auto';
        s.fragment = false;
      },
      matches: (s) =>
          s.protocol == 'auto' && s.scan == 'balanced' && s.transport == 'h2' && s.noize == 'auto' && !s.fragment,
    ),
    RoutePreset(
      id: 'speed',
      title: 'Speed',
      tagline: 'WireGuard, first gateway',
      apply: (s) {
        s.protocol = 'wg';
        s.scan = 'turbo';
        s.noize = 'auto';
        s.fragment = false;
      },
      matches: (s) => s.protocol == 'wg' && s.scan == 'turbo' && s.noize == 'auto' && !s.fragment,
    ),
    RoutePreset(
      id: 'strict',
      title: 'Strict network',
      tagline: 'HTTP/2, deep scan, GFW noise',
      apply: (s) {
        s.protocol = 'auto';
        s.scan = 'thorough';
        s.transport = 'h2';
        s.noize = 'gfw';
        s.fragment = true;
      },
      matches: (s) =>
          s.protocol == 'auto' && s.scan == 'thorough' && s.transport == 'h2' && s.noize == 'gfw' && s.fragment,
    ),
    RoutePreset(
      id: 'tor',
      title: 'Tor',
      tagline: 'Plain Tor, bridges if blocked',
      apply: (s) => s.protocol = 'tor',
      matches: (s) => s.protocol == 'tor',
    ),
    RoutePreset(
      id: 'bypass',
      title: 'Bypass',
      tagline: 'Direct, beats site-name filters',
      apply: (s) => s.protocol = 'bypass',
      matches: (s) => s.protocol == 'bypass',
    ),
  ];

  /// The preset [s] currently matches, if any.
  static RoutePreset? of(CoreSettings s) {
    for (final p in all) {
      if (p.matches(s)) return p;
    }
    return null;
  }
}
