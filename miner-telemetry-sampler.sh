#!/usr/bin/env sh
set -eu

interval="${MINER_TELEMETRY_INTERVAL:-60}"
miner_kind="${MINER_KIND:-${AB_ARM:-unknown}}"
api_url="${MINER_API_URL:-}"
api_file="/tmp/miner-telemetry-api.json"
gpu_file="/tmp/miner-telemetry-gpu.csv"

cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

trim() {
  printf '%s' "${1:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

json_escape() {
  printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

is_number() {
  printf '%s' "${1:-}" | grep -Eq '^-?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$'
}

json_number_or_null() {
  if is_number "${1:-}"; then
    printf '%s' "$1"
  else
    printf 'null'
  fi
}

json_bool_or_null() {
  case "${1:-}" in
    true|TRUE|1|yes|YES) printf 'true' ;;
    false|FALSE|0|no|NO) printf 'false' ;;
    *) printf 'null' ;;
  esac
}

hashrate_to_ths() {
  value="${1:-}"
  if ! is_number "$value"; then
    return
  fi
  awk -v value="$value" 'BEGIN {
    if (value > 1000000000) {
      printf "%.6f", value / 1000000000000
    } else {
      printf "%.6f", value
    }
  }'
}

api_probe() {
  rm -f "$api_file"
  if [ -z "$api_url" ]; then
    printf 'false'
    return
  fi
  if cmd_exists curl; then
    curl -fsS --max-time 3 "$api_url" -o "$api_file" 2>/dev/null && {
      printf 'true'
      return
    }
  elif cmd_exists wget; then
    wget -q -T 3 -O "$api_file" "$api_url" >/dev/null 2>&1 && {
      printf 'true'
      return
    }
  fi
  printf 'false'
}

jq_value() {
  filter="$1"
  if [ -s "$api_file" ] && cmd_exists jq; then
    jq -r "$filter // empty" "$api_file" 2>/dev/null | head -n 1
  fi
}

gpu_probe() {
  rm -f "$gpu_file"
  if ! cmd_exists nvidia-smi; then
    printf 'false'
    return
  fi
  nvidia-smi \
    --query-gpu=name,temperature.gpu,power.draw,fan.speed,clocks.mem,clocks.gr \
    --format=csv,noheader,nounits >"$gpu_file" 2>/dev/null && {
      printf 'true'
      return
    }
  nvidia-smi -L >"$gpu_file" 2>/dev/null && {
    printf 'true'
    return
  }
  printf 'false'
}

read_gpu_fields() {
  gpu_name=""
  gpu_temp=""
  gpu_power=""
  gpu_fan=""
  mem_clock=""
  core_clock=""
  if [ ! -s "$gpu_file" ]; then
    return
  fi
  first_line="$(head -n 1 "$gpu_file")"
  case "$first_line" in
    GPU\ *)
      gpu_name="$(printf '%s' "$first_line" | sed 's/^GPU [0-9][0-9]*: //; s/ (UUID:.*$//')"
      ;;
    *)
      old_ifs="$IFS"
      IFS=","
      # shellcheck disable=SC2086
      set -- $first_line
      IFS="$old_ifs"
      gpu_name="$(trim "${1:-}")"
      gpu_temp="$(trim "${2:-}")"
      gpu_power="$(trim "${3:-}")"
      gpu_fan="$(trim "${4:-}")"
      mem_clock="$(trim "${5:-}")"
      core_clock="$(trim "${6:-}")"
      ;;
  esac
}

