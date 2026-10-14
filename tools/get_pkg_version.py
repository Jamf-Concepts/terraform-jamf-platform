#!/usr/bin/env python3
"""
Extract the name and version from a XAR-format .pkg file.

Prints two lines to stdout:
  <name>
  <version>

Name resolution order (first non-empty value wins):
  Distribution: <title> element
  Distribution: <pkg-ref> CFBundleName attribute
  PackageInfo:  identifier attribute (last component after the final dot)
  PackageInfo:  <bundle> CFBundleName attribute
  fallback:     'unknown'

Version resolution order:
  PackageInfo:  version attribute
  Distribution: <pkg-ref> version attribute
  fallback:     'unknown'
"""
import struct, zlib, xml.etree.ElementTree as ET, sys


def _read_heap_entry(f, toc_entry, heap_start):
    d = toc_entry.find('data')
    if d is None:
        return None
    offset = int(d.find('offset').text)
    length = int(d.find('length').text)
    f.seek(heap_start + offset)
    raw = f.read(length)
    try:
        raw = zlib.decompress(raw)
    except Exception:
        pass
    return ET.fromstring(raw)


def get_pkg_info(path):
    name = None
    version = None

    with open(path, 'rb') as f:
        if f.read(4) != b'xar!':
            return 'unknown', 'unknown'
        header_size = struct.unpack('>H', f.read(2))[0]
        f.read(2)
        toc_len = struct.unpack('>Q', f.read(8))[0]
        f.read(12)
        f.seek(header_size)
        toc = ET.fromstring(zlib.decompress(f.read(toc_len)))
        heap_start = header_size + toc_len

        for fe in toc.iter('file'):
            n = fe.find('name')
            if n is None:
                continue

            if n.text == 'Distribution':
                root = _read_heap_entry(f, fe, heap_start)
                if root is None:
                    continue
                # Title
                if not name:
                    t = root.find('title')
                    if t is not None and t.text and t.text.strip():
                        name = t.text.strip()
                # CFBundleName from pkg-ref as fallback name
                if not name:
                    for ref in root.iter('pkg-ref'):
                        n_attr = ref.get('CFBundleName')
                        if n_attr:
                            name = n_attr
                            break
                # Version from pkg-ref
                if not version:
                    for ref in root.iter('pkg-ref'):
                        v = ref.get('version')
                        if v:
                            version = v
                            break

            elif n.text == 'PackageInfo':
                root = _read_heap_entry(f, fe, heap_start)
                if root is None:
                    continue
                # Version from PackageInfo attribute (most reliable)
                if not version:
                    v = root.get('version')
                    if v:
                        version = v
                # Name from identifier (e.g. com.sentinelone.pkg → sentinelone)
                if not name:
                    ident = root.get('identifier', '')
                    if ident:
                        name = ident.split('.')[-1]
                # CFBundleName from nested bundle element
                if not name:
                    for b in root.iter('bundle'):
                        n_attr = b.get('CFBundleName')
                        if n_attr:
                            name = n_attr
                            break

    return name or 'unknown', version or 'unknown'


if __name__ == '__main__':
    pkg_name, pkg_version = get_pkg_info(sys.argv[1])
    print(pkg_name.replace(' ', '-'))
    print(pkg_version)
