/// The app's name, version and release source, in one place.
///
/// `.github/workflows/auto-release.yml` rewrites [kAppVersion] when it tags a release, so the
/// version the app shows (and compares in Updates) always matches the tag it was built from.
const kAppName = 'OryvexVPN';
const kAppVersion = '1.1.23';
const kCreator = 'Muvixo';

/// GitHub repo that publishes releases, as "owner/name". `tools/set-repo.sh` rewrites it.
const kReleasesRepo = 'oryvexofficial/OryvexVPN';
