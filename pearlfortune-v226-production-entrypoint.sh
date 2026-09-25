#!/bin/sh
set -eu
# Continuous PF v2.2.6 for the existing multipool; termination belongs to Salad group lifecycle.
if [ "${1:-}" = "/usr/local/bin/pearlfortune-telemetry-entrypoint" ]; then shift; fi
has_proxy=0; has_address=0; has_worker=0; has_gpu=0
for arg in "$@"; do
  case "$arg" in
    --proxy) has_proxy=1 ;;
    --address) has_address=1 ;;
    --worker) has_worker=1 ;;
    -gpu) has_gpu=1 ;;
  esac
done
if [ "$has_proxy" -ne 1 ] || [ "$has_address" -ne 1 ] || [ "$has_worker" -ne 1 ] || [ "$has_gpu" -ne 1 ]; then
  echo "required miner flags missing" >&2
  exit 64
fi
variant=${PF_CUDA_VARIANT:-cuda12}
case "$variant" in cuda12|cuda13) ;; *) echo "invalid PF_CUDA_VARIANT" >&2; exit 64;; esac
bin="/opt/pearlfortune/miner-$variant"
if [ "${PF_TEST_MODE:-}" = 1 ]; then bin=${PF_TEST_BINARY:?PF_TEST_BINARY required}; fi
if [ ! -x "$bin" ]; then echo "miner unavailable" >&2; exit 65; fi
export MINER_KIND="pearlfortune-official"
export MINER_VERSION="v2.2.6"
export MINER_API_ENABLED="0"
sampler_pid=""; miner_pid=""
cleanup() {
  if [ -n "$sampler_pid" ]; then kill "$sampler_pid" >/dev/null 2>&1 || true; fi
}
forward_term() {
  if [ -n "$miner_pid" ]; then kill -TERM "$miner_pid" >/dev/null 2>&1 || true; fi
}
trap cleanup EXIT
trap forward_term INT TERM
if [ "${MINER_TELEMETRY_ENABLED:-1}" != 0 ] && [ -x /usr/local/bin/miner-telemetry-sampler ]; then
  /usr/local/bin/miner-telemetry-sampler &
  sampler_pid=$!
fi
printf '{"event":"miner_start","schema":"miner_telemetry.v1","arm":"%s","worker":"%s","miner":"pearlfortune-official","miner_version":"v2.2.6","source":"container_stdout"}\n' \
  "${AB_ARM:-}" "${PRL_WORKER:-}"
"$bin" "$@" &
miner_pid=$!
set +e
wait "$miner_pid"
status=$?
set -e
exit "$status"
