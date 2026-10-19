#!/bin/bash
# Quits the running TILE32, waits until it is gone, then starts the build in build/.
# Starting too early fails with "_LSOpenURLsWithCompletionHandler() failed with error -600".
set -euo pipefail
cd "$(dirname "$0")"

pkill -x TILE32 || true
for _ in $(seq 1 50); do
    pgrep -x TILE32 >/dev/null || break
    sleep 0.1
done
if pgrep -x TILE32 >/dev/null; then
    echo "TILE32 did not quit within 5 seconds" >&2
    exit 1
fi
open build/TILE32.app
echo "TILE32 restarted"
