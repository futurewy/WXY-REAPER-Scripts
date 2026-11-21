
# -*- coding: utf-8 -*-
"""Verify the public ReaPack index downloads against the reviewed local scripts.

The index lists one <reapack> package per script and one <version> per
published revision. Republishing a package keeps the previous versions, so
the number of <source> elements can exceed the number of packages.

For every package the newest version is downloaded and compared byte for
byte with the reviewed copy in this repository. Older versions are still
checked: their source URL must be an immutable commit link and must stay
reachable, but they are compared against the file at their own commit.
"""
from pathlib import Path
import hashlib
import subprocess
import urllib.request
import xml.etree.ElementTree as ET
from urllib.parse import urlsplit, unquote

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://raw.githubusercontent.com/futurewy/WXY-REAPER-Scripts/main/index.xml'
EXPECTED_PACKAGES = 9


def download(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'WXY-ReaPack-verification'})
    with urllib.request.urlopen(req, timeout=45) as response:
        assert response.status == 200
        return response.read()


def parse_source(source):
    """Return (relative path, revision) after checking the URL is immutable."""
    url = (source.text or '').strip()
    parsed = urlsplit(url)
    assert parsed.scheme == 'https'
    assert parsed.hostname in ('raw.githubusercontent.com', 'github.com')
    parts = unquote(parsed.path).split('/')
    assert parts[1:3] == ['futurewy', 'WXY-REAPER-Scripts']
    if parsed.hostname == 'github.com':
        assert parts[3] == 'raw'
        parts.pop(3)
    revision = parts[3]
    assert len(revision) == 40 and all(c in '0123456789abcdef' for c in revision)
    relative = Path(*parts[4:])
    assert '..' not in relative.parts
    return relative, revision


def file_at_revision(relative, revision):
    """Return the published bytes for a relative path at a given commit."""
    path = "/".join(relative.parts)
    spec = f'{revision}:{path}'
    result = subprocess.run(
        ['git', '-C', str(ROOT), 'show', spec],
        capture_output=True)
    assert result.returncode == 0, f'cannot read {spec}'
    return result.stdout


def main():
    document = download(URL)
    root = ET.fromstring(document)
    assert root.tag == 'index' and root.get('version') == '1'
    packages = root.findall('.//reapack')
    assert len(packages) == EXPECTED_PACKAGES, \
        f'Expected {EXPECTED_PACKAGES} packages, got {len(packages)}'

    checked = 0
    for package in packages:
        name = package.get('name')
        versions = package.findall('version')
        assert versions, f'{name}: no version element'
        # The index lists versions oldest first, so the last one is current.
        newest = len(versions) - 1
        for index, version in enumerate(versions):
            sources = version.findall('source')
            assert len(sources) == 1, \
                f'{name} {version.get("name")}: expected 1 source, got {len(sources)}'
            relative, revision = parse_source(sources[0])
            remote = download((sources[0].text or '').strip())
            if index == newest:
                # Current version must match the reviewed copy in this repository.
                local = (ROOT / relative).read_bytes()
                assert remote.replace(b'\r\n', b'\n') == local.replace(b'\r\n', b'\n'), \
                    f'{relative}: published content differs from the reviewed copy'
            else:
                # Older versions must still match the file at their own commit.
                published = file_at_revision(relative, revision)
                assert remote.replace(b'\r\n', b'\n') == published.replace(b'\r\n', b'\n'), \
                    f'{relative}@{revision}: published content differs from the commit'
            checked += 1
            print(f'PASS public download: {relative} '
                  f'version={version.get("name")} SHA256={hashlib.sha256(remote).hexdigest()}')

    print(f'PASS: public XML parsed, {len(packages)} packages and '
          f'{checked} version source URLs downloaded and matched reviewed copies.')


if __name__ == '__main__':
    main()
