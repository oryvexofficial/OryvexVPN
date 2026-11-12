import 'args.dart';
import 'settings.dart';

enum StepStatus { pending, active, done, retrying }

/// One stage of bringing a route up. [starts] and [finishes] are lowercase fragments of the
/// core's own log lines (see oryvexcore/src/lib.rs); a later stage seen in the log closes every
/// stage before it, so a missed line never leaves the progress stuck.
class ConnStep {
  ConnStep(this.id, this.title, {this.starts = const [], this.finishes = const [], this.idle = ''})
      : detail = idle;

  final String id;
  final String title;
  final List<String> starts;
  final List<String> finishes;
  final String idle;

  StepStatus status = StepStatus.pending;
  String detail;
}

/// The stages a connection goes through for the chosen protocol, fed from the core's log.
class ConnectionPlan {
  ConnectionPlan._(this.steps, this.socksPort);

  final List<ConnStep> steps;
  final int socksPort;

  static const _identity = [
    'loaded existing',
    'provisioned and saved',
    'identities ready',
    'masque key enrolled',
    'warp enabled for device',
    'loaded the gool wireguard identity',
    'selected protocol',
    'reusing the saved enrolment',
  ];

  static const _scanStarts = [
    'hunting for',
    'candidate ok',
    'wg endpoint',
    'verifying cached',
    'retrying last known-good',
    'scanning fresh',
    'obfuscation profile',
    'oryvexnoize',
  ];

  static const _scanDone = [
    'using cloudflare edge',
    'using forced peer',
    'still works; skipping scan',
    'the assigned endpoint',
    'best gateway',
  ];

  factory ConnectionPlan.of(CoreSettings s, {required bool android}) {
    final steps = <ConnStep>[];
    if (s.mitmOnly) {
      steps.add(ConnStep('start', 'Start the core',
          finishes: const ['starting the mitm engine'], idle: 'Launching'));
      steps.add(ConnStep('mitm', 'Prepare your certificate',
          starts: const ['starting the mitm engine'],
          finishes: const ['mitm certificate:'],
          idle: 'Loading the certificate made on this device'));
    } else if (s.bypassOnly) {
      steps.add(ConnStep('start', 'Start the core',
          finishes: const ['starting the bypass engine'], idle: 'Launching'));
      steps.add(ConnStep('bypass', 'Start the bypass engine',
          starts: const ['starting the bypass engine'],
          finishes: const ['bypass is ready'],
          idle: 'Reshaping the first packets of each connection'));
    } else if (s.torOnly) {
      steps.add(ConnStep('start', 'Start the core', finishes: const ['bootstrapping tor'], idle: 'Launching'));
      steps.add(ConnStep('tor', 'Bootstrap Tor',
          starts: const ['bootstrapping tor'], finishes: const ['tor is ready'], idle: 'Building a circuit'));
      steps.add(_exitStep(s));
    } else {
      final carrier = usesMasqueCarrier(s.protocol) ? Choices.transports[s.transport] ?? '' : '';
      steps.add(ConnStep('identity', 'Set up identity',
          starts: const ['provisioning', 'registering', 'enrolling'],
          finishes: _identity,
          idle: 'Loading your WARP identity…'));
      final (scanTitle, tunnelTitle, tunnelIdle) = switch (s.protocol) {
        'wg' => ('Find an endpoint', 'Verify the tunnel', 'Checking the WireGuard handshake and data'),
        'gool' => ('Find a gateway', 'WireGuard in MASQUE', 'Opening the inner WireGuard hop…'),
        'mim' => ('Find the outer gateway', 'Inner MASQUE hop', 'Opening the inner MASQUE hop…'),
        _ => ('Find a gateway', 'Open the tunnel', 'Connecting over $carrier…'),
      };
      steps.add(ConnStep('scan', scanTitle,
          starts: _scanStarts, finishes: _scanDone, idle: '${Choices.scans[s.scan]} scan…'));
      steps.add(ConnStep('tunnel', tunnelTitle,
          starts: const [
            'establishing',
            'validating wireguard',
            'masque transport',
            'edge assigned',
            'registering the gool',
            'rides inside the masque',
          ],
          finishes: const [
            'tunnel validated',
            'gool ready',
            'masque-in-masque ready',
            'inner masque tunnel established',
          ],
          idle: tunnelIdle));
    }
    steps.add(ConnStep('ready', 'Proxy ready', idle: 'SOCKS5 on port ${s.socksPort}'));
    if (s.noTunnel) {
      // Tor's exit step, if any, is already in the list above; Bypass has nothing more.
    } else if (s.chain == 'tor') {
      steps.add(ConnStep('tor', 'Tor via tunnel',
          starts: const ['bootstrapping tor'], finishes: const ['tor is ready'], idle: 'Port ${s.torPort}'));
      steps.add(_exitStep(s));
    } else if (s.chain == 'psiphon' && !android) {
      steps.add(ConnStep('psiphon', 'Psiphon via tunnel',
          starts: const ['psiphon will be carried'], finishes: const ['psiphon is ready'], idle: 'Port ${s.psiphonPort}'));
    }
    if (android && s.vpnMode) {
      steps.add(ConnStep('vpn', 'Device VPN', idle: 'Routing every app'));
    }
    return ConnectionPlan._(steps, s.socksPort);
  }

