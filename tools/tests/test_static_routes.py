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
        for phrase in ("Fox", "unofficial client", "Windows", "Android"):
            self.assertIn(phrase, text)
        downloads = (SITE / "downloads.html").read_text(encoding="utf-8")
        for phrase in ("ARM64", "ARMv7", "x86", "Windows", "Android"):
            self.assertIn(phrase, downloads)
        self.assertNotIn("assets/shots", text)
        self.assertIn('class="mobile-nav"', text)
        self.assertIn('id="relay"', text)
        self.assertIn('static preview is not live availability data', text.lower())

    def test_all_pages_have_valid_local_links(self):
        pages = list(SITE.glob('*.html'))
        self.assertGreaterEqual(len(pages), 4)
        for page in pages:
            parser = PageLinks()
            parser.feed(page.read_text(encoding='utf-8'))
            for link in parser.links:
                parts = urlsplit(link)
                if not link or parts.scheme or parts.netloc:
                    continue
                target = SITE / parts.path if parts.path else page
                if parts.path in ('.', './'):
                    target = SITE / 'index.html'
                self.assertTrue(target.is_file(), (page.name, link))
                if parts.fragment:
                    target_parser = PageLinks()
                    target_parser.feed(target.read_text(encoding='utf-8'))
                    self.assertIn(parts.fragment, target_parser.ids, (page.name, link))


if __name__ == "__main__":
    unittest.main()
