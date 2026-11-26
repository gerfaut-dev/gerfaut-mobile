#!/usr/bin/env python3
"""Adds to verification-metadata.xml the files Gradle's write mode left out.

usage: gradle-pins.py <verification-metadata.xml> <files-2.1 folder> <group:name:version:file>...

`--write-verification-metadata` leaves out some parent POMs and BOMs,
which the next strict build then names as failed. A fetch phase run by
hand with GRADLE_OPTS=-Dorg.gradle.dependency.verification=lenient lists
them all at once; it accepts any module, so it runs on a volume of its
own, thrown away after, and never builds anything that ships. Copy
caches/modules-2/files-2.1 out of that volume and give each file here.

The sha256 comes from the file in the cache, taken on first use like
every other hash of the file. Its sha1 must equal the one Maven Central
publishes, or nothing is written: a check that the file is the one
Central serves, which is no second source when the file came from
Central itself.
"""
import hashlib
import pathlib
import re
import sys
import urllib.error
import urllib.request

meta, cache, *items = sys.argv[1:]
text = pathlib.Path(meta).read_text()
cache = pathlib.Path(cache)
ORIGIN = "Gradle cache, first use; sha1 as on Maven Central"

for item in items:
    group, name, version, fname = item.split(":")
    found = list((cache / group / name / version).glob(f"*/{fname}"))
    if len(found) != 1:
        sys.exit(f"{item}: {len(found)} files in the cache")
    data = found[0].read_bytes()
    sha256 = hashlib.sha256(data).hexdigest()
    sha1 = hashlib.sha1(data).hexdigest()
    url = "https://repo.maven.apache.org/maven2/{}/{}/{}/{}.sha1".format(group.replace(".", "/"), name, version, fname)
    try:
        central = urllib.request.urlopen(url, timeout=30).read().decode().split()[0].strip()
    except urllib.error.HTTPError as error:
        sys.exit(f"{item}: Maven Central has no sha1 for it ({error.code}); check it against its own repository by hand")
    if central != sha1:
        sys.exit(f"{item}: cache sha1 {sha1}, Maven Central {central}")
    artifact = (f'         <artifact name="{fname}">\n'
                f'            <sha256 value="{sha256}" origin="{ORIGIN}"/>\n'
                f'         </artifact>\n')
    head = f'      <component group="{group}" name="{name}" version="{version}">\n'
    if head in text:
        start = text.index(head) + len(head)
        end = text.index("      </component>\n", start)
        body = text[start:end]
        if f'<artifact name="{fname}">' in body:
            sys.exit(f"{item}: already pinned")
        # Keep the artifacts sorted by name, as Gradle writes them.
        names = re.findall(r'<artifact name="([^"]+)">', body)
        later = [n for n in names if n > fname]
        at = start + body.index(f'         <artifact name="{later[0]}">') if later else end
        text = text[:at] + artifact + text[at:]
    else:
        # A new component goes before the first one that sorts after it.
        comps = [(m.start(), m.group(1), m.group(2), m.group(3)) for m in
                 re.finditer(r'      <component group="([^"]+)" name="([^"]+)" version="([^"]+)">\n', text)]
        key = (group, name, version)
        at = next((pos for pos, g, n, v in comps if (g, n, v) > key), None)
        if at is None:
            at = text.index("   </components>")
        text = text[:at] + head + artifact + "      </component>\n" + text[at:]
    print(f"{sha256}  {item}  (sha1 {sha1} = Maven Central)")

pathlib.Path(meta).write_text(text)
