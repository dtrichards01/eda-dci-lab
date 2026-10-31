#!/usr/bin/env python3
"""Render ${VAR} placeholders in split-ns manifests from KEY=VALUE args.

Usage: split-ns-render.py [--ns NS] FILE KEY=VALUE ...   (prints to stdout)
--ns rewrites every `namespace:` (used for dry-run validation against another namespace).
Fails if any placeholder is left unrendered.
"""
import re
import string
import sys

args = sys.argv[1:]
ns = None
if args[:1] == ["--ns"]:
    ns, args = args[1], args[2:]
path, *pairs = args
values = dict(p.split("=", 1) for p in pairs)
text = string.Template(open(path).read()).safe_substitute(values)
left = sorted(set(re.findall(r"\$\{(\w+)\}", text)))
if left:
    sys.exit(f"{path}: unrendered {left}")
if ns:
    text = re.sub(r"(?m)^(\s*namespace:\s*).*$", rf"\g<1>{ns}", text)
sys.stdout.write(text)
