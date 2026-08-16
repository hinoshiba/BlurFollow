#!/usr/bin/env python3
"""Validate BlurFollow App Store text metadata and screenshot deliverables."""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse


STORE_ROOT = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = STORE_ROOT.parent


class SiteHTMLParser(HTMLParser):
    """Collect local references and basic accessibility metadata."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.references: list[tuple[str, str]] = []
        self.ids: list[str] = []
        self.html_lang: str | None = None
        self.images_without_alt = 0

    def handle_starttag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        values = {name: value for name, value in attrs}
        if tag == "html":
            self.html_lang = values.get("lang")
        element_id = values.get("id")
        if element_id:
            self.ids.append(element_id)
        if tag in {"a", "link"} and values.get("href"):
            self.references.append(("href", values["href"] or ""))
        if tag in {"img", "script", "source"} and values.get("src"):
            self.references.append(("src", values["src"] or ""))
        if tag == "img" and "alt" not in values:
            self.images_without_alt += 1

    def handle_startendtag(
        self, tag: str, attrs: list[tuple[str, str | None]]
    ) -> None:
        self.handle_starttag(tag, attrs)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8").rstrip("\n")


def png_properties(path: Path) -> tuple[int, int, bool]:
    with path.open("rb") as stream:
        if stream.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError("not a valid PNG header")
        width = height = None
        has_alpha = False
        while True:
            length_bytes = stream.read(4)
            if len(length_bytes) != 4:
                raise ValueError("truncated PNG chunk")
            length = struct.unpack(">I", length_bytes)[0]
            chunk_type = stream.read(4)
            data = stream.read(length)
            if len(chunk_type) != 4 or len(data) != length or len(stream.read(4)) != 4:
                raise ValueError("truncated PNG chunk")
            if chunk_type == b"IHDR":
                if length != 13:
                    raise ValueError("invalid IHDR length")
                width, height = struct.unpack(">II", data[:8])
                color_type = data[9]
                has_alpha = color_type in {4, 6}
            elif chunk_type == b"tRNS":
                has_alpha = True
            elif chunk_type in {b"IDAT", b"IEND"}:
                break
        if width is None or height is None:
            raise ValueError("PNG is missing IHDR")
        return width, height, has_alpha


def validate_url(value: str) -> str | None:
    parsed = urlparse(value)
    if parsed.scheme != "https" or not parsed.netloc:
        return "must be an absolute HTTPS URL"
    if parsed.username or parsed.password:
        return "must not contain URL credentials"
    if parsed.query or parsed.fragment:
        return "must not contain a query or fragment"
    return None


def public_path_for_url(value: str, expected_origin: str) -> Path | None:
    parsed = urlparse(value)
    origin = f"{parsed.scheme}://{parsed.netloc}"
    if origin != expected_origin:
        return None
    relative = parsed.path.lstrip("/")
    if not relative or parsed.path.endswith("/"):
        relative = f"{relative}index.html"
    return REPOSITORY_ROOT / "http_dist" / relative


def validate_static_site(errors: list[str], expected_origin: str) -> None:
    http_root = REPOSITORY_ROOT / "http_dist"
    parsed_pages: dict[Path, SiteHTMLParser] = {}

    for page in sorted(http_root.rglob("*.html")):
        parser = SiteHTMLParser()
        try:
            parser.feed(read_text(page))
            parser.close()
        except Exception as error:  # HTMLParser exposes source-specific failures.
            errors.append(f"{page.relative_to(REPOSITORY_ROOT)}: HTML parse failed: {error}")
            continue
        parsed_pages[page.resolve()] = parser
        label = page.relative_to(REPOSITORY_ROOT)
        if not parser.html_lang:
            errors.append(f"{label}: html element is missing lang")
        if len(parser.ids) != len(set(parser.ids)):
            errors.append(f"{label}: duplicate id attribute")
        if parser.images_without_alt:
            errors.append(
                f"{label}: {parser.images_without_alt} image(s) are missing alt"
            )

    origin = urlparse(expected_origin)
    for source, parser in parsed_pages.items():
        for attribute, reference in parser.references:
            parsed = urlparse(reference)
            if parsed.scheme in {"mailto", "tel", "data"}:
                continue
            if parsed.scheme in {"http", "https"}:
                if (parsed.scheme, parsed.netloc) != (origin.scheme, origin.netloc):
                    continue
                target = http_root / parsed.path.lstrip("/")
            elif parsed.scheme or parsed.netloc:
                errors.append(
                    f"{source.relative_to(REPOSITORY_ROOT)}: unsupported {attribute} "
                    f"reference {reference!r}"
                )
                continue
            elif parsed.path.startswith("/"):
                target = http_root / parsed.path.lstrip("/")
            elif parsed.path:
                target = source.parent / parsed.path
            else:
                target = source

            if reference.endswith("/") or parsed.path.endswith("/"):
                target = target / "index.html"
            target = target.resolve()
            try:
                target.relative_to(http_root.resolve())
            except ValueError:
                errors.append(
                    f"{source.relative_to(REPOSITORY_ROOT)}: {attribute} escapes "
                    f"http_dist: {reference!r}"
                )
                continue
            if not target.is_file():
                errors.append(
                    f"{source.relative_to(REPOSITORY_ROOT)}: broken {attribute} "
                    f"reference {reference!r}"
                )
                continue
            if parsed.fragment and target.suffix == ".html":
                target_parser = parsed_pages.get(target)
                if target_parser and parsed.fragment not in target_parser.ids:
                    errors.append(
                        f"{source.relative_to(REPOSITORY_ROOT)}: missing fragment "
                        f"#{parsed.fragment} in {target.relative_to(REPOSITORY_ROOT)}"
                    )

    try:
        manifest = json.loads(read_text(http_root / "site.webmanifest"))
        if manifest.get("start_url") != "/":
            errors.append("http_dist/site.webmanifest: start_url must be /")
    except (OSError, json.JSONDecodeError) as error:
        errors.append(f"http_dist/site.webmanifest: invalid JSON: {error}")

    try:
        sitemap = ET.parse(http_root / "sitemap.xml")
        namespace = {"s": "http://www.sitemaps.org/schemas/sitemap/0.9"}
        locations = [node.text or "" for node in sitemap.findall("s:url/s:loc", namespace)]
        if not locations:
            errors.append("http_dist/sitemap.xml: contains no URL locations")
        for location in locations:
            if public_path_for_url(location, expected_origin) is None:
                errors.append(f"http_dist/sitemap.xml: unexpected origin in {location!r}")
            elif not public_path_for_url(location, expected_origin).is_file():
                errors.append(f"http_dist/sitemap.xml: missing page for {location!r}")
    except (OSError, ET.ParseError) as error:
        errors.append(f"http_dist/sitemap.xml: invalid XML: {error}")

    mirror_pairs = [
        (REPOSITORY_ROOT / "LICENSE", http_root / "oss" / "LICENSE"),
        (REPOSITORY_ROOT / "NOTICE", http_root / "oss" / "NOTICE"),
        (REPOSITORY_ROOT / "THIRD_PARTY_NOTICES.md", http_root / "oss" / "THIRD_PARTY_NOTICES.md"),
        (REPOSITORY_ROOT / "DEPENDENCIES.md", http_root / "oss" / "DEPENDENCIES.md"),
        (REPOSITORY_ROOT / "TRADEMARKS.md", http_root / "oss" / "TRADEMARKS.md"),
        (REPOSITORY_ROOT / "SECURITY.md", http_root / "oss" / "SECURITY.md"),
        (REPOSITORY_ROOT / "Brand" / "PROVENANCE.md", http_root / "oss" / "Brand" / "PROVENANCE.md"),
        (REPOSITORY_ROOT / "Docs" / "THREAT_MODEL.md", http_root / "oss" / "Docs" / "THREAT_MODEL.md"),
        (REPOSITORY_ROOT / "Docs" / "COMPATIBILITY.md", http_root / "oss" / "Docs" / "COMPATIBILITY.md"),
        (REPOSITORY_ROOT / "Docs" / "RELEASE.md", http_root / "oss" / "Docs" / "RELEASE.md"),
    ]
    for source, mirror in mirror_pairs:
        if not mirror.is_file():
            errors.append(f"{mirror.relative_to(REPOSITORY_ROOT)}: mirror is missing")
        elif source.read_bytes() != mirror.read_bytes():
            errors.append(f"{mirror.relative_to(REPOSITORY_ROOT)}: differs from source")

    markdown_link = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
    for document in sorted((http_root / "oss").rglob("*.md")):
        for reference in markdown_link.findall(read_text(document)):
            reference = reference.strip().split(" ", 1)[0].strip("<>")
            parsed = urlparse(reference)
            if parsed.scheme in {"http", "https", "mailto"} or not parsed.path:
                continue
            target = (document.parent / parsed.path).resolve()
            if not target.is_file():
                errors.append(
                    f"{document.relative_to(REPOSITORY_ROOT)}: broken Markdown "
                    f"link {reference!r}"
                )

    print(f"OK    static site: {len(parsed_pages)} HTML pages and local references")


def validate() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--require-screenshots",
        action="store_true",
        help="fail when a screenshot listed in the manifest is missing",
    )
    args = parser.parse_args()

    errors: list[str] = []
    warnings: list[str] = []

    try:
        metadata_manifest = json.loads(
            read_text(STORE_ROOT / "metadata_manifest.json")
        )
        screenshot_manifest = json.loads(
            read_text(STORE_ROOT / "screenshot_manifest.json")
        )
    except (OSError, json.JSONDecodeError) as error:
        print(f"ERROR manifest: {error}", file=sys.stderr)
        return 1

    locales = metadata_manifest["locales"]
    fields = metadata_manifest["localized_fields"]
    expected_origin = metadata_manifest["intended_origin"]

    for locale in locales:
        locale_dir = STORE_ROOT / "metadata" / locale
        for filename, rules in fields.items():
            path = locale_dir / filename
            label = f"{locale}/{filename}"
            if not path.is_file():
                if rules.get("required"):
                    errors.append(f"{label}: required file is missing")
                continue

            try:
                value = read_text(path)
            except UnicodeDecodeError:
                errors.append(f"{label}: file is not valid UTF-8")
                continue

            if rules.get("required") and not value.strip():
                errors.append(f"{label}: value is empty")
                continue
            if value != value.strip():
                errors.append(f"{label}: leading or trailing whitespace is not allowed")

            characters = len(value)
            utf8_bytes = len(value.encode("utf-8"))
            minimum = rules.get("min_characters")
            maximum = rules.get("max_characters")
            max_bytes = rules.get("max_utf8_bytes")
            if minimum is not None and characters < minimum:
                errors.append(f"{label}: {characters} characters; minimum is {minimum}")
            if maximum is not None and characters > maximum:
                errors.append(f"{label}: {characters} characters; maximum is {maximum}")
            if max_bytes is not None and utf8_bytes > max_bytes:
                errors.append(f"{label}: {utf8_bytes} UTF-8 bytes; maximum is {max_bytes}")

            if rules.get("plain_text"):
                if "<script" in value.casefold() or "<html" in value.casefold():
                    errors.append(f"{label}: HTML is not allowed")
                if "](" in value or "```" in value:
                    errors.append(f"{label}: Markdown markup is not allowed")

            if rules.get("https_url"):
                url_error = validate_url(value)
                if url_error:
                    errors.append(f"{label}: {url_error}")
                else:
                    public_path = public_path_for_url(value, expected_origin)
                    if public_path is None:
                        errors.append(
                            f"{label}: URL origin must be {expected_origin}"
                        )
                    elif not public_path.is_file():
                        errors.append(
                            f"{label}: public page is missing at "
                            f"{public_path.relative_to(REPOSITORY_ROOT)}"
                        )

            if rules.get("comma_separated"):
                keywords = [item.strip() for item in value.split(",")]
                if any(not item for item in keywords):
                    errors.append(f"{label}: keyword list contains an empty item")
                folded = [item.casefold() for item in keywords]
                if len(folded) != len(set(folded)):
                    errors.append(f"{label}: keyword list contains a duplicate")
                min_keyword = rules.get("minimum_keyword_characters", 1)
                for keyword in keywords:
                    if len(keyword) < min_keyword:
                        errors.append(
                            f"{label}: keyword {keyword!r} has fewer than "
                            f"{min_keyword} characters"
                        )
                for forbidden in rules.get("forbidden_terms", []):
                    if any(forbidden.casefold() in item for item in folded):
                        errors.append(
                            f"{label}: forbidden or duplicated product term "
                            f"{forbidden!r} is present"
                        )

            if filename == "keywords.txt":
                print(f"OK    {label}: {utf8_bytes}/100 UTF-8 bytes")
            elif maximum is not None:
                print(f"OK    {label}: {characters}/{maximum} characters")
            elif max_bytes is not None:
                print(f"OK    {label}: {utf8_bytes}/{max_bytes} UTF-8 bytes")

    common_dir = STORE_ROOT / "metadata" / "common"
    for filename in metadata_manifest["common_fields"]:
        path = common_dir / filename
        if not path.is_file():
            errors.append(f"common/{filename}: required file is missing")
            continue
        if path.suffix == ".json":
            try:
                json.loads(read_text(path))
            except json.JSONDecodeError as error:
                errors.append(f"common/{filename}: invalid JSON: {error}")
        elif not read_text(path).strip():
            errors.append(f"common/{filename}: value is empty")

    if read_text(common_dir / "primary_category.txt") != "Utilities":
        errors.append("common/primary_category.txt: expected Utilities")
    if read_text(common_dir / "secondary_category.txt") != "Productivity":
        errors.append("common/secondary_category.txt: expected Productivity")

    validate_static_site(errors, expected_origin)

    screenshot_locales = screenshot_manifest["locales"]
    required_screenshots = [
        item["filename"] for item in screenshot_manifest["required_files"]
    ]
    accepted_sizes = {
        tuple(size) for size in screenshot_manifest["accepted_sizes"]
    }
    maximum_count = screenshot_manifest["maximum_count"]
    allow_alpha = screenshot_manifest.get("allow_alpha", False)
    expected_names = set(required_screenshots)

    for locale in screenshot_locales:
        directory = STORE_ROOT / "screenshots" / locale
        images = sorted(
            path for path in directory.iterdir()
            if path.is_file() and path.suffix.casefold() in {".png", ".jpg", ".jpeg"}
        ) if directory.is_dir() else []

        if len(images) > maximum_count:
            errors.append(
                f"screenshots/{locale}: {len(images)} images; maximum is {maximum_count}"
            )
        unexpected = {path.name for path in images} - expected_names
        for filename in sorted(unexpected):
            errors.append(f"screenshots/{locale}/{filename}: not listed in manifest")

        for filename in required_screenshots:
            path = directory / filename
            if not path.is_file():
                message = f"screenshots/{locale}/{filename}: capture is missing"
                if args.require_screenshots:
                    errors.append(message)
                else:
                    warnings.append(message)
                continue
            if path.suffix.casefold() != ".png":
                errors.append(f"screenshots/{locale}/{filename}: manifest requires PNG")
                continue
            try:
                width, height, has_alpha = png_properties(path)
            except (OSError, ValueError) as error:
                errors.append(f"screenshots/{locale}/{filename}: {error}")
                continue
            dimensions = (width, height)
            if dimensions not in accepted_sizes:
                sizes = ", ".join(f"{width}×{height}" for width, height in sorted(accepted_sizes))
                errors.append(
                    f"screenshots/{locale}/{filename}: {dimensions[0]}×{dimensions[1]} "
                    f"is not accepted; use {sizes}"
                )
            else:
                if has_alpha and not allow_alpha:
                    errors.append(
                        f"screenshots/{locale}/{filename}: alpha/transparency is not allowed"
                    )
                print(
                    f"OK    screenshots/{locale}/{filename}: "
                    f"{dimensions[0]}×{dimensions[1]}, "
                    f"{'alpha' if has_alpha else 'opaque RGB'}"
                )

    for warning in warnings:
        print(f"WARN  {warning}")
    for error in errors:
        print(f"ERROR {error}", file=sys.stderr)

    if errors:
        print(
            f"FAILED: {len(errors)} error(s), {len(warnings)} warning(s)",
            file=sys.stderr,
        )
        return 1

    print(f"PASSED: 0 errors, {len(warnings)} warning(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(validate())
