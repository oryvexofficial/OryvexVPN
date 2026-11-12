from __future__ import annotations

import unittest
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
SITE = ROOT / "site"


class PageLinks(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if values.get("id"):
            self.ids.add(values["id"])
        if tag == "a":
            self.links.append(values.get("href", ""))
        elif tag in {"img", "script", "link"}:
            self.links.append(values.get("src") or values.get("href") or "")


class SiteTests(unittest.TestCase):
    def test_homepage_links_and_assets(self):
        page = SITE / "index.html"
        parser = PageLinks()
        parser.feed(page.read_text(encoding="utf-8"))
        for link in parser.links:
            if not link:
                continue
            if link.startswith("#"):
                self.assertIn(link[1:], parser.ids, link)
                continue
            parts = urlsplit(link)
            if parts.scheme or parts.netloc:
                continue
            path = parts.path
            if path in ("", ".", "./"):
                path = "index.html"
            self.assertTrue((SITE / path).is_file(), link)

    def test_homepage_has_fox_and_supported_downloads(self):
        text = (SITE / "index.html").read_text(encoding="utf-8")
        for phrase in ("Fox", "unofficial client", "Windows", "Android", "ARM64", "ARMv7"):
            self.assertIn(phrase, text)
        self.assertNotIn("assets/shots", text)


if __name__ == "__main__":
    unittest.main()
