# OryvexVPN Fox relay

This Worker carries Fox control-plane requests for users who choose to run their own relay. It is **not** a general-purpose VPN or open proxy. The only upstream host suffixes accepted are `mozilla.org`, `mozilla.com`, `firefox.com`, `github.com`, `githubusercontent.com`, and `jsdelivr.net`.

## Deploy from OryvexVPN

Open **Settings → Fox connection → Deploy Cloudflare relay** in OryvexVPN. The app requests a scoped Cloudflare API token, uploads this Worker, sets a random `SECRET` binding, enables its `workers.dev` route, and saves the relay URL in Fox's local configuration. The Cloudflare token is used in memory for that deployment and is not saved by OryvexVPN. The generated relay secret is stored only in your local Fox config and Cloudflare's Worker secret binding.

Cloudflare token creation happens on Cloudflare's dashboard. The **Token template** button opens an Android system Custom Tab or the system browser on Windows. Restrict the template from all accounts to the account you intend to use; verify Account Settings Read and Workers Scripts Edit are selected, then paste the token into the app. The Firefox browser sign-in page itself connects directly, not through the Worker. Cloudflare may require Workers Admin for first-time Worker creation; if so, use the narrower template first and only grant the additional permission if Cloudflare explicitly refuses deployment.

## Deploy manually

```sh
npx wrangler deploy --config wrangler.toml
npx wrangler secret put SECRET --config wrangler.toml
```

Then set the Fox `network.api_relay` value to the Worker HTTPS URL with `?secret=<your-secret>`, and set `network.api_relay_enabled` to `true`.

## Data and security notes

- The relay forwards Fox API requests, including Firefox Account sign-in and access-token requests. Only deploy it to an account you control.
- OryvexVPN does not receive your Cloudflare API token. The relay operator (you) can see requests sent through their Worker.
- VPN tunnel traffic and unrelated browsing do not pass through this relay.
- The Worker rejects non-HTTPS destinations, non-allowlisted hosts, nonstandard ports, unsupported methods, and oversized bodies. It returns upstream redirects without following them; each later request through the Worker is independently checked against the allowlist. It does not enable browser CORS.
- The status page is public and contains no secret. The health endpoint and proxy requests require the secret.
- The Worker source bundled with the Flutter app is checked against this repository copy by `tools/tests/test_cloudflare_worker.mjs`.
