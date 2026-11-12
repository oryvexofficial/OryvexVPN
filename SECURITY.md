# Security

Do not commit Cloudflare secrets, account credentials, app bearer tokens, or local environment files. Report security issues privately to the repository owner before opening a public issue.

The Worker stores native app session token hashes in D1, requires a strong `STREAM_SIGN_SECRET` and `EDGE_TOKEN`, and limits Check host to VexoStream-owned or explicitly authorized targets. Keep those controls enabled and rotate any credential that has been exposed.
