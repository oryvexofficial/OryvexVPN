# Bundled fonts

These are the fonts the VexoStream site uses, bundled so the app never downloads fonts at runtime.

- Geist (Regular, Medium, SemiBold, Bold): site UI font. Static instances of the Google Fonts variable font. SIL Open Font License 1.1, Vercel.
- Geist Mono (Regular, Medium, SemiBold): site monospace font. SIL Open Font License 1.1, Vercel.
- Vazirmatn (Regular, Medium, SemiBold, Bold): Persian/Arabic font the site loads for RTL languages. SIL Open Font License 1.1, Saber Rastikerdar.
- Noto Sans Arabic (Regular, Bold): copied from `site/assets/fonts`, the site's own Arabic fallback. See `NOTO-LICENSE.txt`.

Text uses Geist first, then Vazirmatn, then Noto Sans Arabic, so Persian text renders in Vazirmatn like on the site.
