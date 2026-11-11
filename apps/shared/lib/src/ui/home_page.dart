import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/args.dart';
import '../core/bypass_services.dart';
import '../core/controller.dart';
import '../core/settings.dart';
import 'theme.dart';
import 'widgets/brand.dart';
import 'widgets/bypass_list.dart';
import 'widgets/motion.dart';
import 'widgets/orb.dart';
import 'widgets/section.dart';
import 'widgets/sparkline.dart';
import 'widgets/steps_view.dart';
import 'widgets/tor_exit_picker.dart';

/// The Connect page: a connection panel (where you stand, the orb, one action) beside a live
/// dashboard (progress, numbers, route). Side by side on wide windows, stacked on narrow ones.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller, this.onOpenActivity, this.showHeader = true});

  final CoreController controller;
  final VoidCallback? onOpenActivity;

  /// The brand row at the top. Off when a navigation bar already shows it.
  final bool showHeader;

  /// Widest the page content grows; past this it stays centred.
  static const maxContent = 1240.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final pad = MediaQuery.paddingOf(context);
        final busy = c.state == CoreState.starting ||
            c.state == CoreState.connecting ||
            c.state == CoreState.reconnecting;

        return LayoutBuilder(
          builder: (context, box) {
            final side = box.maxWidth < 600 ? 16.0 : 24.0;
            final content = math.max(0.0, math.min(box.maxWidth - side * 2, maxContent));
            final wide = content >= 820;
            final panelWidth = wide ? (content - 20) * 11 / 21 : content;
            final orbSize = (panelWidth * 0.66).clamp(200.0, 300.0);

            final panel = _ConnectionPanel(
              controller: c,
              orbSize: orbSize,
              compact: panelWidth < 520,
              onOpenActivity: onOpenActivity,
            );
            final steps = _Collapsible(
              show: busy,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: StepsView(plan: c.plan, stageSince: c.stageSince, onOpenActivity: onOpenActivity),
              ),
            );
            final stats = Reveal(delay: const Duration(milliseconds: 120), child: _Bento(controller: c));
            final route = Reveal(delay: const Duration(milliseconds: 220), child: _RouteAndMode(controller: c));

            final Widget body = wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 11, child: panel),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 10,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [steps, stats, const SizedBox(height: 14), route],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [panel, const SizedBox(height: 16), steps, stats, const SizedBox(height: 14), route],
                  );

            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(side, pad.top + 16, side, pad.bottom + 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: maxContent),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showHeader)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Row(
                            children: [
                              const OxMark(size: 28),
                              const SizedBox(width: 10),
                              Flexible(child: OxWordmark(size: 21)),
                            ],
                          ),
                        ),
                      _Collapsible(
                        show: c.lastError != null,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _Banner(
                            icon: Icons.error_outline_rounded,
                            color: Ox.danger,
                            message: c.lastError ?? '',
                            onClose: c.dismissError,
                            action: onOpenActivity == null ? null : OxLink('View details', onTap: onOpenActivity),
                          ),
                        ),
                      ),
                      _Collapsible(
                        show: c.settingsDirty && c.isActive,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _Banner(
                            icon: Icons.tune_rounded,
                            color: Ox.warn,
                            message: 'Your settings changed. Reconnect to apply them.',
                            action: OxLink('Reconnect', onTap: c.canToggle ? c.reconnect : null),
                          ),
                        ),
                      ),
                      body,
                      const SizedBox(height: 18),
                      OxCredit(),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// The connection panel: status, the orb and the one action, on a tile lit from within by the
