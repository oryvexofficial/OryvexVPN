import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/args.dart';
import '../core/bypass_services.dart';
import '../core/controller.dart';
import '../core/settings.dart';
import '../core/platform_links.dart';
import '../core/update_check.dart';
import 'theme.dart';
import 'widgets/brand.dart';
import 'widgets/bypass_list.dart';
import 'widgets/cloudflare_relay_setup.dart';
import 'widgets/route_about.dart';
import 'widgets/motion.dart';
import 'widgets/section.dart';
import 'widgets/tor_exit_picker.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});

  final CoreController controller;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final s = c.settings;
        void set(void Function(CoreSettings x) edit) => c.updateSettings(edit);
        int port(String v, int fallback) {
          final p = int.tryParse(v.trim());
          return p != null && p > 0 && p < 65536 ? p : fallback;
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, pad.top + 10, 20, pad.bottom + 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageTitle(eyebrow: 'Personalize your VPN', title: 'Settings'),
                  _Dirty(controller: c),
                  _SettingsColumns(children: [
                  OxSection(
                    title: 'Appearance',
                    icon: Icons.palette_outlined,
                    children: [
                      SwitchRow(
                        title: 'Dark mode',
                        subtitle: 'Use a darker interface throughout OryvexVPN.',
                        value: s.darkTheme,
                        onChanged: (v) => set((x) => x.darkTheme = v),
                      ),
                    ],
                  ),
                  OxSection(
                    title: 'App behavior',
                    icon: Icons.widgets_outlined,
                    children: [
                      SwitchRow(
                        title: 'Connect on launch',
                        subtitle: 'Connect automatically when OryvexVPN starts.',
                        value: s.autoConnect,
                        onChanged: (v) => set((x) => x.autoConnect = v),
                      ),
                      SwitchRow(
                        title: 'Automatic reconnect',
                        subtitle: 'Retry the connection up to five times if the tunnel drops.',
                        value: s.autoReconnect,
                        onChanged: (v) => set((x) => x.autoReconnect = v),
                      ),
                      if (Platform.isWindows) ...[
                        SwitchRow(
                          title: 'Launch at Windows sign-in',
                          subtitle: 'Start OryvexVPN when you sign in to Windows.',
                          value: s.launchAtStartup,
                          onChanged: (v) => set((x) => x.launchAtStartup = v),
                        ),
                        if (s.launchAtStartup)
                          SwitchRow(
                            title: 'Start minimized to the system tray',
                            subtitle: 'Keep the window hidden when OryvexVPN starts at sign-in.',
                            value: s.startInTray,
                            onChanged: (v) => set((x) => x.startInTray = v),
                          ),
                        ChoiceRow(
                          label: 'When closing the window',
                          options: Choices.closeActions,
                          value: s.closeAction,
                          hint: Choices.closeActionHints[s.closeAction],
                          onChanged: (v) => set((x) => x.closeAction = v),
                        ),
                      ],
                    ],
                  ),
                  OxSection(
                    title: 'Connection',
                    icon: Icons.alt_route_rounded,
                    footer: 'Connection changes take effect the next time you connect.',
                    children: [
                      ChoiceRow(
                        label: 'Protocol',
                        icons: protocolIcons,
                        options: Choices.protocols,
                        value: s.protocol,
                        hint: Choices.protocolHints[s.protocol],
                        onChanged: (v) => set((x) => x.protocol = v),
                      ),
                      NavRow(
                        title: 'About this connection',
                        value: 'How ${Choices.protocols[s.protocol] ?? 'it'} works',
                        icon: Icons.info_outline_rounded,
                        onTap: () => showRouteAbout(context, s.protocol, backend: c.backend),
                      ),
                      if (s.mitmOnly) NavRow(
                        title: 'Certificate',
                        value: 'Install once',
                        icon: Icons.verified_user_rounded,
                        onTap: () => showRouteAbout(context, 'mitm', backend: c.backend),
                      ),
                      if (s.mitmOnly) ChoiceRow(
                        label: 'IP version',
                        segmented: true,
                        options: Choices.ips,
                        value: s.ip,
                        onChanged: (v) => set((x) => x.ip = v),
                      ),
                      if (!s.noTunnel && (usesMasqueCarrier(s.protocol) || s.protocol == 'auto'))
                        ChoiceRow(
                          label: 'MASQUE carrier',
                          segmented: true,
                          options: Choices.transports,
                          value: s.transport,
                          hint: Choices.transportHints[s.transport],
                          onChanged: (v) => set((x) => x.transport = v),
                        ),
                      if (!s.noTunnel) ChoiceRow(
                        label: 'Scan',
                        options: Choices.scans,
                        value: s.scan,
                        hint: Choices.scanHints[s.scan],
                        onChanged: (v) => set((x) => x.scan = v),
                      ),
                      if (!s.noTunnel) ChoiceRow(
                        label: 'Obfuscation',
                        options: Choices.noizes,
                        value: s.noize,
                        hint: 'Try this when the default route is blocked or unreliable.',
                        onChanged: (v) => set((x) => x.noize = v),
                      ),
                      if (!s.noTunnel) ChoiceRow(
                        label: 'IP version',
                        segmented: true,
                        options: Choices.ips,
                        value: s.ip,
                        onChanged: (v) => set((x) => x.ip = v),
                      ),
                      if (!s.noTunnel) SwitchRow(
                        title: 'Fragment the TLS ClientHello',
                        subtitle: 'Can help when a firewall resets the TLS handshake.',
                        value: s.fragment,
                        onChanged: (v) => set((x) => x.fragment = v),
                      ),
                      if (!s.noTunnel) SwitchRow(
                        title: 'Prefer the last working gateway',
                        subtitle: 'Try the most recently successful gateway first.',
                        value: s.quickReconnect,
                        onChanged: (v) => set((x) => x.quickReconnect = v),
                      ),
                      if (s.bypassOnly) ChoiceRow(
                        label: 'IP version',
                        segmented: true,
                        options: Choices.ips,
                        value: s.ip,
                        onChanged: (v) => set((x) => x.ip = v),
                      ),
                      if (s.bypassOnly) SwitchRow(
                        title: 'Own DNS resolver',
                        subtitle: 'Look names up through encrypted DNS, so a blocked or poisoned answer cannot send you astray.',
                        value: s.bypassDoh,
                        onChanged: (v) => set((x) => x.bypassDoh = v),
                      ),
                      if (s.bypassOnly) SwitchRow(
                        title: 'Force TCP (drop QUIC)',
                        subtitle: 'Browsers fall back to TCP, where the bypass works. Turn off only if a site needs QUIC.',
                        value: s.bypassDropQuic,
                        onChanged: (v) => set((x) => x.bypassDropQuic = v),
                      ),
                      if (s.bypassOnly) NavRow(
                        title: 'Bypass list',
                        value: '${bypassServices.length} services',
                        icon: Icons.checklist_rounded,
                        onTap: () => showBypassList(context),
                      ),
                    ],
                  ),
                  if (c.backend.supportsVpn)
                    OxSection(
                      title: 'Android VPN',
                      icon: Icons.phone_android_rounded,
                      children: [
                        SwitchRow(
                          title: 'Whole-device VPN',
                          subtitle: s.torOnly
                              ? 'Route every app through Tor. DNS is answered locally.'
                              : s.mitmOnly
                                  ? 'Route the device through the MITM proxy. Browsers that trust your certificate reach the listed sites; other apps go out directly.'
                              : s.bypassOnly
                                  ? 'Route every app through the bypass engine, with its first packets reshaped.'
                                  : 'When off, only apps configured to use the proxy are routed.',
                          value: s.vpnMode,
                          onChanged: (v) => set((x) => x.vpnMode = v),
                        ),
                        SwitchRow(
                          title: 'Fake DNS',
                          subtitle: 'Resolve domain names through the tunnel without UDP.',
                          value: s.fakeDns,
                          enabled: s.vpnMode,
                          onChanged: (v) => set((x) => x.fakeDns = v),
                        ),
                        SwitchRow(
                          title: 'Tunnel IPv6',
                          subtitle: 'Prevent IPv6 traffic from bypassing the VPN.',
                          value: s.vpnIpv6,
                          enabled: s.vpnMode,
                          onChanged: (v) => set((x) => x.vpnIpv6 = v),
                        ),
                      ],
                    ),
                  const _ColumnBreak(),
                  OxSection(
                    title: 'Local proxy',
                    icon: Icons.lan_rounded,
                    children: [
                      FieldRow(
                        label: 'SOCKS5 port',
                        value: '${s.socksPort}',
                        number: true,
                        onChanged: (v) => set((x) => x.socksPort = port(v, 1819)),
                      ),
                      if (!s.foxOnly) SwitchRow(
                        title: 'HTTP proxy',
                        subtitle: 'Provide an HTTP CONNECT proxy alongside SOCKS5.',
                        value: s.httpProxy,
                        onChanged: (v) => set((x) => x.httpProxy = v),
                      ),
                      if (!s.foxOnly && (s.httpProxy ||
                          (c.backend.supportsSystemProxy && (s.systemProxy || s.directOnly)))
                        )
                        FieldRow(
                          label: 'HTTP port',
                          value: '${s.httpPort}',
                          number: true,
                          onChanged: (v) => set((x) => x.httpPort = port(v, 1820)),
                        ),
                      if (c.backend.supportsSystemProxy && !s.foxOnly)
                        SwitchRow(
                          title: 'Windows system proxy',
                          subtitle: s.directOnly
                              ? 'Automatically on for Bypass and MITM. Apps that use Windows proxy settings follow it; your previous setting is restored when disconnected.'
                              : 'Apply while connected and restore your previous setting when disconnected.',
                          value: s.systemProxy || s.directOnly,
                          enabled: !s.directOnly,
                          onChanged: (v) => set((x) => x.systemProxy = v),
                        ),
                      SwitchRow(
                        title: 'Share the proxy on your local network',
                        subtitle: 'Listens on all network interfaces without a password. Use only on trusted networks.',
                        value: s.shareLan,
                        onChanged: (v) => set((x) => x.shareLan = v),
                      ),
                    ],
                  ),
                  if (s.foxOnly)
                    OxSection(
                      title: 'Fox connection',
                      icon: Icons.public_rounded,
                      footer: 'A personal relay carries Fox control-plane requests only. It does not carry general VPN traffic.',
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                          child: Text(
                            'If Mozilla is blocked on your network, deploy a restricted Cloudflare Worker you control. The relay can see Fox sign-in and account requests, so use only your own Cloudflare account.',
                            style: Ox.body(14, color: Ox.secondary),
                          ),
                        ),
                        NavRow(
                          title: 'Deploy Cloudflare relay',
                          value: 'Cloudflare token',
                          icon: Icons.cloud_upload_outlined,
                          onTap: () => showCloudflareRelaySetup(context, backend: c.backend),
                        ),
                      ],
                    ),
                  if (s.usesTorExit)
                    OxSection(
                      title: 'Tor',
                      icon: Icons.travel_explore_rounded,
                      footer: 'Country data is fetched from the Tor directory through Tor.',
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                          child: TorExitPicker(controller: c, quickCount: 12),
                        ),
                        if (s.torExit != 'auto')
                          SwitchRow(
                            title: 'Require the selected exit country',
                            subtitle: 'Do not connect through another country if the selected exit is unavailable.',
                            value: s.torExitStrict,
                            onChanged: (v) => set((x) => x.torExitStrict = v),
                          ),
                      ],
                    ),
                  if (!s.noTunnel) OxSection(
                    title: 'Additional route',
                    icon: Icons.call_split_rounded,
                    children: [
                      ChoiceRow(
                        options: {
                          for (final e in Choices.chains.entries)
                            if (e.key != 'psiphon' || c.backend.supportsPsiphon) e.key: e.value,
                        },
                        value: s.chain,
                        hint: Choices.chainHints[s.chain],
                        onChanged: (v) => set((x) => x.chain = v),
                      ),
                      if (s.chain == 'tor')
                        FieldRow(
                          label: 'Tor proxy port',
                          value: '${s.torPort}',
                          number: true,
                          onChanged: (v) => set((x) => x.torPort = port(v, 1822)),
                        ),
                      if (s.chain == 'psiphon' && c.backend.supportsPsiphon)
                        FieldRow(
                          label: 'Psiphon proxy port',
                          value: '${s.psiphonPort}',
                          number: true,
                          onChanged: (v) => set((x) => x.psiphonPort = port(v, 1821)),
                        ),
                    ],
                  ),
                  OxSection(
                    title: 'Advanced',
                    icon: Icons.code_rounded,
                    children: [
                      FieldRow(
                        label: 'Force peer (IP:port)',
                        hint: 'Skip the scan, e.g. 162.159.198.1:443',
                        value: s.peer,
                        mono: true,
                        onChanged: (v) => set((x) => x.peer = v),
                      ),
                      FieldRow(
                        label: 'DNS servers inside the tunnel',
                        hint: '1.1.1.1,1.0.0.1',
                        value: s.dns,
                        mono: true,
                        onChanged: (v) => set((x) => x.dns = v),
                      ),
                      FieldRow(
                        label: 'Extra core arguments',
                        hint: '--masque-sni www.cloudflare.com',
                        value: s.extraArgs,
                        mono: true,
                        onChanged: (v) => set((x) => x.extraArgs = v),
                      ),
                      SwitchRow(
                        title: 'Verbose logs',
                        subtitle: 'Show more detail in Activity to help troubleshoot connection issues.',
                        value: s.verbose,
                        onChanged: (v) => set((x) => x.verbose = v),
                      ),
                    ],
                  ),
                  const _Updates(),
                  _About(platform: c.backend.platformLabel),
                  ]),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Marks where the second settings column starts on wide windows.
