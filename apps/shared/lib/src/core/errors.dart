/// Turns the core's raw failure text into one sentence a person can act on.
String friendlyError(String raw) {
  var msg = raw.trim();

  // `Error: Other("...")`, the shape Rust prints when main returns an error.
  final wrapped = RegExp(r'^Error:\s*\w+\("(.*)"\)\s*$', dotAll: true).firstMatch(msg);
  if (wrapped != null) {
    msg = wrapped.group(1)!.replaceAll(r'\"', '"').replaceAll(r'\n', ' ');
  } else if (msg.startsWith('Error: ')) {
    msg = msg.substring(7);
  }
  msg = msg.replaceFirst(RegExp(r'^\[[-!*+=]\]\s*'), '');
  final lower = msg.toLowerCase();

  final port = RegExp(r'cannot use \S*?:(\d+)').firstMatch(msg)?.group(1);
  if (lower.contains('already listens there') ||
      lower.contains('address already in use') ||
      lower.contains('os error 10048') ||
      lower.contains('os error 98')) {
    return port != null
        ? 'Port $port is in use by another app. Close it or choose a different port in Settings.'
        : 'A local port is already in use. Close the other app or choose a different port in Settings.';
  }
  if (lower.contains('excludedportrange') || (lower.contains('permission denied') && port != null)) {
    return 'Windows has reserved port $port. Choose a different port in Settings.';
  }
  if (lower.contains('no tor support')) {
    return 'This version does not include Tor support. Turn off Tor in Settings.';
  }
  if (lower.contains('unknown option')) {
    final opt = RegExp(r"unknown option '([^']+)'").firstMatch(msg)?.group(1);
    return 'The core does not recognize ${opt ?? 'that option'}. Check Extra core arguments in Settings.';
  }
  if (lower.contains('requires a value')) {
    return 'An entry in Extra core arguments is missing a value.';
  }
  if (lower.contains('identity refused')) {
    return 'Cloudflare rejected the saved identity. Connect again to register a new one.';
  }
  if (lower.contains('no clean endpoint') || lower.contains('scan deadline')) {
    return 'No gateway responded. Try another protocol, choose Thorough scan, or use HTTP/2.';
  }
  // Keep the first sentence only; the full text stays in Activity.
  final cut = msg.indexOf('\n');
  if (cut > 0) msg = msg.substring(0, cut);
  if (msg.length > 220) msg = '${msg.substring(0, 217)}...';
  if (msg.isNotEmpty) {
    msg = msg[0].toUpperCase() + msg.substring(1);
  }
  return msg.isEmpty ? 'Something went wrong. Check Activity for details.' : msg;
}
