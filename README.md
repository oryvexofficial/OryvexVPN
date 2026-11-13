# VexoStream

Flutter Windows and Android app (`apps/flutterapp/`) plus the Cloudflare Worker site and API (`site/`).

- The app bundles the site's fonts in `apps/flutterapp/assets/fonts`: Geist and Geist Mono (site UI), Vazirmatn (Persian), and Noto Sans Arabic (the site's own Arabic fallback). Nothing is downloaded at runtime.
- Quality picker shows main qualities only. Fallback sources stay hidden and are used automatically if a main source fails.
- Android setup applies the `VexoStream` app name and density/adaptive launcher icons generated from the same source as the Windows desktop icon.
- GitHub Actions (`.github/workflows/build.yml`) tests the website and app, builds the Windows installer/portable ZIP and universal Android APK, and publishes version-tagged GitHub Releases.

## Original project documentation

# VexoStream

One repository for the existing VexoStream site, its Cloudflare Worker API, and a Flutter client for Windows and Android.

```text
.
├── site/                   Existing site + Cloudflare Worker source
│   ├── src/                Pages, routing, account logic, API v1
│   ├── assets/             Brand and provider assets
│   ├── migrations/         Idempotent D1 migrations
│   ├── scripts/            Worker build and tests
│   └── wrangler.toml       Cloudflare routes and D1 bindings
├── apps/
│   └── flutterapp/          Flutter Windows and Android app source
├── .github/workflows/      GitHub Actions tests, builds and releases the app
├── README.md
└── SECURITY.md
```

## What is included

### Site

The supplied VexoStream Tailwind v25 Worker source is under `site/`, including its original pages, provider settings, member sign-in, admin panel, status, social page, developers page, Check host, and media proxy. The site and app API are built together into one Cloudflare Worker.

### Windows app

`apps/flutterapp/` contains the Flutter client and all app code. It includes an 18+ first-run confirmation, Home, Browse/Search, performer directory and profiles, VexoStream embedded video playback with quality selection, “More like this,” the player shortcut reference, share/embed snippets, device-local Continue Watching with resume, account sign-in/sign-up, Status, Social, Developers/embed, and Check host pages. Bearer tokens are stored securely on supported platforms; account sessions can be revoked by signing out.

GitHub Actions tests the site and Flutter source, builds Windows and Android, and packages the NSIS installer. It uploads the installer separately and in a bundle with the portable Windows ZIP. When `APP_KEY` is missing, artifacts are explicitly marked validation-only because protected API calls will not work. Site Owner and delegated Admin credentials work in the app login form. Both bypass maintenance while signed in, and the Admin dashboard exposes only the controls their server-side permissions allow. Live viewer settings remain Owner-only.

The app Check Host page shows regional probes and the Cloudflare edge separately, including progress, errors and response details. It uses the same authorized-host and port restrictions as the website. Windows uses Edge WebView2; Android uses Android System WebView, whose native error pages can differ. The app uses the allowlisted first-party VexoStream embedded player as its only playback surface.

### API

Base URL: `https://api.vexostream.bond/api/v1`

| Method | Endpoint | Purpose |
| --- | --- | --- |
| GET | `/health` | Worker/API health |
| GET | `/config` or `/providers` | Provider list, default provider, account policy |
| GET | `/catalog?provider=xvideos&q=trending&page=1` | Browse/search catalog |
| GET | `/search?q=...&provider=...&page=1` | Search alias |
| GET | `/models?gender=women&search=...&page=1` | Performer directory |
| GET | `/models/{slug}` | Performer profile |
| GET | `/image?url=...` | Proxied thumbnails, posters, and performer photos |
| GET | `/posters?u=...` | Real video posters (og:image), up to 24 per call |
| GET | `/status` | System and provider status |
| GET | `/social` | Public social links and bots |
| GET | `/developers` | Embed snippet and endpoint reference |
| GET | `/check-host/nodes` | Available diagnostic nodes |
| GET | `/check-host/start?host=...&type=http` | Start an authorized host check |
| GET | `/check-host/result?id=...&type=http` | Poll a host check |
| POST | `/auth/signup` | Create account, requires `username`, `password`, `passwordConfirm`, and `adult: true` |
| POST | `/auth/login` | Create a member bearer session |
| POST | `/auth/logout` | Revoke the current bearer session |
| GET | `/account` | Read the signed-in account |
| POST | `/embed/grant` | Create a five-minute, video-bound grant for the signed-in app’s WebView |
| POST | `/videos/extract` | Resolve a supported video URL into Worker-proxied streams |

