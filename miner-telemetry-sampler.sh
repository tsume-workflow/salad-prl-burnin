#!/usr/bin/env sh
set -eu

interval="${MINER_TELEMETRY_INTERVAL:-60}"
miner_kind="${MINER_KIND:-${AB_ARM:-unknown}}"
api_url="${MINER_API_URL:-}"

json_escape() {
  printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_bool() {
  case "${1:-}" in
    1|true|TRUE|yes|YES) printf 'true' ;;
    *) printf 'false' ;;
  esac
}

cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

api_probe() {
  if [ -z "$api_url" ]; then
    printf 'false'
    return
  fi
  if cmd_exists curl; then
    curl -fsS --max-time 3 "$api_url" >/tmp/miner-telemetry-api.json 2>/dev/null && {
      printf 'true'
      return
    }
  elif cmd_exists wget; then
    wget -q -T 3 -O /tmp/miner-telemetry-api.json "$api_url" >/dev/null 2>&1 && {
      printf 'true'
      return
    }
  fi
  printf 'false'
}

gpu_probe() {
  if ! cmd_exists nvidia-smi; then
    printf 'false'
    return
  fi
  nvidia-smi -L >/tmp/miner-telemetry-gpu.txt 2>/dev/null && {
    printf 'true'
    return
  }
  printf 'false'
}

while :; do
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
  api_ok="$(api_probe)"
  gpu_ok="$(gpu_probe)"
  gpu_name=""
  if [ -s /tmp/miner-telemetry-gpu.txt ]; then
    gpu_name="$(head -n 1 /tmp/miner-telemetry-gpu.txt | sed 's/^GPU [0-9][0-9]*: //; s/ (UUID:.*$//')"
  fi

  printf '{"event":"miner_telemetry","schema":"miner_telemetry.v1","ts":"%s","arm":"%s","pool":"%s","worker":"%s","miner":"%s","miner_version":"%s","source":"container_stdout","pool_url":"%s","connected":null,"job_active":null,"hashrate_ths_local":null,"accepted_delta":null,"stale_delta":null,"invalid_delta":null,"last_share_at":null,"last_error":null,"gpu_detected":%s,"gpu_name":"%s","api_enabled":%s,"api_ok":%s}\n' \
    "$(json_escape "$ts")" \
    "$(json_escape "${AB_ARM:-}")" \
    "$(json_escape "${AB_POOL:-${PRL_POOL_ARM:-}}")" \
    "$(json_escape "${PRL_WORKER:-}")" \
    "$(json_escape "$miner_kind")" \
    "$(json_escape "${MINER_VERSION:-}")" \
    "$(json_escape "${PRL_POOL_URL:-}")" \
    "$(json_bool "$gpu_ok")" \
    "$(json_escape "$gpu_name")" \
    "$(json_bool "${MINER_API_ENABLED:-0}")" \
    "$(json_bool "$api_ok")"

  sleep "$interval"
done
