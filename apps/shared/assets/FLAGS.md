# Country flags

One PNG per ISO 3166-1 alpha-2 code (lowercase, `de.png`), 128 x 96, transparent, used by the
Tor exit picker and the route card. They are the flag artwork of Google's Noto Emoji project
(https://github.com/googlefonts/noto-emoji, flags from its `third_party/region-flags`, public
domain; the font itself is SIL OFL 1.1), rendered out of Noto Color Emoji and quantised.

Windows does not draw flag emoji, so the app ships pictures instead of relying on the font.
A code without a file falls back to a two-letter badge.
