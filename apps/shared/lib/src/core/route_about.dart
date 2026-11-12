/// What each connection is and how it works, shown in the app for every route.
class RouteAbout {
  const RouteAbout({
    required this.title,
    required this.summary,
    required this.how,
    required this.good,
    required this.limits,
    required this.platforms,
  });

  final String title;
  final String summary;

  /// Numbered steps, in the order things happen.
  final List<String> how;
  final List<String> good;
  final List<String> limits;
  final String platforms;
}

const routeAbout = <String, RouteAbout>{
  'fox': RouteAbout(
    title: 'Fox',
    summary: 'An unofficial Firefox Account VPN client that connects through Mozilla’s VPN service. It is independent of Mozilla and is not endorsed by Mozilla.',
    how: [
      'Sign in with a Firefox Account in Fox’s local dashboard.',
      'Fox obtains a Mozilla VPN pass and opens an encrypted proxy connection.',
      'Choose a server location in the dashboard; its country flags and server list come from Mozilla’s available locations.',
      'On Android, the app can route the whole device through its VPN service.',
    ],
    good: ['Uses your Firefox Account', 'Country, server and account management in one local dashboard'],
    limits: [
      'Requires a Firefox Account with Mozilla VPN access and is subject to Mozilla’s service limits.',
      'This is an unofficial client, not a Mozilla product.',
      'The dashboard opens in your browser on this device.',
    ],
    platforms: 'Windows 10/11 (x64) and Android 7.0+ (ARM64 and ARMv7).',
  ),
  'auto': RouteAbout(
    title: 'Auto',
    summary: 'Tries the tunnel routes one after another and keeps the first that connects.',
    how: [
      'WireGuard is tried first, then MASQUE, MASQUE², then Gool.',
      'Each gets a time limit; a route that does not come up in time is dropped.',
      'The first one that passes real traffic is kept, and the app shows which one it is.',
    ],
    good: ['No choices to make', 'Adapts when a network blocks one protocol'],
    limits: ['Connecting can take longer on a heavily filtered network'],
    platforms: 'Android 7.0+, Windows 10/11 (x64).',
  ),
  'wg': RouteAbout(
    title: 'WireGuard',
    summary: 'A fast WireGuard tunnel to a Cloudflare WARP gateway.',
    how: [
      'The app scans for a WARP gateway that answers and checks its handshake.',
      'It builds the WireGuard tunnel over UDP and sends your traffic through it.',
      'Your address becomes a Cloudflare one.',
    ],
    good: ['Fastest tunnel', 'Low battery use'],
    limits: ['Needs UDP to reach the gateway; some networks block it'],
    platforms: 'Android 7.0+, Windows 10/11 (x64).',
  ),
  'masque': RouteAbout(
    title: 'MASQUE',
    summary: 'A tunnel that looks like ordinary HTTPS (HTTP/2) or HTTP/3 traffic.',
    how: [
      'The app finds a gateway and opens a TLS connection to it.',
      'Your traffic is wrapped inside that connection (the MASQUE standard).',
      'To a filter it looks like a visit to a normal website.',
    ],
    good: ['Works where UDP or VPN protocols are blocked (HTTP/2)', 'Blends in'],
    limits: ['A little slower than WireGuard'],
    platforms: 'Android 7.0+, Windows 10/11 (x64).',
  ),
  'mim': RouteAbout(
    title: 'MASQUE²',
    summary: 'MASQUE carried inside MASQUE, for a different exit address.',
    how: [
      'An outer MASQUE tunnel is opened to a gateway.',
      'A second MASQUE tunnel is opened through the first.',
      'Traffic leaves from the inner hop.',
    ],
    good: ['A second layer when a single tunnel is blocked'],
    limits: ['Slowest of the tunnels; two handshakes'],
    platforms: 'Android 7.0+, Windows 10/11 (x64).',
  ),
  'gool': RouteAbout(
    title: 'Gool',
    summary: 'WireGuard carried inside MASQUE.',
    how: [
      'A MASQUE tunnel is opened first, which looks like HTTPS.',
      'WireGuard runs inside it, so UDP is never exposed to the network.',
      'Traffic leaves with a different exit address.',
    ],
    good: ['WireGuard speed with HTTPS disguise'],
    limits: ['Two layers, so a longer start'],
    platforms: 'Android 7.0+, Windows 10/11 (x64).',
  ),
  'tor': RouteAbout(
    title: 'Tor',
    summary: 'Sends your traffic through the Tor network, using bridges when Tor is blocked.',
    how: [
      'The app bootstraps Tor, with bridges if direct access fails.',
      'It builds a circuit of three relays.',
      'You can pick the exit country; traffic leaves from that exit.',
    ],
    good: ['Strong anonymity', 'Works with bridges where Tor is blocked'],
    limits: ['Slower than a VPN', 'Some sites block Tor exits'],
    platforms: 'Android 7.0+, Windows 10/11 (x64).',
  ),
  'bypass': RouteAbout(
    title: 'Bypass',
    summary: 'Goes out directly and reshapes the first packets so a filter cannot read the site name.',
    how: [
      'Names are looked up through an encrypted DNS resolver, so poisoned answers cannot mislead you.',
      'The first bytes of each connection (TLS hello or HTTP request) are split, reordered or padded with decoys.',
      'A filter that matches the site name in those bytes no longer sees it; the real server still does.',
    ],
    good: ['No account, no server', 'Your speed and address stay the same'],
    limits: ['Does not beat filters that rebuild the whole stream or block by address'],
    platforms: 'Android 7.0+, Windows 7 to 11, Linux, macOS, OpenWrt.',
  ),
  'mitm': RouteAbout(
    title: 'MITM (domain fronting)',
    summary:
        'Reaches YouTube, Google, Instagram, WhatsApp, Facebook, Reddit and other Fastly sites with no server: the app re-sends your request with another site\'s name in the handshake.',
    how: [
      'On first use the app makes a private certificate authority on your device. The key never leaves it.',
      'You install its certificate as trusted once (the button below).',
      'When your browser opens a listed site, the app answers the secure handshake itself using that certificate, so it can read the request.',
      'It then connects to the real server, but names a harmless site (for example www.google.com) in the handshake. That name is all a filter sees.',
      'It checks the server\'s real certificate, and relays the answer to your browser. Name lookups use encrypted DNS.',
    ],
    good: ['No server, no account, no v2ray', 'Free and fast: your traffic is not tunnelled', 'Everything else goes out untouched'],
    limits: [
      'Only reaches the listed services, not the whole internet',
      'Use a browser: most other Android apps ignore certificates you install',
      'Firefox needs its own certificate setting; your address does not change',
    ],
    platforms:
        'Windows 10/11 (installs the certificate for you), Android 7.0+ (browsers; install the certificate once from Settings), Linux, macOS and OpenWrt through the core (oryvexcore --mitm).',
  ),
};