while :; do
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date)"
  api_ok="$(api_probe)"
  gpu_ok="$(gpu_probe)"
  read_gpu_fields

  api_hashrate="$(jq_value '.hashrate // .hashrate_hs // .total_hashrate // .total_hashrate_hs')"
  api_hashrate_ths="$(hashrate_to_ths "$api_hashrate" || true)"
  api_accepted="$(jq_value '.accepted_shares // .accepted // .accepted_total // .shares.accepted')"
  api_stale="$(jq_value '.stale_shares // .stale // .stale_total // .shares.stale')"
  api_invalid="$(jq_value '.invalid_shares // .invalid // .invalid_total // .shares.invalid')"
  api_power="$(jq_value '.gpus[0].power_w // .power_w // .gpu_power_w')"
  api_temp="$(jq_value '.gpus[0].temperature_c // .temperature_c // .temp_c // .gpu_temp_c')"
  api_fan="$(jq_value '.gpus[0].fan_pct // .fan_pct // .gpu_fan_pct')"
  api_gpu_name="$(jq_value '.gpus[0].name // .gpu_name')"
  api_version="$(jq_value '.version // .miner_version')"
  api_connected="$(jq -r 'if (.pool.connected == true or .connected == true) then "true" elif (.pool.connected == false or .connected == false) then "false" else empty end' "$api_file" 2>/dev/null | head -n 1 || true)"
  api_last_share_at="$(jq_value '.last_share_at // .last_share_time')"

  if [ -n "$api_gpu_name" ]; then gpu_name="$api_gpu_name"; fi
  if [ -n "$api_power" ]; then gpu_power="$api_power"; fi
  if [ -n "$api_temp" ]; then gpu_temp="$api_temp"; fi
  if [ -n "$api_fan" ]; then gpu_fan="$api_fan"; fi

  miner_version="${MINER_VERSION:-}"
  if [ -z "$miner_version" ] && [ -n "$api_version" ]; then miner_version="$api_version"; fi

  hashrate_json="$(json_number_or_null "$api_hashrate_ths")"
  accepted_json="$(json_number_or_null "$api_accepted")"
  stale_json="$(json_number_or_null "$api_stale")"
  invalid_json="$(json_number_or_null "$api_invalid")"
  power_json="$(json_number_or_null "$gpu_power")"
  temp_json="$(json_number_or_null "$gpu_temp")"
  fan_json="$(json_number_or_null "$gpu_fan")"
  mem_clock_json="$(json_number_or_null "$mem_clock")"
  core_clock_json="$(json_number_or_null "$core_clock")"
  connected_json="$(json_bool_or_null "$api_connected")"

  printf '{"event":"miner_telemetry","schema":"miner_telemetry.v1","ts":"%s","arm":"%s","pool":"%s","worker":"%s","miner":"%s","miner_version":"%s","source":"container_stdout","pool_url":"%s","connected":%s,"job_active":null,"hashrate":%s,"hashrate_unit":"TH/s","hashrate_ths_local":%s,"hashrate_window_sec":null,"shares":%s,"accepted":%s,"accepted_delta":null,"stale":%s,"stale_delta":null,"invalid":%s,"invalid_delta":null,"last_share_at":"%s","last_error":null,"gpu_detected":%s,"gpu_name":"%s","power":%s,"power_w":%s,"temp":%s,"temperature_c":%s,"fan_pct":%s,"mem_clock_mhz":%s,"core_clock_mhz":%s,"api_enabled":%s,"api_ok":%s}\n' \
    "$(json_escape "$ts")" \
    "$(json_escape "${AB_ARM:-}")" \
    "$(json_escape "${AB_POOL:-${PRL_POOL_ARM:-}}")" \
    "$(json_escape "${PRL_WORKER:-}")" \
    "$(json_escape "$miner_kind")" \
    "$(json_escape "$miner_version")" \
    "$(json_escape "${PRL_POOL_URL:-}")" \
    "$connected_json" \
    "$hashrate_json" \
    "$hashrate_json" \
    "$accepted_json" \
    "$accepted_json" \
    "$stale_json" \
    "$invalid_json" \
    "$(json_escape "$api_last_share_at")" \
    "$(json_bool_or_null "$gpu_ok")" \
    "$(json_escape "$gpu_name")" \
    "$power_json" \
    "$power_json" \
    "$temp_json" \
    "$temp_json" \
    "$fan_json" \
    "$mem_clock_json" \
    "$core_clock_json" \
    "$(json_bool_or_null "${MINER_API_ENABLED:-0}")" \
    "$(json_bool_or_null "$api_ok")"

  sleep "$interval"
done
