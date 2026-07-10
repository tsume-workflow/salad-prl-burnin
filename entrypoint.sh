#!/usr/bin/env bash
set -euo pipefail

wildrig="${WILDRIG_BIN:-/opt/wildrig/wildrig-multi}"
wallet="${PRL_WALLET:?PRL_WALLET is required}"
pool_url="${PRL_POOL_URL:-pool.pearlhash.xyz:9000}"
worker="${PRL_WORKER:-salad-${HOSTNAME:-worker}}"
algo="${PRL_ALGO:-pearlhash}"
burnin_seconds="${BURNIN_SECONDS:-1200}"
gpu_temp_limit="${GPU_TEMP_LIMIT:-81}"
print_time="${PRINT_TIME:-30}"
post_burnin_action="${POST_BURNIN_ACTION:-idle}"
sampler="${MINER_TELEMETRY_SAMPLER:-/usr/local/bin/miner-telemetry-sampler}"

export MINER_KIND="${MINER_KIND:-wildrig}"
export MINER_VERSION="${MINER_VERSION:-${WILDRIG_VERSION:-0.49.3}}"
export MINER_API_ENABLED="${MINER_API_ENABLED:-0}"

echo "[burnin] starting"
echo "[burnin] pool=${pool_url}"
echo "[burnin] worker=${worker}"
echo "[burnin] algo=${algo}"
echo "[burnin] burnin_seconds=${burnin_seconds}"
echo "[burnin] wildrig=$("$wildrig" --version 2>&1 | tr '\n' ' ')"

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi || true
else
  echo "[burnin] nvidia-smi not found"
fi

sampler_pid=""
if [[ -x "$sampler" && "${MINER_TELEMETRY_ENABLED:-1}" != "0" ]]; then
  "$sampler" &
  sampler_pid=$!
fi

cleanup() {
  if [[ -n "$sampler_pid" ]]; then
    kill "$sampler_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

cmd=(
  "$wildrig"
  --algo "$algo"
  --url "$pool_url"
  --user "${wallet}.${worker}"
  --pass x
  --opencl-platforms nvidia
  --opencl-devices 0
  --gpu-temp-limit "$gpu_temp_limit"
  --print-time "$print_time"
  --no-color
)

if [[ -n "${WILDRIG_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra_args=( $WILDRIG_EXTRA_ARGS )
  cmd+=("${extra_args[@]}")
fi

echo "[burnin] command=${cmd[*]/$wallet/<wallet>}"

if [[ "$burnin_seconds" == "0" || "$burnin_seconds" == "continuous" || "$burnin_seconds" == "infinite" ]]; then
  echo "[burnin] continuous mode"
  "${cmd[@]}"
  exit_code=$?
  echo "[burnin] miner_exit_code=${exit_code}"
  exit "$exit_code"
fi

set +e
timeout --foreground "$burnin_seconds" "${cmd[@]}"
exit_code=$?
set -e

if [[ "$exit_code" -eq 124 ]]; then
  echo "[burnin] completed after ${burnin_seconds}s"
  if [[ "$post_burnin_action" == "exit" ]]; then
    exit 0
  fi
  echo "[burnin] idling until container group is stopped"
  sleep infinity
  exit 0
fi

exit "$exit_code"
