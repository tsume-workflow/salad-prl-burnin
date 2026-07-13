#!/usr/bin/env sh
set -eu

sampler="${MINER_TELEMETRY_SAMPLER:-/usr/local/bin/miner-telemetry-sampler}"

export MINER_KIND="${MINER_KIND:-pearlfortune-official}"
export MINER_VERSION="${MINER_VERSION:-v1.2.4}"
export MINER_API_ENABLED="${MINER_API_ENABLED:-0}"

sampler_pid=""
if [ -x "$sampler" ] && [ "${MINER_TELEMETRY_ENABLED:-1}" != "0" ]; then
  "$sampler" &
  sampler_pid=$!
fi

cleanup() {
  if [ -n "$sampler_pid" ]; then
    kill "$sampler_pid" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

printf '{"event":"miner_start","schema":"miner_telemetry.v1","arm":"%s","pool":"%s","worker":"%s","miner":"pearlfortune-official","miner_version":"%s","source":"container_stdout"}\n' \
  "${AB_ARM:-}" \
  "${AB_POOL:-${PRL_POOL_ARM:-}}" \
  "${PRL_WORKER:-}" \
  "${MINER_VERSION:-v1.2.4}"

if [ "${1:-}" = "/usr/local/bin/pearlfortune-telemetry-entrypoint" ] || [ "${1:-}" = "/app/entrypoint.sh" ]; then
  shift
fi

/app/entrypoint.sh "$@"
