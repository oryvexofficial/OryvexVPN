import 'https_client.dart';
import 'update_service.dart';
import 'version.dart';

export 'version.dart' show kReleasesRepo;

class UpdateInfo {
  const UpdateInfo({required this.currentVersion, required this.latestVersion, required this.releaseUrl, required this.updateAvailable});
  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;
  final bool updateAvailable;
}

/// Checks the latest GitHub release (through the core's SOCKS5 port when [socksPort] is given).
/// Returns null when the check fails.
Future<UpdateInfo?> checkForUpdate(String currentVersion, {int? socksPort}) async {
  try {
    final reply = await HttpsGet.fetch('api.github.com', '/repos/$kReleasesRepo/releases/latest',
        socksPort: socksPort,
        headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'OryvexVPN-update-check'});
    if (!reply.ok) return null;
    final r = ReleaseInfo.fromGitHub(reply.body);
    if (r == null) return null;
    return UpdateInfo(currentVersion: currentVersion, latestVersion: r.version, releaseUrl: r.pageUrl,
        updateAvailable: isNewerVersion(r.version, currentVersion));
  } on Object {
    return null;
  }
}
