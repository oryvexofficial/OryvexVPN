from __future__ import annotations

import unittest
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit


ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / "site"
PAGE_ROUTES = {"about", "app", "creator", "docs", "download", "guide", "tor"}


class SiteLinks(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "a":
            self.links.append(values.get("data-href") or values.get("href") or "")
        elif tag in {"img", "script", "link"}:
            self.links.append(values.get("src") or values.get("href") or "")


class StaticRouteTests(unittest.TestCase):
    def test_every_local_site_link_resolves_to_a_file_or_404_route(self) -> None:
        missing: list[str] = []
        for page in sorted(SITE.glob("*.html")):
            parser = SiteLinks()
            parser.feed(page.read_text(encoding="utf-8"))
            for raw in parser.links:
                if not raw or raw.startswith(("#", "//")):
                    continue
                parts = urlsplit(raw)
                if parts.scheme or parts.netloc:
                    continue
                path = parts.path
                if path.startswith("/"):
                    path = path.lstrip("/")
                if path in {"", "."} or path.endswith("/"):
                    path = path + "index.html"
                target = (SITE / page.parent.relative_to(SITE) / path).resolve()
                if target.is_file():
                    continue
                route = Path(path).name
                if (
                    path == route
                    and not Path(route).suffix
                    and route in PAGE_ROUTES
                    and (SITE / f"{route}.html").is_file()
                ):
                    continue
                missing.append(f"{page.relative_to(ROOT)} -> {raw}")

        self.assertEqual(missing, [], "\n".join(missing))

    def test_404_resolves_extensionless_routes_under_the_detected_base_path(self) -> None:
        fallback = (SITE / "404.html").read_text(encoding="utf-8")
        script = (ROOT / "tools" / "build-site.py").read_text(encoding="utf-8")
        route_map = "routePages={about:1,app:1,creator:1,docs:1,download:1,guide:1,tor:1}"
        route_rewrite = "location.replace(r+slug+'.html'+location.search+location.hash)"

        self.assertIn(route_map, fallback)
        self.assertIn(route_rewrite, fallback)
        self.assertIn("location.pathname.slice(r.length)", fallback)
        self.assertIn(route_map, script)
        self.assertIn(route_rewrite, script)
        self.assertIn("location.pathname.slice(r.length)", script)

    def test_html_pages_remain_canonical_and_generator_keeps_real_filenames(self) -> None:
        app = (SITE / "app.js").read_text(encoding="utf-8")
        generator = (ROOT / "tools" / "build-site.py").read_text(encoding="utf-8")
        self.assertNotIn("location.pathname.replace(/(index)?\\.html$/", app)
        self.assertIn("return html", generator)

    def test_release_docs_match_published_ghcr_image_and_openwrt_path(self) -> None:
        image = "ghcr.io/oryvexofficial/oryvexvpn:latest"
        for relative in ("README.md", "docs/GUIDE.md", "site/docs.html", "tools/build-site.py"):
            self.assertIn(image, (ROOT / relative).read_text(encoding="utf-8"), relative)

        openwrt = (ROOT / "docs" / "OPENWRT.md").read_text(encoding="utf-8")
        self.assertIn("cd OryvexVPN/oryvexcore", openwrt)
        self.assertNotIn("cd OryvexCore/oryvexcore", openwrt)


if __name__ == "__main__":
    unittest.main()
