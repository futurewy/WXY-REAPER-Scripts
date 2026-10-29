"""Verify public ReaPack index downloads against local reviewed scripts."""
from pathlib import Path
import hashlib
import urllib.request
import xml.etree.ElementTree as ET
from urllib.parse import urlsplit, unquote

ROOT = Path(__file__).resolve().parents[1]
URL = 'https://raw.githubusercontent.com/futurewy/WXY-REAPER-Scripts/main/index.xml'
def download(url):
    req = urllib.request.Request(url, headers={'User-Agent': 'WXY-ReaPack-verification'})
    with urllib.request.urlopen(req, timeout=45) as response:
        assert response.status == 200
        return response.read()

def main():
    document = download(URL)
    root = ET.fromstring(document)
    assert root.tag == 'index' and root.get('version') == '1'
    packages = root.findall('.//reapack')
    assert len(packages) == 6, f'Expected 6 packages, got {len(packages)}'
    sources = root.findall('.//source')
    assert len(sources) == 6, f'Expected 6 source files, got {len(sources)}'
    for source in sources:
        url = (source.text or '').strip()
        parsed = urlsplit(url)
        assert parsed.scheme == 'https' and parsed.hostname == 'raw.githubusercontent.com'
        parts = unquote(parsed.path).split('/')
        assert parts[1:3] == ['futurewy', 'WXY-REAPER-Scripts']
        revision = parts[3]
        assert len(revision) == 40 and all(c in '0123456789abcdef' for c in revision)
        relative = Path(*parts[4:])
        assert '..' not in relative.parts
        remote = download(url)
        local = (ROOT / relative).read_bytes()
        assert remote.replace(b'\r\n', b'\n') == local.replace(b'\r\n', b'\n'), str(relative)
        print(f'PASS public download: {relative} SHA256={hashlib.sha256(remote).hexdigest()}')
    print('PASS: public XML parsed, 6 immutable source URLs downloaded and matched reviewed copies.')

if __name__ == '__main__':
    main()
