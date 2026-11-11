/// Services the Bypass engine has built-in handling for (oryvexcore/bypass/src/engine.c,
/// SITE_FAMILY, plus the YouTube video-server and Telegram raw-stream techniques).
///
/// This is not a promise that a service opens on every network: Bypass beats filters that
/// read the site name or poison DNS, not filters that block an address. Any other site is
/// still tried automatically.
class BypassService {
  const BypassService(this.id, this.name, this.note, {this.limited = false});

  final String id;
  final String name;

  /// What is covered, or the known limit when [limited] is true.
  final String note;

  /// Known to be cut on some networks, or only partly covered.
  final bool limited;

  String get icon => 'assets/services/$id.svg';
}

const bypassServices = <BypassService>[
  BypassService('youtube', 'YouTube', 'Site and app, video servers included'),
  BypassService('x', 'X (Twitter)', 'Site, app and images'),
  BypassService('telegram', 'Telegram', 'Messages and media. Calls are not covered.', limited: true),
  BypassService('instagram', 'Instagram', 'Some networks cut it after it connects; use a tunnel route then.', limited: true),
  BypassService('whatsapp', 'WhatsApp', 'Messages only, and some networks cut it. Calls are not covered.', limited: true),
  BypassService('facebook', 'Facebook', 'Site, Messenger and media'),
  BypassService('discord', 'Discord', 'Chat and media. Voice is not covered.', limited: true),
  BypassService('reddit', 'Reddit', 'Site, app and media'),
  BypassService('twitch', 'Twitch', 'Site and streams'),
  BypassService('spotify', 'Spotify', 'App and web player'),
  BypassService('tiktok', 'TikTok', 'Site and app'),
];