  /// Where Tor leaves: measured, a country tried, or Tor's own pick. Every core path ends in one
  /// "tor exit: using" line (see oryvexcore/src/tor.rs, choose_exit).
  static ConnStep _exitStep(CoreSettings s) {
    final idle = switch (s.torExit) {
      'auto' => 'Letting Tor choose an exit…',
      'fastest' => 'Finding the fastest exit…',
      _ => 'Using exit in ${s.torExit.toUpperCase()}',
    };
    return ConnStep('exit', 'Tor exit',
        starts: const ['tor exit: measuring', 'tor exit: trying'], finishes: const ['tor exit: using'], idle: idle);
  }

  static final _exitUsing = RegExp(r'tor exit: using (auto|[a-z]{2})\b(?:.*?(\d+) ms)?', caseSensitive: false);
  static final _exitTrying = RegExp(r'tor exit: trying ([a-z]{2})', caseSensitive: false);

  int get _readyIndex => steps.indexWhere((x) => x.id == 'ready');

  bool get ready => steps[_readyIndex].status == StepStatus.done;

  /// 0..1, for the progress bar.
  double get progress {
    var p = 0.0;
    for (final x in steps) {
      if (x.status == StepStatus.done) {
        p += 1;
      } else if (x.status == StepStatus.active || x.status == StepStatus.retrying) {
        p += 0.45;
      }
    }
    return steps.isEmpty ? 0 : p / steps.length;
  }

  ConnStep? get current {
    for (final x in steps) {
      if (x.status != StepStatus.done) return x;
    }
    return null;
  }

  void begin() {
    for (final x in steps) {
      x.status = StepStatus.pending;
      x.detail = x.idle;
    }
    steps.first.status = StepStatus.active;
  }

  void _activate(int i, {String? detail}) {
    for (var k = 0; k < i; k++) {
      if (steps[k].status != StepStatus.done) {
        steps[k].status = StepStatus.done;
      }
    }
    if (steps[i].status != StepStatus.done) {
      steps[i].status = StepStatus.active;
      if (detail != null) steps[i].detail = detail;
    }
  }

  void _finish(int i, {String? detail}) {
    _activate(i);
    steps[i].status = StepStatus.done;
    if (detail != null) steps[i].detail = detail;
    if (i + 1 < steps.length && steps[i + 1].status == StepStatus.pending) {
      steps[i + 1].status = StepStatus.active;
    }
  }

