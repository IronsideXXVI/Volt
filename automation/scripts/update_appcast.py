#!/usr/bin/env python3
"""Prepend a signed Volt release to a Sparkle appcast while retaining history."""

from __future__ import annotations

import argparse
import email.utils
import os
import re
import tempfile
import urllib.parse
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC_NS = "http://purl.org/dc/elements/1.1/"
DEFAULT_FEED_URL = "https://ironsidexxvi.github.io/Volt/appcast.xml"

ET.register_namespace("sparkle", SPARKLE_NS)
ET.register_namespace("dc", DC_NS)


def sparkle_tag(name: str) -> str:
    return f"{{{SPARKLE_NS}}}{name}"


def require_https_url(value: str, label: str) -> str:
    parsed = urllib.parse.urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc:
        raise ValueError(f"{label} must be an absolute HTTPS URL")
    return value


def validate_release_data(args: argparse.Namespace) -> None:
    if not re.fullmatch(r"[0-9]+", args.version):
        raise ValueError("version must be a numeric Sparkle build number")
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.short_version):
        raise ValueError("short-version must contain three numeric components")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){2}", args.minimum_system_version):
        raise ValueError("minimum-system-version must contain three numeric components")
    if args.length <= 0:
        raise ValueError("length must be greater than zero")
    if not args.ed_signature.strip():
        raise ValueError("ed-signature cannot be empty")
    if args.limit < 1:
        raise ValueError("limit must be at least one")
    require_https_url(args.release_notes_url, "release-notes-url")
    require_https_url(args.download_url, "download-url")
    if email.utils.parsedate_to_datetime(args.pub_date) is None:
        raise ValueError("pub-date must be an RFC 2822 date")


def new_feed() -> tuple[ET.ElementTree, ET.Element]:
    root = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(root, "channel")
    ET.SubElement(channel, "title").text = "Volt Updates"
    ET.SubElement(channel, "link").text = DEFAULT_FEED_URL
    ET.SubElement(channel, "description").text = "Volt release updates"
    ET.SubElement(channel, "language").text = "en"
    return ET.ElementTree(root), channel


def load_feed(existing: Path | None) -> tuple[ET.ElementTree, ET.Element]:
    if existing is None or not existing.exists() or existing.stat().st_size == 0:
        return new_feed()

    tree = ET.parse(existing)
    root = tree.getroot()
    if root.tag != "rss":
        raise ValueError("existing appcast root must be <rss>")
    channel = root.find("channel")
    if channel is None:
        raise ValueError("existing appcast must contain a <channel>")
    return tree, channel


def child_text(item: ET.Element, tag: str) -> str | None:
    child = item.find(tag)
    return child.text if child is not None else None


def build_item(args: argparse.Namespace) -> ET.Element:
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Volt {args.short_version}"
    ET.SubElement(item, "pubDate").text = args.pub_date
    ET.SubElement(item, sparkle_tag("version")).text = args.version
    ET.SubElement(item, sparkle_tag("shortVersionString")).text = args.short_version
    ET.SubElement(item, sparkle_tag("minimumSystemVersion")).text = args.minimum_system_version
    ET.SubElement(item, sparkle_tag("releaseNotesLink")).text = args.release_notes_url
    ET.SubElement(
        item,
        "enclosure",
        {
            "url": args.download_url,
            "length": str(args.length),
            "type": "application/octet-stream",
            sparkle_tag("edSignature"): args.ed_signature,
        },
    )
    return item


def update_feed(args: argparse.Namespace) -> ET.ElementTree:
    validate_release_data(args)
    tree, channel = load_feed(args.existing)

    old_items = list(channel.findall("item"))
    for item in old_items:
        channel.remove(item)

    retained = [
        item
        for item in old_items
        if child_text(item, sparkle_tag("version")) != args.version
    ]

    channel.append(build_item(args))
    for item in retained[: max(0, args.limit - 1)]:
        channel.append(item)

    ET.indent(tree, space="  ")
    return tree


def write_atomically(tree: ET.ElementTree, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="wb", prefix=f".{output.name}.", dir=output.parent, delete=False
    ) as temporary:
        temporary_path = Path(temporary.name)
        tree.write(temporary, encoding="utf-8", xml_declaration=True)
    os.replace(temporary_path, output)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--existing", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--short-version", required=True)
    parser.add_argument("--minimum-system-version", default="14.0.0")
    parser.add_argument("--release-notes-url", required=True)
    parser.add_argument("--download-url", required=True)
    parser.add_argument("--length", type=int, required=True)
    parser.add_argument("--ed-signature", required=True)
    parser.add_argument("--pub-date", required=True)
    parser.add_argument("--limit", type=int, default=15)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    write_atomically(update_feed(args), args.output)


if __name__ == "__main__":
    main()
