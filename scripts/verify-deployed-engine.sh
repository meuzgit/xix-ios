#!/usr/bin/env bash
# Confirm the engine deployed to the shared project is the one this checkout builds.
#
# Two checks, cheapest first:
#   1. the function reports the sha256 of the module it loaded, which must equal the local one
#   2. a throwaway round is scored by it, and the payload must carry the leaderboard metrics this
#      engine emits — a stale module answers without stableford_vs_level
#
# The round is created, scored and deleted again; nothing is left behind. Keys come from the CLI and
# are never printed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REF="${XIX_PROJECT_REF:-zsipifaskpupjwfiinen}"
URL="https://$REF.supabase.co"
MODULE="supabase/functions/xix-engine/xix-engine-cli.wasm"
ROUND="eeeeeeee-eeee-4eee-8eee-eeeeeeeeee01"
COURSE="eeeeeeee-eeee-4eee-8eee-eeeeeeeeee00"

[ -f "$MODULE" ] || { echo "no module at $MODULE — run make wasm first"; exit 1; }
LOCAL_SHA="$(shasum -a 256 "$MODULE" | cut -d' ' -f1)"

KEYS="$(supabase projects api-keys --project-ref "$REF" -o json)"
ANON="$(echo "$KEYS" | python3 -c 'import json,sys; print(next(k["api_key"] for k in json.load(sys.stdin) if k["id"]=="anon"))')"
SERVICE="$(echo "$KEYS" | python3 -c 'import json,sys; print(next(k["api_key"] for k in json.load(sys.stdin) if k["id"]=="service_role"))')"
unset KEYS

echo "== 1. which module is deployed"
DEPLOYED="$(curl -s -X GET "$URL/functions/v1/xix-engine" -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("module",""))')"
if [ "$DEPLOYED" != "$LOCAL_SHA" ]; then
  echo "   deployed ${DEPLOYED:0:16}… but this checkout builds ${LOCAL_SHA:0:16}…"
  echo "   run: make deploy-engine"
  exit 1
fi
echo "   ${LOCAL_SHA:0:16}… matches this checkout"

USER_ID=""
cleanup() {
  supabase db query --linked "delete from xix.rounds where id = '$ROUND'" >/dev/null 2>&1 || true
  supabase db query --linked "delete from xix.courses where id = '$COURSE'" >/dev/null 2>&1 || true
  # The profile goes with the auth user (profiles.id cascades from auth.users).
  [ -n "$USER_ID" ] && curl -s -X DELETE "$URL/auth/v1/admin/users/$USER_ID" \
    -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "== 2. score a throwaway round with it"
# One statement per call: the Management API runs a single command at a time, and a data-modifying CTE
# is not visible to the rest of its own statement anyway, so the round has to exist before its scores.
q() { supabase db query --linked "$1" >/dev/null; }

q "insert into xix.courses (id, name, region) values ('$COURSE', 'Deploy Check', 'Local')
   on conflict (id) do update set name = excluded.name"
q "insert into xix.course_holes (course_id, hole, par, stroke_index)
   select '$COURSE', n, 4, n from generate_series(1, 9) n on conflict do nothing"
# A round needs an owner with a profile, and the shared project holds no leftover people by design —
# so make one for the duration and delete it again on the way out.
USER_ID="$(curl -s -X POST "$URL/auth/v1/admin/users" \
  -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" -H "Content-Type: application/json" \
  -d "{\"email\":\"xix-deploy-check-$(date +%s)@privaterelay.appleid.com\",\"email_confirm\":true}" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
[ -n "$USER_ID" ] || { echo "   could not create a throwaway user"; exit 1; }
q "insert into xix.profiles (id, display_name) values ('$USER_ID', 'Deploy Check') on conflict (id) do nothing"
q "insert into xix.rounds (id, owner_id, course_id, holes, status, join_code, ended_at)
   values ('$ROUND', '$USER_ID', '$COURSE', 9, 'ended', 'DEPLOY', now())
   on conflict (id) do update set status = 'ended', ended_at = now()"
# Two players with an entered index, so the passive Stableford metric has strokes to work from.
q "insert into xix.players (id, round_id, display_name, seat, index_snapshot)
   values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeee11', '$ROUND', 'One', 0, 5),
          ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeee12', '$ROUND', 'Two', 1, 12)
   on conflict (id) do nothing"
q "insert into xix.scores (round_id, player_id, hole, strokes, client_ts)
   select '$ROUND', pid, n, 4 + (n % 2), now()
     from generate_series(1, 9) n,
          (values ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeee11'::uuid), ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeee12'::uuid)) as x(pid)
   on conflict (round_id, player_id, hole) do update set strokes = excluded.strokes"

curl -s -X POST "$URL/functions/v1/xix-engine" \
  -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" -H "Content-Type: application/json" \
  -d "{\"round_id\":\"$ROUND\"}" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("error"):
    print("   the function refused it:", d["error"]); raise SystemExit(1)
print("   scored:", d.get("status"), "engine version", d.get("version"))'

echo "== 3. what the payload carries"
supabase db query --linked "
select jsonb_build_object(
  'modes', (select jsonb_agg(k order by k) from jsonb_object_keys(payload -> 'leaderboard') k),
  'stableford_vs_level', payload -> 'leaderboard' -> 'stableford_vs_level',
  'engine_version', payload ->> 'engineVersion')
from xix.results where round_id = '$ROUND'" -o json 2>/dev/null | python3 -c '
import json, sys
rows = json.load(sys.stdin).get("rows", [])
if not rows:
    print("   no result was written"); raise SystemExit(1)
out = list(rows[0].values())[0]
modes = out.get("modes") or []
print("   leaderboard modes:", ", ".join(modes))
if "stableford_vs_level" not in modes:
    print("   MISSING stableford_vs_level — the deployed module is older than this engine")
    raise SystemExit(1)
print("   stableford_vs_level:", json.dumps(out["stableford_vs_level"]))
print("   engineVersion:", out.get("engine_version"))'

echo "== the deployed engine is this one"
