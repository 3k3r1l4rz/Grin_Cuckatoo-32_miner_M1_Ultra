#!/usr/bin/env bash
# =============================================================================
# start.sh -- preflight + launch the standalone Grin C32 miner (mine34_live).
#
#   ./start.sh        run headless (detached, nohup, pidfile, timestamped log)
#   ./start.sh -f     run in the foreground (live console; Ctrl-C to stop)
#   ./start.sh -h     help
#
# Sources miner.conf, builds the binary if missing, checks the node is
# reachable (warns but still launches), and supervises the process.
#
# Internal:  ./start.sh --supervise   (re-exec'd by the detached launch; the
#            one and only supervisor loop -- do not call directly.)
# =============================================================================
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || { echo "FATAL: cannot cd to $SCRIPT_DIR"; exit 1; }

CONF="$SCRIPT_DIR/miner.conf"
BIN="$SCRIPT_DIR/mine34_live"
PIDFILE="$SCRIPT_DIR/miner.pid"

# --- load config (plain source; NO allexport -- see M1_STEER handling) -------
load_config() {
  if [ -f "$CONF" ]; then
    # shellcheck disable=SC1090
    . "$CONF"
  else
    echo "WARN: $CONF not found -- using in-binary defaults." >&2
  fi
  EDGE_BITS="${EDGE_BITS:-32}"
  ROUNDS="${ROUNDS:-160}"
  MAXGRAPHS="${MAXGRAPHS:-0}"
  AUTO_RESTART="${AUTO_RESTART:-1}"
  RESTART_DELAY="${RESTART_DELAY:-10}"
  PTY_LOG="${PTY_LOG:-1}"
  LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"

  # Always-safe stratum vars (binary has defaults for all four).
  export M1_STRATUM_HOST="${M1_STRATUM_HOST:-127.0.0.1}"
  export M1_STRATUM_PORT="${M1_STRATUM_PORT:-3416}"
  export M1_STRATUM_LOGIN="${M1_STRATUM_LOGIN:-m1miner}"
  export M1_STRATUM_PASSWORD="${M1_STRATUM_PASSWORD:-x}"

  # "Presence == behavior" vars: the binary turns the feature ON if the var
  # merely EXISTS (even empty). Export only when non-empty; otherwise UNSET to
  # scrub any value inherited from the parent environment.
  if [ -n "${M1_STEER:-}" ]; then
    export M1_STEER
    if [ -n "${M1_STEER_STATE:-}" ]; then export M1_STEER_STATE; else unset M1_STEER_STATE; fi
  else
    unset M1_STEER M1_STEER_STATE
  fi
  if [ -n "${M1_TELEMETRY_PATH:-}" ]; then
    export M1_TELEMETRY_PATH
    export M1_TELEMETRY_MAX_MB="${M1_TELEMETRY_MAX_MB:-256}"
    export M1_TELEMETRY_KEEP_FILES="${M1_TELEMETRY_KEEP_FILES:-4}"
  else
    unset M1_TELEMETRY_PATH M1_TELEMETRY_MAX_MB M1_TELEMETRY_KEEP_FILES
  fi
}

# --- the one supervisor loop (shared by fg, bg, and --supervise re-exec) ------
# Launches the miner, waits, optionally restarts. A TERM/INT trap kills the
# live child (and, under PTY_LOG, any mine34_live grandchild left behind by the
# `script` wrapper) and removes the pidfile, so shutdown is always clean.
run_supervised() {
  local child=
  term() {
    if [ -n "$child" ]; then
      kill "$child" 2>/dev/null
      # Under `script`, $child is the `script` PID; reap the miner under it too.
      pkill -TERM -P "$child" 2>/dev/null
    fi
    pkill -TERM -f "$BIN" 2>/dev/null
    rm -f "$PIDFILE"
    exit 0
  }
  trap term TERM INT
  while : ; do
    if [ "$PTY_LOG" = "1" ] && command -v script >/dev/null 2>&1; then
      # macOS `script` forces a pty -> line-buffered, real-time log.
      script -q /dev/null "$BIN" "$EDGE_BITS" "$ROUNDS" "$MAXGRAPHS" >>"$LOG" 2>&1 &
    else
      "$BIN" "$EDGE_BITS" "$ROUNDS" "$MAXGRAPHS" >>"$LOG" 2>&1 &
    fi
    child=$!
    wait "$child"
    [ "$AUTO_RESTART" = "1" ] || break
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] miner exited; restarting in ${RESTART_DELAY}s" >>"$LOG"
    sleep "$RESTART_DELAY"
  done
  pkill -TERM -f "$BIN" 2>/dev/null
  rm -f "$PIDFILE"
}

