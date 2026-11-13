# Flags

Downloaded from the internet: hampusborgos/country-flags (SVGs taken from
Wikimedia Commons, public domain). Byte-for-byte copies, checksums verified
against GitHub.

| File | Country |
|---|---|
| ir.svg | Iran (official emblem + 22 takbir) |
| us.svg | United States |
| de.svg | Germany |
| gb.svg | United Kingdom |
| fr.svg | France |
| nl.svg | Netherlands |

Served at `/assets/flags/<cc>.svg`. Re-download any time with `npm run flags`.
To add a country: drop `<cc>.svg` here and add it to `CH_COUNTRIES` in `src/05d-checkhost.ts`.