/// brand blue. The light grows while connecting, fills the tile once the tunnel is up, and turns
/// amber while a dropped tunnel is being restored.
class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({
    required this.controller,
    required this.orbSize,
    required this.compact,
    this.onOpenActivity,
  });

  final CoreController controller;
  final double orbSize;
  final bool compact;
  final VoidCallback? onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final on = c.state == CoreState.connected;
    final glow = c.state == CoreState.reconnecting ? Ox.warn : Ox.blue;
    final strength = on ? 0.24 : (c.state.busy ? 0.15 : 0.07);
    final protocol = c.settings.protocol;
    return AnimatedContainer(
      duration: Ox.slow,
      curve: Ox.easeInOut,
      decoration: BoxDecoration(
        color: Ox.tile,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: on ? Ox.blue.withValues(alpha: 0.38) : Ox.hairlineSoft),
        boxShadow: Ox.tileShadow,
      ),
      child: AnimatedContainer(
        duration: Ox.slow,
        curve: Ox.easeInOut,
        padding: EdgeInsets.fromLTRB(compact ? 16 : 28, 18, compact ? 16 : 28, 26),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(31),
          gradient: RadialGradient(
            center: const Alignment(0, -0.05),
            radius: 0.9,
            colors: [glow.withValues(alpha: strength), glow.withValues(alpha: 0)],
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                StatusPill(state: c.state, vpnUp: c.vpnUp),
                const Spacer(),
                _RouteChip(label: Choices.protocols[protocol] ?? 'Auto', icon: protocolIcons[protocol]),
              ],
            ),
            const SizedBox(height: 8),
            _Hero(controller: c, orbSize: orbSize, compact: compact, onOpenActivity: onOpenActivity),
          ],
        ),
      ),
    );
  }
}

/// The chosen route as a small capsule with its icon, at the top of the connection panel.
class _RouteChip extends StatelessWidget {
  const _RouteChip({required this.label, this.icon});

  final String label;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(icon == null ? 12 : 6, 5, 12, 5),
      decoration: BoxDecoration(
        color: Ox.field,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Ox.hairlineSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            SvgPicture.asset(icon!, package: 'oryvex_shared', width: 20, height: 20),
            const SizedBox(width: 6),
          ],
          Text(label, style: Ox.body(13, weight: FontWeight.w600, color: Ox.secondary)),
        ],
      ),
    );
  }
}

/// Grows open / folds shut around [child] and cross-fades it.
class _Collapsible extends StatelessWidget {
  const _Collapsible({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: Ox.medium,
      curve: Ox.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: Ox.medium,
        switchInCurve: Ox.easeOut,
        switchOutCurve: Ox.easeIn,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero).animate(a),
            child: child,
          ),
        ),
        child: show ? KeyedSubtree(key: const ValueKey('on'), child: child) : const SizedBox(key: ValueKey('off'), width: double.infinity),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.controller, required this.orbSize, required this.compact, this.onOpenActivity});

  final CoreController controller;
  final double orbSize;
  final bool compact;
  final VoidCallback? onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.settings;
    final step = c.plan.current;
    final shown = c.routeProtocol;
    final String route;
    if (s.bypassOnly) {
      route = 'Bypass · direct, packets reshaped';
    } else if (s.torOnly) {
      route = 'Tor · ${torExitLabel(c)}';
    } else {
      final carrier = usesMasqueCarrier(shown) ? ' over ${Choices.transports[s.transport]}' : '';
      final autoStep = c.autoStepLabel;
      final count = autoStep == null ? '' : ' ($autoStep)';
      route = c.isAuto
          ? 'Auto · ${Choices.protocolLong(shown)}$carrier$count'
          : '${Choices.protocolLong(shown)}$carrier';
    }

    final (String eyebrow, Color eyebrowColor) = switch (c.state) {
      CoreState.stopped => ('Private by Design', Ox.blue),
      CoreState.starting => ('Getting Ready', Ox.blue),
      CoreState.connecting => (step?.title ?? 'Connecting', Ox.blue),
      CoreState.connected => (c.vpnUp ? 'Protected across all apps' : 'Tunnel connected', Ox.blue),
      CoreState.reconnecting => ('Restoring connection', Ox.warn),
      CoreState.stopping => ('Closing the tunnel', Ox.secondary),
    };

    final String sub = switch (c.state) {
      // On a narrow panel the gateway stays in its own tile, so the line never gets cut off.
      CoreState.connected => c.edge != null && !compact ? 'Via ${c.edge}  ·  $route' : route,
      CoreState.connecting || CoreState.reconnecting => c.isAuto ? route : (step?.detail ?? route),
      CoreState.starting => c.isAuto && c.activeProtocol != null ? route : 'Checking your ports…',
      CoreState.stopping => 'Disconnecting securely…',
      CoreState.stopped => c.isAuto
          ? 'Auto: WireGuard › MASQUE › MASQUE² › Gool'
          : (s.noTunnel ? route : '$route  ·  ${Choices.scans[s.scan]} scan'),
    };

    return Column(
      children: [
        const SizedBox(height: 6),
        BlurSwitcher(
          child: Text(eyebrow,
              key: ValueKey<String>('e$eyebrow'), textAlign: TextAlign.center, style: Ox.eyebrow(color: eyebrowColor)),
        ),
        const SizedBox(height: 6),
        BlurSwitcher(
          child: FittedBox(
            key: ValueKey<CoreState>(c.state),
            fit: BoxFit.scaleDown,
            child: Text(
              c.state.headline,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: Ox.headline(compact ? 44 : 64),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 24,
          child: BlurSwitcher(
            duration: const Duration(milliseconds: 380),
            child: Text(
              sub,
              key: ValueKey<String>(sub),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ox.body(17, color: Ox.secondary),
            ),
          ),
        ),
        const SizedBox(height: 22),
        ConnectOrb(
          state: c.state,
          progress: c.plan.progress,
          size: orbSize,
          onTap: c.canToggle ? c.toggle : null,
        ),
        const SizedBox(height: 20),
        _Cta(state: c.state, onTap: c.canToggle ? c.toggle : null),
        if (onOpenActivity != null) ...[
          const SizedBox(height: 14),
          OxLink('View Activity', onTap: onOpenActivity),
        ],
      ],
    );
  }
}

