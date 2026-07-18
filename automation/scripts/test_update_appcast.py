#!/usr/bin/env python3

from __future__ import annotations

import argparse
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

import update_appcast


class UpdateAppcastTests(unittest.TestCase):
    def release(self, **overrides: object) -> argparse.Namespace:
        values: dict[str, object] = {
            "existing": None,
            "output": Path("unused.xml"),
            "version": "42",
            "short_version": "0.1.42",
            "minimum_system_version": "14.0.0",
            "release_notes_url": "https://ironsidexxvi.github.io/Volt/releases/0.1.42.html",
            "download_url": "https://github.com/IronsideXXVI/Volt/releases/download/v0.1.42/Volt-0.1.42.dmg",
            "length": 123456,
            "ed_signature": "test-signature",
            "pub_date": "Fri, 17 Jul 2026 22:00:00 +0000",
            "limit": 15,
        }
        values.update(overrides)
        return argparse.Namespace(**values)

    def test_creates_complete_feed_item(self) -> None:
        tree = update_appcast.update_feed(self.release())
        item = tree.getroot().find("channel/item")

        self.assertIsNotNone(item)
        assert item is not None
        self.assertEqual(item.findtext(update_appcast.sparkle_tag("version")), "42")
        self.assertEqual(
            item.findtext(update_appcast.sparkle_tag("minimumSystemVersion")),
            "14.0.0",
        )
        enclosure = item.find("enclosure")
        self.assertIsNotNone(enclosure)
        assert enclosure is not None
        self.assertEqual(enclosure.get("length"), "123456")
        self.assertEqual(
            enclosure.get(update_appcast.sparkle_tag("edSignature")),
            "test-signature",
        )

    def test_replaces_duplicate_and_retains_bounded_history(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            existing = Path(directory) / "appcast.xml"
            existing.write_text(
                """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Existing title</title>
    <item><sparkle:version>42</sparkle:version></item>
    <item><sparkle:version>41</sparkle:version></item>
    <item><sparkle:version>40</sparkle:version></item>
  </channel>
</rss>
""",
                encoding="utf-8",
            )

            tree = update_appcast.update_feed(
                self.release(existing=existing, limit=3)
            )
            channel = tree.getroot().find("channel")
            self.assertIsNotNone(channel)
            assert channel is not None
            versions = [
                item.findtext(update_appcast.sparkle_tag("version"))
                for item in channel.findall("item")
            ]

            self.assertEqual(channel.findtext("title"), "Existing title")
            self.assertEqual(versions, ["42", "41", "40"])

    def test_rejects_non_public_download_url(self) -> None:
        with self.assertRaisesRegex(ValueError, "absolute HTTPS URL"):
            update_appcast.update_feed(
                self.release(download_url="file:///tmp/Volt.dmg")
            )


if __name__ == "__main__":
    unittest.main()
