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

The Worker serves `vexostream.bond/*`, `www.vexostream.bond/*`, and `api.vexostream.bond/*` through Cloudflare zone routes. The API uses a Worker Route, not a Custom Domain. Routes require an existing proxied DNS record for `api` in the `vexostream.bond` zone; Wrangler does not create that DNS record or a separate certificate. The API hostname returns plain 404s for `/` and website paths. `/api/v1` and image requests require `X-App-Key`; signed media proxy URLs use short-lived IP-bound signatures for native HLS playback. The app login accepts member and Owner credentials; Owner accounts get the app Admin dashboard.