/// The pill call to action under the orb: filled blue to connect, quiet grey to stop.
class _Cta extends StatelessWidget {
  const _Cta({required this.state, required this.onTap});

  final CoreState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = state == CoreState.stopped;
    final label = switch (state) {
      CoreState.stopped => 'Connect',
      CoreState.connected => 'Disconnect',
      CoreState.stopping => 'Disconnecting',
      _ => 'Cancel connection',
    };
    return Center(
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: Ox.medium,
          curve: Ox.easeInOut,
          constraints: const BoxConstraints(minWidth: 190),
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: primary ? Ox.blueCta : Ox.tileHi,
            borderRadius: BorderRadius.circular(99),
          ),
          alignment: Alignment.center,
          child: BlurSwitcher(
            duration: const Duration(milliseconds: 360),
            child: Text(
              label,
              key: ValueKey<String>(label),
              style: Ox.body(17,
                  weight: FontWeight.w600,
                  color: primary ? Colors.white : (state == CoreState.stopping ? Ox.secondary : Ox.text)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small frosted status capsule: a dot that breathes while working, and a word.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.state, required this.vpnUp, this.dense = false, this.showLabel = true});

  final CoreState state;
  final bool vpnUp;
  final bool dense;

  /// Off on narrow bars: the dot alone still tells the state, by colour and pulse.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final on = state == CoreState.connected;
    final text = on ? (vpnUp ? 'VPN protected' : 'Connected') : (state.busy ? state.label : 'Off');
    final color = on ? Ox.blue : (state == CoreState.reconnecting ? Ox.warn : (state.busy ? Ox.blueSoft : Ox.tertiary));
    return AnimatedContainer(
      duration: Ox.medium,
      curve: Ox.easeInOut,
      padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 5 : 7),
      decoration: BoxDecoration(
        color: on ? Ox.blueWash : Ox.tileHi,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: color, pulsing: state.busy),
          if (showLabel) ...[
            const SizedBox(width: 7),
            AnimatedSize(
              duration: Ox.medium,
              curve: Ox.easeOut,
              child: Text(text, style: Ox.body(dense ? 13 : 14, weight: FontWeight.w600, color: on ? Ox.text : Ox.secondary)),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.pulsing && _c.isAnimating) {
      _c.animateTo(0, duration: Ox.fast);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = Curves.easeInOut.transform(_c.value);
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: widget.color),
          duration: Ox.medium,
          builder: (context, color, _) => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: (color ?? widget.color).withValues(alpha: 0.55 * v), blurRadius: 8, spreadRadius: 1.5 * v),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.message, this.onClose, this.action});

  final IconData icon;
  final Color color;
  final String message;
  final VoidCallback? onClose;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), Ox.tile),
        borderRadius: BorderRadius.circular(Ox.radiusGroup),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, maxLines: 5, overflow: TextOverflow.ellipsis, style: Ox.body(15)),
                if (action != null) Padding(padding: const EdgeInsets.only(top: 6), child: action),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Dismiss message',
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: Icon(Icons.close_rounded, size: 18, color: Ox.secondary),
            ),
        ],
      ),
    );
  }
}