Successful signup/login returns a 30-day bearer token. Send it as `Authorization: Bearer <token>` for protected endpoints. Only a SHA-256 hash is stored in D1. Passwords reuse the site's PBKDF2-SHA256 account handling. `EDGE_TOKEN` is never sent to the app.

The API uses the existing site's policies: provider locks/hidden states are enforced, performer access follows the member setting, and stream extraction follows the login-to-watch setting. Check host is intentionally limited to VexoStream-owned hosts and explicitly authorized targets. It is not an unrestricted scanner.

## Important backend dependency

The provided site already forwards catalog, model, poster, and stream-extraction requests to VexoStream Core using the Worker `RAILWAY_URL`/`BACKEND_URL` setting and `EDGE_TOKEN`. This repository adds the complete app-facing Worker API and Flutter client, but it does **not** contain that separate Core extraction/catalog service. Keep the existing Core service available and configure the Worker to reach it; otherwise the app shell, accounts, status, and social pages work, but browsing and playback will not return catalogue results.

## Push to GitHub

1. Create an empty GitHub repository.
2. Unzip this repository locally.
3. Initialize Git, commit, and push the root contents. Example:

   ```bash
   git init
   git add .
   git commit -m "Add VexoStream site, API, and Windows app"
   git branch -M main
   git remote add origin https://github.com/OWNER/REPOSITORY.git
   git push -u origin main
   ```

4. Configure the optional repository secret `APP_KEY` to build API-ready artifacts. After a successful push to `main` or `master`, GitHub Actions automatically creates the `v<version>` tag from `apps/flutterapp/pubspec.yaml`, creates a GitHub Release, and uploads the Windows installer, portable ZIP, and universal Android APK if that version has not already been released. Later pushes without a version bump still run CI but skip publishing, so existing releases are never overwritten. Bump the app version for each new release; pull requests do not publish releases. You can also push a matching version tag manually. Without `APP_KEY`, artifacts are labeled validation-only and the Release is a pre-release.

The repo is arranged so GitHub sees `site/`, `apps/`, `.github/`, and this README at the root. It does not contain a `.git` directory or your GitHub credentials.

## Configure Cloudflare before deployment

The `site/wrangler.toml` carries forward the zone and D1 IDs from the supplied archive. Confirm they belong to the Cloudflare account you intend to deploy to; replace the D1 IDs if you created different databases. Ensure the zone `vexostream.bond` is active in that account.

Set Worker secrets in Cloudflare before deploying:

- `STREAM_SIGN_SECRET`: a long, random secret used for signed sessions and media URLs.
- `EDGE_TOKEN`: a separate long, random token shared with the configured VexoStream Core backend.
- `APP_KEY`: a random app-access key. The Worker requires it in `X-App-Key` for every `/api/v1` request. Stream proxy URLs use their own short-lived signatures.
- `TELEGRAM_BOT_TOKEN`: optional, only if the Telegram bot is enabled.
- `ADMIN_USERS`: optional legacy bootstrap admins, if used.

Set `APP_KEY` only as a Cloudflare Worker secret with `npx wrangler secret put APP_KEY` from `site/`. Site deployment remains manual; GitHub Actions never deploys the Worker. To build API-ready app artifacts, add the same value as the repository **secret** `APP_KEY`. The key is embedded in client binaries and can be extracted, so it is not a durable secret. Without the Actions secret, builds are marked validation-only and their releases are pre-releases excluded from stable update checks. Alternatively, pass `--dart-define=APP_KEY=<same-value>` to a local Flutter build.

Set the Worker `RAILWAY_URL` (or `BACKEND_URL`) to the public HTTPS origin for the VexoStream Core service. Do not put `EDGE_TOKEN` in Flutter or in the repository. If using the admin panel's backend override, that saved value takes precedence over the Worker variable.