class _ColumnBreak extends StatelessWidget {
  const _ColumnBreak();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// The settings sections in one column, or in two side by side once there is room.
class _SettingsColumns extends StatelessWidget {
  const _SettingsColumns({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final split = children.indexWhere((w) => w is _ColumnBreak);
        if (box.maxWidth < 900 || split < 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final w in children) if (w is! _ColumnBreak) w],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children.sublist(0, split)),
            ),
            const SizedBox(width: 24),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children.sublist(split + 1)),
            ),
          ],
        );
      },
    );
  }
}

class _Dirty extends StatelessWidget {
  const _Dirty({required this.controller});

  final CoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final show = c.settingsDirty && c.isActive;
    return AnimatedSize(
      duration: context.reduceMotion ? Duration.zero : Ox.medium,
      curve: Ox.easeOut,
      alignment: Alignment.topCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: OxTile(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, color: Ox.warn, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Your settings changed. Reconnect to apply them.', style: Ox.body(15))),
                    Pressable(
                      onTap: c.canToggle ? c.reconnect : null,
                      semanticLabel: 'Reconnect',
                      borderRadius: BorderRadius.circular(99),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: Ox.blueCta, borderRadius: BorderRadius.circular(99)),
                        child: Text('Reconnect', style: Ox.body(14, weight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _About extends StatelessWidget {
  const _About({required this.platform});

  final String platform;

  @override
  Widget build(BuildContext context) {
    return OxSection(
      title: 'About',
      icon: Icons.info_outline_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Row(
            children: [
              const OxLogoTile(size: 60),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OxWordmark(size: 22),
                    const SizedBox(height: 4),
                    Text('Version $kAppVersion · $platform', style: Ox.body(14, color: Ox.secondary)),
                    const SizedBox(height: 2),
                    Text('Made by $kCreator', style: Ox.body(14, color: Ox.text, weight: FontWeight.w500)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Checks the latest GitHub release and shows whether a newer version is out.
class _Updates extends StatefulWidget {
  const _Updates();

  @override
  State<_Updates> createState() => _UpdatesState();
}

class _UpdatesState extends State<_Updates> {
  bool _checking = false;
  bool _checked = false;
  UpdateInfo? _info;

  @override
  void initState() {
    super.initState();
    // Check on open, so the section says at once when a newer release is out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() => _checking = true);
    final info = await checkForUpdate(kAppVersion);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _checked = true;
      _info = info;
    });
  }

  String get _status {
    if (_checking) return 'Checking…';
    if (!_checked) return 'Version $kAppVersion';
    final i = _info;
    if (i == null) return 'Update check failed. Try again.';
    if (i.updateAvailable) return 'Version ${i.latestVersion} is available';
    return 'Up to date';
  }

  @override
  Widget build(BuildContext context) {
    final i = _info;
    return OxSection(
      title: 'Updates',
      icon: Icons.system_update_alt_rounded,
      footer: 'The latest releases are published on github.com/$kReleasesRepo.',
      children: [
        NavRow(
          title: 'Check for updates',
          value: _status,
          icon: i?.updateAvailable == true
              ? Icons.new_releases_rounded
              : Icons.system_update_alt_rounded,
          iconColor: i?.updateAvailable == true ? Ox.warn : null,
          onTap: _checking ? null : _check,
        ),
        if (i != null && i.updateAvailable)
          NavRow(
            title: 'Download version ${i.latestVersion}',
            value: 'Open release',
            icon: Icons.new_releases_rounded,
            iconColor: Ox.warn,
            onTap: () => openExternal(i.releaseUrl),
          ),
        if (i != null && i.updateAvailable)
          NavRow(
            title: 'Copy download link',
            value: 'v${i.latestVersion}',
            icon: Icons.link_rounded,
            onTap: () {
              Clipboard.setData(ClipboardData(text: i.releaseUrl));
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(content: Text('Release link copied to clipboard.')),
              );
            },
          ),
      ],
    );
  }
}