# =============================================================================
# Re-exec entry: the detached launch calls `start.sh --supervise`. LOG comes in
# via the environment so we don't re-derive a timestamp. This is the single
# code path that actually runs the miner -- no duplicated quoted heredoc.
# =============================================================================
if [ "${1:-}" = "--supervise" ]; then
  load_config
  LOG="${MINER_LOG:?--supervise requires MINER_LOG}"
  run_supervised
  exit 0
fi

# --- normal CLI --------------------------------------------------------------
FOREGROUND=0
case "${1:-}" in
  -f|--foreground) FOREGROUND=1 ;;
  -h|--help)
    awk 'NR>1 && /^# ={10,}/{n++; if(n==2) exit} n==1 && NR>2 {sub(/^# ?/,""); print}' "$SCRIPT_DIR/start.sh"
    exit 0 ;;
  "" ) : ;;
  * ) echo "Unknown option: $1 (use -f for foreground, -h for help)"; exit 2 ;;
esac

load_config

# --- preflight: binary exists, else build ------------------------------------
if [ ! -x "$BIN" ]; then
  echo "Binary missing -- building with make..."
  if ! make -C "$SCRIPT_DIR"; then
    echo "FATAL: build failed."; exit 1
  fi
fi
[ -x "$BIN" ] || { echo "FATAL: $BIN still not present after build."; exit 1; }

# --- preflight: node reachable (warn-only; does NOT block launch) ------------
# BSD nc (/usr/bin/nc): -z scan only, -G connect timeout (seconds).
if command -v nc >/dev/null 2>&1; then
  if nc -z -G 3 "$M1_STRATUM_HOST" "$M1_STRATUM_PORT" >/dev/null 2>&1; then
    echo "OK: node reachable at $M1_STRATUM_HOST:$M1_STRATUM_PORT"
  else
    echo "WARN: cannot reach $M1_STRATUM_HOST:$M1_STRATUM_PORT -- is the grin node up?"
    echo "      Launching anyway; the miner exits on stratum-login failure."
    if [ "$AUTO_RESTART" = "1" ]; then
      echo "      AUTO_RESTART=1: it will retry every ${RESTART_DELAY}s until the node returns."
    else
      echo "      AUTO_RESTART=0: it will exit immediately and NOT retry."
    fi
  fi
else
  echo "WARN: nc not found; skipping node reachability check."
fi

# --- double-start guard ------------------------------------------------------
if [ -f "$PIDFILE" ]; then
  OLD="$(cat "$PIDFILE" 2>/dev/null)"
  if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
    echo "Already running (pid $OLD). Use ./stop.sh first."; exit 1
  fi
  echo "Clearing stale pidfile (pid ${OLD:-?} not alive)."
  rm -f "$PIDFILE"
fi

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/miner-$(date +%Y%m%d-%H%M%S).log"

echo "Config: C$EDGE_BITS rounds=$ROUNDS maxgraphs=$MAXGRAPHS  steer=${M1_STEER:-OFF}  telemetry=${M1_TELEMETRY_PATH:-OFF}"

if [ "$FOREGROUND" = "1" ]; then
  echo "Foreground mode. Logging to: $LOG  (Ctrl-C to stop)"
  echo "$$" > "$PIDFILE"
  run_supervised
else
  # Detached, immune to hangup. Re-exec ourselves as the supervisor; capture
  # ITS pid (not $$) into the pidfile, race-free -- no poll loop needed.
  MINER_LOG="$LOG" nohup "$SCRIPT_DIR/start.sh" --supervise >/dev/null 2>&1 &
  SUP=$!
  echo "$SUP" > "$PIDFILE"
  disown 2>/dev/null || true
  echo "Started headless. pid=$SUP"
  echo "Log:  $LOG"
  echo "Tail: tail -f \"$LOG\""
  echo "Stop: $SCRIPT_DIR/stop.sh"
fi