/// The live numbers: download and upload with graphs, session time and the gateway in use.
/// Four across when there is room, two otherwise, one on very narrow screens.
class _Bento extends StatelessWidget {
  const _Bento({required this.controller});

  final CoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final on = c.state == CoreState.connected;
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 12.0;
        final cols = box.maxWidth >= 640 ? 4 : (box.maxWidth >= 300 ? 2 : 1);
        // Floored so rounding can never push the last tile onto a new row.
        final w = ((box.maxWidth - gap * (cols - 1)) / cols).floorToDouble();
        final tiles = <Widget>[
          _MetricTile(
            icon: Icons.south_rounded,
            label: 'Download',
            value: CoreController.formatRate(c.downNow),
            foot: '${c.down} total',
            graph: Sparkline(samples: c.downRate, tick: c.rateTick, color: Ox.blue, height: 28),
          ),
          _MetricTile(
            icon: Icons.north_rounded,
            label: 'Upload',
            value: CoreController.formatRate(c.upNow),
            foot: '${c.up} total',
            graph: Sparkline(samples: c.upRate, tick: c.rateTick, color: Ox.blueSoft, height: 28),
          ),
          Ticking(
            enabled: on,
            builder: (context) => _MetricTile(
              icon: Icons.schedule_rounded,
              label: 'Session',
              value: on ? c.uptime : '00:00:00',
              mono: true,
              foot: on ? 'Tunnel up' : 'Starts when you connect',
            ),
          ),
          if (c.settings.torOnly)
            _MetricTile(
              icon: Icons.travel_explore_rounded,
              label: 'Tor exit',
              value: c.torExitInUse == null
                  ? '—'
                  : (c.torExitInUse == 'auto' ? 'Auto' : c.torExitInUse!.toUpperCase()),
              mono: true,
              foot: c.torExitInUse == null
                  ? torExitLabel(c)
                  : (c.torExitInUse == 'auto'
                      ? 'Tor picks by bandwidth'
                      : '${c.torExits.nameOf(c.torExitInUse!)}${c.torExitMs == null ? '' : ' · ${c.torExitMs} ms'}'),
            )
          else if (c.settings.bypassOnly)
            _MetricTile(
              icon: Icons.checklist_rounded,
              label: 'Bypass list',
              value: '${bypassServices.length} services',
              foot: 'Tap to see what it covers',
              onTap: () => showBypassList(context),
            )
          else
            _MetricTile(
              icon: Icons.hub_rounded,
              label: 'Gateway',
              value: c.edge ?? '—',
              mono: true,
              foot: Choices.protocolLong(c.routeProtocol),
            ),
        ];
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, height: 150, child: t)],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.foot,
    this.graph,
    this.mono = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String foot;
  final Widget? graph;
  final bool mono;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = _tile();
    if (onTap == null) return tile;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      semanticLabel: label,
      borderRadius: BorderRadius.circular(Ox.radiusTile),
      child: tile,
    );
  }

  Widget _tile() {
    return OxTile(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: Ox.blueWash, borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 16, color: Ox.link),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Ox.body(14, color: Ox.secondary, weight: FontWeight.w500)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: Ox.fast,
              child: Text(
                value,
                key: ValueKey<String>(value),
                maxLines: 1,
                style: mono
                    ? Ox.code(19, weight: FontWeight.w600, height: 1.2)
                    : Ox.headline(24, weight: FontWeight.w700),
              ),
            ),
          ),
          const Spacer(),
          if (graph != null) graph!,
          if (graph != null) const SizedBox(height: 4),
          Text(foot, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ox.body(13, color: Ox.tertiary)),
        ],
      ),
    );
  }
}

