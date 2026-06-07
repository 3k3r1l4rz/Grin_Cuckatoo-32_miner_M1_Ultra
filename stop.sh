#!/usr/bin/env bash
# =============================================================================
# stop.sh -- stop the headless Grin miner started by start.sh.
#
# Sends SIGTERM to the supervisor PID (from miner.pid). The supervisor's trap
# kills the live mine34_live child and removes the pidfile. Escalates to
# SIGKILL if it does not exit, then sweeps any orphaned mine34_live.
# =============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PIDFILE="$SCRIPT_DIR/miner.pid"
BIN="$SCRIPT_DIR/mine34_live"

if [ ! -f "$PIDFILE" ]; then
  echo "No pidfile ($PIDFILE) -- miner does not appear to be running."
else
  PID="$(cat "$PIDFILE" 2>/dev/null)"
  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    echo "Stopping supervisor pid $PID ..."
    kill -TERM "$PID" 2>/dev/null
    # Wait up to ~10s for a clean shutdown.
    for _ in $(seq 1 20); do
      kill -0 "$PID" 2>/dev/null || break
      sleep 0.5
    done
    if kill -0 "$PID" 2>/dev/null; then
      echo "Did not exit; sending SIGKILL."
      kill -KILL "$PID" 2>/dev/null
    fi
    echo "Stopped."
  else
    echo "Pidfile present but pid ${PID:-?} is not alive (stale)."
  fi
  rm -f "$PIDFILE"
fi

# Safety sweep: kill any leftover mine34_live (e.g. from a crashed supervisor).
LEFT="$(pgrep -f "$BIN" 2>/dev/null || true)"
if [ -n "$LEFT" ]; then
  echo "Sweeping orphaned mine34_live: $LEFT"
  # shellcheck disable=SC2086
  kill -TERM $LEFT 2>/dev/null
  sleep 1
  LEFT="$(pgrep -f "$BIN" 2>/dev/null || true)"
  # shellcheck disable=SC2086
  [ -n "$LEFT" ] && kill -KILL $LEFT 2>/dev/null
fi
echo "Done."
