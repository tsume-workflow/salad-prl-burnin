#!/usr/bin/env bash
set -euo pipefail

version="${PEAKMINER_VERSION:-1.0.17}"
sha256="${PEAKMINER_SHA256:-538d805ef896495a9fc759d8ae0504db7e6b4ee8c4d19fdfe0c70635ba32a3c1}"
url="${PEAKMINER_URL:-https://github.com/peakminer/peakminer/releases/download/v${version}/peakminer-${version}-linux-x86_64}"
install_dir="${PEAKMINER_INSTALL_DIR:-/opt/peakminer}"
miner="${install_dir}/peakminer"

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

exec "$miner" "$@"
