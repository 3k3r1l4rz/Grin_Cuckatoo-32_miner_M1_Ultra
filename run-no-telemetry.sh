#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -f ./miner.conf ]; then
  # shellcheck disable=SC1091
  . ./miner.conf
fi

export M1_STRATUM_HOST="${M1_STRATUM_HOST:-127.0.0.1}"
export M1_STRATUM_PORT="${M1_STRATUM_PORT:-3416}"
export M1_STRATUM_LOGIN="${M1_STRATUM_LOGIN:-m1miner}"
export M1_STRATUM_PASSWORD="${M1_STRATUM_PASSWORD:-x}"

unset M1_TELEMETRY_PATH M1_TELEMETRY_MAX_MB M1_TELEMETRY_KEEP_FILES
unset M1_STEER M1_STEER_STATE

if [ "$#" -gt 0 ]; then
  exec ./mine34_live "$@"
fi

exec ./mine34_live "${EDGE_BITS:-32}" "${ROUNDS:-160}" "${MAXGRAPHS:-0}"
