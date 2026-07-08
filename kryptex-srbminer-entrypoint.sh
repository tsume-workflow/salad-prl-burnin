#!/usr/bin/env bash
set -euo pipefail

srbminer="${SRBMINER_BIN:-/opt/srbminer/SRBMiner-MULTI}"
wallet="${PRL_WALLET:?PRL_WALLET is required}"
pool_url="${PRL_POOL_URL:-prl.kryptex.network:7048}"
worker="${PRL_WORKER:-kx-${HOSTNAME:-worker}}"
wallet_worker="${wallet}.${worker}"
algo="${PRL_ALGO:-pearlhash}"
burnin_seconds="${BURNIN_SECONDS:-0}"
gpu_id="${GPU_ID:-0}"
gpu_intensity="${GPU_INTENSITY:-16}"
gpu_off_temp="${GPU_OFF_TEMP:-81}"
post_burnin_action="${POST_BURNIN_ACTION:-idle}"
job_timeout="${SRBMINER_JOB_TIMEOUT:-120}"
log_file="${SRBMINER_LOG_FILE:-/tmp/kryptex-srbminer.log}"

log_prefixed() {
  local prefix="$1"
  sed -u "s/^/${prefix} /"
}

echo "[kryptex] starting"
echo "[kryptex] pool=${pool_url}"
echo "[kryptex] worker=${worker}"
echo "[kryptex] algo=${algo}"
echo "[kryptex] burnin_seconds=${burnin_seconds}"
echo "[kryptex] srbminer=${srbminer}"
ls -l "$srbminer" 2>&1 | log_prefixed "[kryptex][binary]" || true

if command -v ldd >/dev/null 2>&1; then
  ldd "$srbminer" 2>&1 | log_prefixed "[kryptex][ldd]" || true
else
  echo "[kryptex] ldd not found"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi 2>&1 | log_prefixed "[kryptex][nvidia-smi]" || true
else
  echo "[kryptex] nvidia-smi not found"
fi

set +e
timeout 20 "$srbminer" --list-devices 2>&1 | log_prefixed "[kryptex][devices]"
list_devices_status=${PIPESTATUS[0]}
set -e
echo "[kryptex] list_devices_status=${list_devices_status}"

mkdir -p "$(dirname "$log_file")"
touch "$log_file"

cmd=(
  "$srbminer"
  --disable-cpu
  --algorithm "$algo"
  --pool "$pool_url"
  --wallet "$wallet_worker"
  --gpu-id "$gpu_id"
  --gpu-intensity "$gpu_intensity"
  --gpu-off-temperature "$gpu_off_temp"
  --api-enable
  --api-rig-name "$worker"
  --extended-log
  --forced-tls12
  --job-timeout "$job_timeout"
  --log-file "$log_file"
  --log-file-mode 0
)

if [[ "${PRL_POOL_TLS:-0}" == "1" || "${PRL_POOL_TLS:-0}" == "true" ]]; then
  cmd+=(--tls true)
fi

if [[ -n "${SRBMINER_EXTRA_ARGS:-}" ]]; then
  # shellcheck disable=SC2206
  extra_args=( $SRBMINER_EXTRA_ARGS )
  cmd+=("${extra_args[@]}")
fi

echo "[kryptex] command=${cmd[*]/$wallet_worker/<wallet.worker>}"

if [[ "$burnin_seconds" == "0" || "$burnin_seconds" == "continuous" || "$burnin_seconds" == "infinite" ]]; then
  echo "[kryptex] continuous mode"
  set +e
  "${cmd[@]}" 2>&1 | tee -a "$log_file"
  exit_code=${PIPESTATUS[0]}
  set -e
  echo "[kryptex] miner_exit_code=${exit_code}"
  exit "$exit_code"
fi

set +e
timeout --foreground "$burnin_seconds" "${cmd[@]}" 2>&1 | tee -a "$log_file"
exit_code=${PIPESTATUS[0]}
set -e

if [[ "$exit_code" -eq 124 ]]; then
  echo "[kryptex] completed after ${burnin_seconds}s"
  if [[ "$post_burnin_action" == "exit" ]]; then
    exit 0
  fi
  echo "[kryptex] idling until container group is stopped"
  sleep infinity
  exit 0
fi

exit "$exit_code"