  /// The socks5 listener the user dials has come up: "[+] socks5 server listening on 127.0.0.1:1819".
  /// The port check skips the throwaway listener gool opens while it registers.
  bool isReadyLine(String m) {
    final l = m.toLowerCase();
    return (l.contains('listening on') || l.contains('is ready')) &&
        !l.contains('http proxy') &&
        (m.trimRight().endsWith(':$socksPort') || l.contains('bypass is ready') || l.contains('mitm is ready'));
  }

  static final _rtt = RegExp(r'(?:candidate ok|wg endpoint|best gateway)\s+(\S+)\s+rtt=([0-9.]+\w*)');
  static final _edge = RegExp(r'(?:using cloudflare edge|using forced peer|cached gateway)\s+(\S+)');

  /// Feeds one log message. Returns true when anything changed.
  bool ingest(String message) {
    final m = message.toLowerCase();

    if (m.contains('reconnecting') || m.contains('rescanning')) {
      final scan = steps.indexWhere((x) => x.id == 'scan' || x.id == 'tor');
      if (scan >= 0) {
        for (var k = scan; k < steps.length; k++) {
          steps[k].status = StepStatus.pending;
          steps[k].detail = steps[k].idle;
        }
        steps[scan].status = StepStatus.retrying;
        steps[scan].detail = m.contains('no usable') || m.contains('no remembered')
            ? 'No gateway responded yet. Retrying…'
            : 'The tunnel dropped. Searching for a new route…';
        return true;
      }
    }

    final ready = _readyIndex;
    if (isReadyLine(message)) {
      _finish(ready, detail: steps[ready].idle);
      return true;
    }

    for (var i = steps.length - 1; i >= 0; i--) {
      final x = steps[i];
      if (i == ready) continue;
      if (x.finishes.any(m.contains)) {
        String? detail;
        final e = _edge.firstMatch(message);
        if (x.id == 'scan' && e != null) detail = e.group(1);
        if (x.id == 'tor' || x.id == 'psiphon') detail = 'Ready';
        if (x.id == 'bypass') detail = 'Ready';
        if (x.id == 'mitm') detail = 'Ready';
        if (x.id == 'exit') {
          final u = _exitUsing.firstMatch(message);
          if (u != null) {
            final code = u.group(1)!.toLowerCase();
            final ms = u.group(2);
            detail = code == 'auto' ? 'Tor\'s own pick' : '${code.toUpperCase()}${ms == null ? '' : ' · $ms ms'}';
          }
        }
        _finish(i, detail: detail);
        return true;
      }
      if (x.starts.any(m.contains)) {
        String? detail;
        final r = _rtt.firstMatch(message);
        if (r != null) detail = '${r.group(1)} · ${r.group(2)}';
        final t = _exitTrying.firstMatch(message);
        if (x.id == 'exit' && t != null) detail = 'Trying ${t.group(1)!.toUpperCase()}';
        if (m.contains('registering') || m.contains('provisioning') || m.contains('enrolling')) {
          detail = 'Registering a new identity';
        }
        if (m.contains('verifying cached') || m.contains('retrying last known-good')) {
          detail = 'Trying the last gateway that worked';
        }
        _activate(i, detail: detail);
        return true;
      }
    }
    return false;
  }

  void vpn(bool up) {
    final i = steps.indexWhere((x) => x.id == 'vpn');
    if (i < 0) return;
    if (up) {
      steps[i].status = StepStatus.done;
      steps[i].detail = 'Every app is protected';
    } else if (steps[i].status == StepStatus.done) {
      steps[i].status = StepStatus.pending;
      steps[i].detail = steps[i].idle;
    }
  }

  /// Marks every stage done, for routes whose readiness the app learns itself.
  void completeAll({String? readyDetail}) {
    for (final x in steps) {
      x.status = StepStatus.done;
    }
    final i = _readyIndex;
    if (i >= 0 && readyDetail != null) steps[i].detail = readyDetail;
  }

  void reset() {
    for (final x in steps) {
      x.status = StepStatus.pending;
      x.detail = x.idle;
    }
  }
}
