#!/usr/bin/env python3
"""Exit 0 when two JSON documents are structurally equal (4 == 4.0), else print the first difference and exit 1."""
import json, sys

def diff(a, b, path=""):
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k not in a: return f"{path}.{k}: missing on the left"
            if k not in b: return f"{path}.{k}: missing on the right"
            d = diff(a[k], b[k], f"{path}.{k}")
            if d: return d
        return None
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b): return f"{path}: length {len(a)} vs {len(b)}"
        for i, (x, y) in enumerate(zip(a, b)):
            d = diff(x, y, f"{path}[{i}]")
            if d: return d
        return None
    if isinstance(a, bool) or isinstance(b, bool):
        return None if a is b else f"{path}: {a!r} vs {b!r}"
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return None if abs(a - b) < 1e-9 else f"{path}: {a!r} vs {b!r}"
    return None if a == b else f"{path}: {a!r} vs {b!r}"

a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
d = diff(a, b)
if d:
    print(d, file=sys.stderr); sys.exit(1)
