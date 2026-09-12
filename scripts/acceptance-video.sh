#!/bin/sh
# Build Doc 3 step 1 acceptance: two simulators, one round, New round to results with a guest joining
# by link mid-round, driven by the UI tests in XIX/UITests and recorded from both simulators.
# Needs `supabase start`, `supabase functions serve --no-verify-jwt` (the local webhook calls it), and
# the two simulators booted. Output: docs/acceptance-step1.mp4 (both phones side by side).
set -e
cd "$(dirname "$0")/.."
A=${XIX_SIM_A:?"XIX_SIM_A=<udid of the owner's simulator>"}
B=${XIX_SIM_B:?"XIX_SIM_B=<udid of the guest's simulator>"}
OUT=${XIX_VIDEO_OUT:-docs/acceptance-step1.mp4}
DD=/tmp/xix-dd
HAND=/tmp/xix-video
rm -rf "$HAND"; mkdir -p "$HAND"

echo "building…"
xcodebuild -project XIX/XIX.xcodeproj -scheme XIX -configuration Debug -destination "id=$A" -derivedDataPath "$DD" build-for-testing 2>&1 | grep -E "error:|BUILD" || true

for U in "$A" "$B"; do
  xcrun simctl terminate "$U" golf.xix.app 2>/dev/null || true
  xcrun simctl uninstall "$U" golf.xix.app 2>/dev/null || true
done

pkill -INT -f "simctl io .* recordVideo" 2>/dev/null || true
sleep 1
xcrun simctl io "$A" recordVideo --codec h264 -f "$HAND/a.mp4" &
xcrun simctl io "$B" recordVideo --codec h264 -f "$HAND/b.mp4" &
sleep 3
[ -f "$HAND/a.mp4" ] && [ -f "$HAND/b.mp4" ] || { echo "recording did not start"; exit 1; }

xcodebuild -project XIX/XIX.xcodeproj -scheme XIX -destination "id=$A" -derivedDataPath "$DD" test-without-building \
  -only-testing:XIXUITests/PlayableLoopTests/testOwnerPlaysRound > "$HAND/owner.log" 2>&1 &
TA=$!
xcodebuild -project XIX/XIX.xcodeproj -scheme XIX -destination "id=$B" -derivedDataPath "$DD" test-without-building \
  -only-testing:XIXUITests/PlayableLoopTests/testGuestJoinsMidRound > "$HAND/guest.log" 2>&1 &
TB=$!
wait $TA; RA=$?
wait $TB; RB=$?
pkill -INT -f "simctl io .* recordVideo"; sleep 4
grep -E "Test Case .* (passed|failed)|error:" "$HAND/owner.log" "$HAND/guest.log" | sed 's/^/  /'

ffmpeg -y -loglevel error -i "$HAND/a.mp4" -i "$HAND/b.mp4" \
  -filter_complex "[0:v]scale=-2:1600[a];[1:v]scale=-2:1600[b];[a][b]hstack=inputs=2" -c:v libx264 -pix_fmt yuv420p -crf 26 "$OUT"
echo "wrote $OUT"
[ $RA -eq 0 ] && [ $RB -eq 0 ]
