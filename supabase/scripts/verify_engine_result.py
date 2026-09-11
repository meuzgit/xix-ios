#!/usr/bin/env python3
"""Acceptance for Build Doc 2 step 2: xix.results.payload for the seeded Fraserview round must equal the
fixture's expected block. Seeded UUIDs are mapped back to the fixture's ids first; the diff rules match
the Swift harness (only expected keys are checked, annotations skipped, arrays of objects matched by id
when the fixture keys them by id, ±1 on rivalPoints).

Usage: verify_engine_result.py [payload.json]   (reads the payload from the local database when omitted)
"""
import json, pathlib, subprocess, sys
root = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / "supabase" / "scripts"))
from gen_seed import IDS  # noqa: E402

fixture = json.load(open(root / "fraserview_2026-09-09.json"))
expected = fixture["expected"]

if len(sys.argv) > 1:
    payload = json.load(open(sys.argv[1]))
else:
    sql = "select payload from xix.results where round_id = '%s'" % IDS["round"]
    out = subprocess.run(["docker", "exec", "-i", "supabase_db_XIX", "psql", "-U", "postgres", "-Atc", sql],
                         capture_output=True, text=True, check=True).stdout.strip()
    if not out:
        print("no results row for the seeded round"); sys.exit(2)
    payload = json.loads(out)

# uuid → fixture id
back = {}
for kind in ("player", "game", "callout"):
    for fid, uid in IDS[kind].items():
        back[uid] = fid

def unmap(v):
    if isinstance(v, dict):
        return {back.get(k, k): unmap(x) for k, x in v.items()}
    if isinstance(v, list):
        return [unmap(x) for x in v]
    if isinstance(v, str):
        if v in back: return back[v]
        for uid, fid in back.items():   # ids embedded in text, e.g. "ray 2&1"
            v = v.replace(uid, fid)
        return v
    return v

actual = unmap(payload)
ANNOTATIONS = {"note", "notes", "description"}
ID_KEYS = ["gameID", "calloutID", "id", "player", "profile"]
mismatches = []

def index(arr):
    out = {}
    for item in arr:
        if isinstance(item, dict):
            for k in ID_KEYS:
                if isinstance(item.get(k), str):
                    out.setdefault(item[k], item); break
    return out

def diff(exp, act, path):
    if exp is None:
        if act is not None: mismatches.append((path, "null", act))
        return
    if act is None:
        mismatches.append((path, exp, "<missing>")); return
    if isinstance(exp, dict):
        if isinstance(act, list): act = index(act)
        if not isinstance(act, dict): mismatches.append((path, exp, act)); return
        for k, v in exp.items():
            if k.startswith("_") or k in ANNOTATIONS: continue
            diff(v, act.get(k), f"{path}.{k}" if path else k)
    elif isinstance(exp, list):
        if not isinstance(act, list): mismatches.append((path, exp, act)); return
        if len(exp) != len(act): mismatches.append((f"{path}.count", len(exp), len(act)))
        for i, v in enumerate(exp):
            diff(v, act[i] if i < len(act) else None, f"{path}[{i}]")
    elif isinstance(exp, bool) or isinstance(act, bool):
        if exp != act: mismatches.append((path, exp, act))
    elif isinstance(exp, (int, float)) and isinstance(act, (int, float)):
        tol = 1 if path.startswith("rivalPoints") else 0
        if abs(exp - act) > tol + 1e-9: mismatches.append((path, exp, act))
    elif exp != act:
        mismatches.append((path, exp, act))

diff(expected, actual, "")
if mismatches:
    print(f"{len(mismatches)} field(s) differ from the fixture's expected block:")
    for p, e, a in mismatches: print(f"  {p}: expected {e!r} · actual {a!r}")
    sys.exit(1)
print(f"results.payload matches fraserview_2026-09-09.json expected (engineVersion {payload.get('engineVersion')}, status {payload.get('status')})")