The Worker serves these Cloudflare zone routes:

- `vexostream.bond/*`
- `www.vexostream.bond/*`
- `api.vexostream.bond/*` for the API and media proxy

The API uses a Worker **Route**, not a Custom Domain. Keep an existing proxied DNS record for `api` in the `vexostream.bond` zone; unlike a Custom Domain, a Route does not create DNS records or issue a separate certificate. `https://api.vexostream.bond/` and non-API website paths return plain 404s. `/api/v1` and image requests require `X-App-Key`; media proxy URLs are short-lived and target-bound for the native app because Dart HTTP and mpv can use different IPv4/IPv6 paths; website browser streams retain IP-bound signatures. The Windows app tries `https://vexostream.bond/api/v1` first, then `https://api.vexostream.bond/api/v1`. Both route to the same Worker; the site hostname is preferred because it is the main proxied zone host. Use `--dart-define=VEXOSTREAM_API_BASE=...` only if you need another API origin.

## Deploy site and API manually from Windows CMD

The site is deployed from your own terminal with Wrangler. The repository includes the compiled `site/dist/worker.js`, so a first deploy does not fail on the missing entrypoint.

1. Extract the ZIP and open Command Prompt.
2. Enter the `site` subfolder. Example:

   ```bat
   cd /d C:\Users\CynetAdmin\Downloads\repo\site
   ```

   Replace `repo` with the name of the folder you extracted. Don’t deploy from the older `VexoStream-CheckHost-v22.2` directory if you want the new API and Windows app changes.

3. Authenticate Wrangler once and deploy:

   ```bat
   npx wrangler login
   npx wrangler deploy
   ```

4. Before first app use, apply the idempotent D1 API-session migration from `site/`:

   ```bat
   npx wrangler d1 execute DB --file=./migrations/2026-11-11-api-sessions.sql --remote
   npx wrangler d1 execute DB --file=./migrations/2026-11-12-admin-api-sessions.sql --remote
   ```

   You can apply both before deploy. The Worker creates both tables lazily if needed.

For any future source changes, rebuild then deploy:

```bat
npm install
npm run build
npx wrangler deploy
```

Wrangler does not run the source build automatically. `npx wrangler deploy` works from the supplied ZIP because `dist/worker.js` is included; `npm run build` regenerates it after source edits. GitHub Actions builds and tests the Worker, but does not deploy it. Version tags publish the installer, portable ZIP, and universal Android APK; missing `APP_KEY` is called out as validation-only.

`site/wrangler.toml` carries forward the zone and D1 IDs from the supplied archive. Confirm they belong to your Cloudflare account and replace them if you created different databases. Ensure `api.vexostream.bond` has a proxied DNS record in that zone for the Worker Route. Set `STREAM_SIGN_SECRET`, `EDGE_TOKEN`, and `APP_KEY` as Worker secrets, and configure `RAILWAY_URL`/`BACKEND_URL` to the separate VexoStream Core service. Authenticate with Wrangler locally, or use a Cloudflare API token in your terminal environment. Don’t commit credentials.

## Local source checks

The GitHub Actions workflow tests the site and app, generates missing platform runners, builds the Windows app and Android universal APK, and compiles the NSIS installer. Add `APP_KEY` as a repository secret for an API-ready build; otherwise artifacts are validation-only. For local source checks, run:

```bash
cd site
npm install
npm test

cd ../apps
flutter pub get
flutter test
```

Use the GitHub Actions artifact for the Windows release build.

## App design

The app uses the site's v25 dark "night-screening room" tokens (ink surfaces, signal blue `#378EFF`, pill controls, 18px rounded surfaces, hairline rings), the Geist and Geist Mono fonts, the VexoStream logo and mark, and the same layout ideas: top bar with search, sidebar/drawer navigation, the "Paste a link. Press play." hero, video cards, Continue Watching, player recommendations and shortcuts, and site-style empty/error states. The Windows build workflow sets the VexoStream icon, window title, and `VexoStream.exe` name. A newer stable GitHub Release blocks app use until the platform-specific update is opened; failed checks are shown as unverified and can be retried.
