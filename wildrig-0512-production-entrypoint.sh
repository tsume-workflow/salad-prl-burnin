#!/bin/sh
set -eu
# Continuous WildRig 0.51.2 for the existing PearlHash multipool arm.
wallet=${PRL_WALLET:?PRL_WALLET required}
pool=${PRL_POOL_URL:?PRL_POOL_URL required}
worker=${PRL_WORKER:?PRL_WORKER required}
algo=${PRL_ALGO:-pearlhash}
gpu_list=${GPU_LIST:-0}
case "$gpu_list" in *[!0-9,]*|'') echo 'invalid GPU_LIST' >&2; exit 64;; esac
case "${BURNIN_SECONDS:-0}" in 0|continuous|infinite) ;; *) echo 'production image requires continuous mode' >&2; exit 64;; esac
bin=/opt/wildrig/wildrig-multi
if [ "${WILDRIG_TEST_MODE:-0}" = 1 ]; then bin=${WILDRIG_TEST_BINARY:?WILDRIG_TEST_BINARY required}; fi
if [ ! -x "$bin" ]; then echo 'miner unavailable' >&2; exit 65; fi
export MINER_KIND=wildrig MINER_VERSION=0.51.2 MINER_API_ENABLED=0
sampler_pid=; miner_pid=
cleanup() {
  if [ -n "$sampler_pid" ]; then kill "$sampler_pid" >/dev/null 2>&1 || true; fi
}
forward_term() {
  trap - INT TERM
  if [ -n "$miner_pid" ]; then
    kill -TERM "$miner_pid" >/dev/null 2>&1 || true
    wait "$miner_pid" >/dev/null 2>&1 || true
  fi
  exit 143
}
trap cleanup EXIT
trap forward_term INT TERM
if [ "${MINER_TELEMETRY_ENABLED:-1}" != 0 ] && [ -x /usr/local/bin/miner-telemetry-sampler ]; then
  /usr/local/bin/miner-telemetry-sampler &
  sampler_pid=$!
fi
printf '{"event":"miner_start","schema":"miner_telemetry.v1","arm":"%s","pool":"%s","worker":"%s","miner":"wildrig","miner_version":"0.51.2","source":"container_stdout"}\n' \
  "${AB_ARM:-}" "${AB_POOL:-pearlhash}" "$worker"
"$bin" --algo "$algo" --url "$pool" --user "$wallet.$worker" --pass x \
  --opencl-platforms nvidia --gpu-list "$gpu_list" \
  --gpu-temp-limit "${GPU_TEMP_LIMIT:-81}" --print-time "${PRINT_TIME:-30}" --no-color &
miner_pid=$!
set +e
wait "$miner_pid"
status=$?
set -e
exit "$status"
