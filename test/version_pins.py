#!/usr/bin/env python3
"""Every Hermes version named in the docs and build sheet must be the one the
Dockerfiles actually pin. The upstream-bump workflow moves only the Dockerfile
ARGs, so any other hard-coded version silently goes stale (it did: the listing
readme still said v2026.9.14 four releases later).
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parent.parent
pin_re = re.compile(r"ARG HERMES_IMAGE_VERSION=(\S+)")
pins = {f: pin_re.search((root / f).read_text()).group(1) for f in ("Dockerfile", "Dockerfile.legacy-data")}
problems = []
if len(set(pins.values())) != 1:
    problems.append(f"Dockerfile pins disagree: {pins}")
pin = pins["Dockerfile"]

version_re = re.compile(r"\bv(?:\d{1,3}\.\d+\.\d+|20\d\d\.\d+\.\d+)\b")
for f in ("README.md", "TEMPLATE_OVERVIEW.md", "template.json"):
    for n, line in enumerate((root / f).read_text().splitlines(), 1):
        for v in version_re.findall(line):
            if v != pin:
                problems.append(f"{f}:{n} names {v}, Dockerfile pins {pin}")

for p in problems:
    print("FAIL", p)
print("PASS" if not problems else f"{len(problems)} problems")
sys.exit(1 if problems else 0)
