#!/usr/bin/env bash
set -euo pipefail

version="${PEAKMINER_VERSION:-1.0.17}"
sha256="${PEAKMINER_SHA256:-538d805ef896495a9fc759d8ae0504db7e6b4ee8c4d19fdfe0c70635ba32a3c1}"
url="${PEAKMINER_URL:-https://github.com/peakminer/peakminer/releases/download/v${version}/peakminer-${version}-linux-x86_64}"
install_dir="${PEAKMINER_INSTALL_DIR:-/opt/peakminer}"
miner="${install_dir}/peakminer"
sampler="${MINER_TELEMETRY_SAMPLER:-/usr/local/bin/miner-telemetry-sampler}"

mkdir -p "$install_dir"

if [[ ! -x "$miner" ]]; then
  tmp="$(mktemp "${install_dir}/peakminer.XXXXXX")"
  trap 'rm -f "$tmp"' EXIT
  curl -fsSL "$url" -o "$tmp"
  echo "${sha256}  ${tmp}" | sha256sum -c -
  chmod +x "$tmp"
  mv "$tmp" "$miner"
  trap - EXIT
fi

if [[ "${1:-}" == "peakminer" ]]; then
  shift
fi

export MINER_KIND="${MINER_KIND:-peakminer}"
export MINER_VERSION="${MINER_VERSION:-${version}}"
export MINER_API_ENABLED="${MINER_API_ENABLED:-1}"
export MINER_API_URL="${MINER_API_URL:-http://127.0.0.1:${PEAKMINER_API_PORT:-4068}/summary}"

printf '{"event":"miner_start","schema":"miner_telemetry.v1","arm":"%s","pool":"%s","worker":"%s","miner":"peakminer","miner_version":"%s","source":"container_stdout"}\n' \
  "${AB_ARM:-}" \
  "${AB_POOL:-${PRL_POOL_ARM:-}}" \
  "${PRL_WORKER:-}" \
  "${MINER_VERSION:-${version}}"

sampler_pid=""
miner_pid=""

start_sampler() {
  case "${1:-}" in
    --version|-V|-v|--help|-h) return ;;
  esac
  if [[ -x "$sampler" && "${MINER_TELEMETRY_ENABLED:-1}" != "0" ]]; then
    "$sampler" &
    sampler_pid=$!
  fi
}

cleanup() {
  if [[ -n "$sampler_pid" ]]; then
    kill "$sampler_pid" >/dev/null 2>&1 || true
  fi
}

terminate() {
  if [[ -n "$miner_pid" ]]; then
    kill "$miner_pid" >/dev/null 2>&1 || true
  fi
  cleanup
}

trap terminate INT TERM
trap cleanup EXIT

start_sampler "${1:-}"

"$miner" "$@" &
miner_pid=$!
wait "$miner_pid"
