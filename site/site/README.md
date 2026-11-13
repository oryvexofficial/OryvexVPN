# VexoStream site and Cloudflare Worker

This directory contains the VexoStream site Worker source and the app-facing API. A tested compiled bundle is included at `dist/worker.js`, so `npx wrangler deploy` can be run directly from this `site/` folder.

## Manual deploy from Windows CMD

From the extracted repository, use the `site` folder, not the old v22.2 project folder:

```bat
cd /d C:\Users\CynetAdmin\Downloads\repo\site
npx wrangler login
npx wrangler deploy
```

Replace `repo` in the path with the folder name you used when extracting the ZIP. If you are already in the `site` directory, just run `npx wrangler login` once and then `npx wrangler deploy`.

If you edit Worker source files, rebuild before deploying:

```bat
npm install
npm run build
npx wrangler deploy
```

`npx wrangler deploy` does not run the build script on its own. If `dist/worker.js` is missing, `npm run build` regenerates it. The Worker deployment is manual; GitHub Actions only tests and builds the Flutter Windows app.

## App API database migration

Before first use of the Flutter app, apply both idempotent API session migrations to the remote `DB` database from this same folder. They store only hashed revocable tokens for member and owner/admin app sessions:

```bat
npx wrangler d1 execute DB --file=./migrations/2026-11-11-api-sessions.sql --remote
npx wrangler d1 execute DB --file=./migrations/2026-11-12-admin-api-sessions.sql --remote
```

The Worker creates both session tables lazily, but applying the migrations explicitly is cleaner.

## Required setup

Confirm that `wrangler.toml` points at the Cloudflare zone and D1 database IDs you intend to use. In Cloudflare, configure `STREAM_SIGN_SECRET`, `EDGE_TOKEN`, and `APP_KEY` as Worker secrets, and set `RAILWAY_URL` or `BACKEND_URL` to your public VexoStream Core backend. The site is deployed manually with Wrangler. For a release artifact from GitHub Actions, use the repository secret `APP_KEY`, or build locally with `--dart-define=APP_KEY=...`. Never commit any of these values. The app key is embedded in the desktop binary, so it is a client gate, not a secret from a determined user.

The Worker serves `vexostream.bond/*`, `www.vexostream.bond/*`, and `api.vexostream.bond/*` through Cloudflare zone routes. The API uses a Worker Route, not a Custom Domain. Routes require an existing proxied DNS record for `api` in the `vexostream.bond` zone; Wrangler does not create that DNS record or a separate certificate. The API hostname returns plain 404s for `/` and website paths. `/api/v1` and image requests require `X-App-Key`; signed media URLs expire after 24 hours. Browser playback remains IP-bound; the native app uses target-bound signatures because Dart HTTP and mpv may use different IPv4/IPv6 paths. The app login accepts member and Owner credentials. The app Owner dashboard covers the site Admin sections for providers, backend, members, team, social, Telegram, live viewers, operations, and password management. App model filters are translated into the Core API’s `Female`, `Female,Male`, and `Male` values.

The watch-page Embed dialog keeps the iframe and Web component options for VexoStream’s own player, and now also shows, previews, and copies the VexoStream `/embed/` link for supported provider video-page formats. Supported source domains are Pornhub, XVideos, XNXX, YouPorn, and RedTube. The link always points to `https://vexostream.bond/embed/{base64url(video-page-url)}`; it never uses an embed URL or destination host supplied by catalog data, and it does not call a provider embed API. Provider extraction, regional access, and video availability still apply to the VexoStream player.

Windows app playback runs in a WebView of VexoStream’s own `/embed/` player. It authenticates without copying the app bearer token into the browser: an authenticated app session requests `POST /api/v1/embed/grant`; the Worker returns a five-minute HMAC grant bound to that video URL. The `/embed/` page and stream extraction validate the grant against the same URL. Expired, mismatched, hidden, or locked sources do not get the login bypass.

Player posters on `/video/` and `/embed/` use the same-origin image proxy and can resolve thumbnails from several common metadata aliases. Catalog cards show a valid listing thumbnail immediately, then upgrade to the resolved page poster when available; failed images leave a branded placeholder instead of removing the card. The image proxy sends a provider-matching `Referer` and retries once without `Origin` for CDNs that reject it.