/// Route, mode and local proxy. Side by side on wide windows, stacked on phones.
class _RouteAndMode extends StatelessWidget {
  const _RouteAndMode({required this.controller});

  final CoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.settings;
    final route = OxTile(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Route', style: Ox.headline(22, weight: FontWeight.w600)),
          const SizedBox(height: 14),
          ...[
            ChoicePills(
              options: Choices.protocols,
              icons: protocolIcons,
              value: s.protocol,
              onChanged: (v) => c.updateSettings((x) => x.protocol = v),
            ),
            const SizedBox(height: 10),
            _Hint(Choices.protocolHints[s.protocol] ?? ''),
            if (s.usesTorExit) ...[
              const SizedBox(height: 20),
              TorExitPicker(controller: c),
            ],
            if (usesMasqueCarrier(s.protocol) || s.protocol == 'auto') ...[
              const SizedBox(height: 18),
              Text('Carrier', style: Ox.body(15, weight: FontWeight.w500)),
              const SizedBox(height: 10),
              Segmented(
                options: Choices.transports,
                value: s.transport,
                onChanged: (v) => c.updateSettings((x) => x.transport = v),
              ),
            ],
            if (!s.noTunnel) ...[
              const SizedBox(height: 18),
              Text('Scan', style: Ox.body(15, weight: FontWeight.w500)),
              const SizedBox(height: 10),
              ChoicePills(
                options: Choices.scans,
                value: s.scan,
                onChanged: (v) => c.updateSettings((x) => x.scan = v),
              ),
              const SizedBox(height: 10),
              _Hint(Choices.scanHints[s.scan] ?? ''),
            ],
          ],
        ],
      ),
    );

    final host = s.shareLan ? '0.0.0.0' : '127.0.0.1';
    final showHttp = s.httpProxy || (c.backend.supportsSystemProxy && s.systemProxy);
    final mode = OxTile(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text('Mode', style: Ox.headline(22, weight: FontWeight.w600)),
          ),
          const SizedBox(height: 6),
          if (c.backend.supportsVpn)
            SwitchRow(
              title: 'Whole-device VPN',
              subtitle: s.vpnMode ? 'Route every app through $kAppName' : 'Proxy only. Set an app to use the address below.',
              value: s.vpnMode,
              onChanged: (v) => c.updateSettings((x) => x.vpnMode = v),
            ),
          if (c.backend.supportsSystemProxy)
            SwitchRow(
              title: 'Windows system proxy',
              subtitle: 'Browsers and most apps will use the proxy while connected.',
              value: s.systemProxy,
              onChanged: (v) => c.updateSettings((x) => x.systemProxy = v),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text('Local proxy addresses', style: Ox.body(15, weight: FontWeight.w500, color: Ox.secondary)),
          ),
          const SizedBox(height: 4),
          _AddressRow(label: 'SOCKS5', address: '$host:${s.socksPort}'),
          if (showHttp) _AddressRow(label: 'HTTP', address: '$host:${s.httpPort}'),
          if (s.chain == 'tor' && !s.noTunnel) _AddressRow(label: 'Tor', address: '$host:${s.torPort}'),
          if (s.chain == 'psiphon' && !s.noTunnel && c.backend.supportsPsiphon)
            _AddressRow(label: 'Psiphon', address: '$host:${s.psiphonPort}'),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: route),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: mode),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [route, const SizedBox(height: 12), mode],
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Ox.medium,
      switchInCurve: Ox.easeOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, if (current != null) current],
      ),
      child: Text(text, key: ValueKey<String>(text), style: Ox.body(14, color: Ox.secondary)),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.label, required this.address});

  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 4, 2),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: Ox.body(15, color: Ox.secondary))),
          Expanded(child: SelectableText(address, maxLines: 1, style: Ox.code(15, weight: FontWeight.w500))),
          IconButton(
            tooltip: 'Copy $label address',
            icon: const Icon(Icons.copy_rounded, size: 18, color: Ox.blue),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: address));
              ScaffoldMessenger.maybeOf(context)
                  ?.showSnackBar(SnackBar(content: Text('$label address copied to clipboard.'), duration: const Duration(seconds: 2)));
            },
          ),
        ],
      ),
    );
  }
}
