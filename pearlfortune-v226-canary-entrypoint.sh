#!/bin/sh
set -eu
# Inner timeout; an independently armed Salad group STOP remains mandatory.
seconds=${BURNIN_SECONDS:-900}
case "$seconds" in ""|*[!0-9]*) echo "invalid BURNIN_SECONDS" >&2; exit 64;; esac
if [ "$seconds" -lt 1 ] || [ "$seconds" -gt 900 ]; then echo "BURNIN_SECONDS must be 1..900" >&2; exit 64; fi
: "${PRL_WALLET:?PRL_WALLET required}"
: "${PRL_WORKER:?PRL_WORKER required}"
variant=${PF_CUDA_VARIANT:-cuda12}
case "$variant" in cuda12|cuda13) ;; *) echo "invalid PF_CUDA_VARIANT" >&2; exit 64;; esac
bin="/opt/pearlfortune/miner-$variant"
if [ "${PF_TEST_MODE:-}" = 1 ]; then bin=${PF_TEST_BINARY:?PF_TEST_BINARY required}; fi
if [ ! -x "$bin" ]; then echo "miner unavailable" >&2; exit 65; fi
set +e
timeout --signal=TERM --kill-after=10s "$seconds" "$bin" --proxy "${PRL_POOL_URL:-global.pearlfortune.org:443}" --address "$PRL_WALLET" --worker "$PRL_WORKER" -gpu --gpu-devices "${PF_GPU_DEVICE:-0}" --stats-interval "${PF_STATS_INTERVAL:-10s}"
status=$?
set -e
if [ "$status" -eq 124 ]; then echo "canary_hash_time_complete"; exit 0; fi
if [ "$status" -eq 0 ]; then echo "canary_miner_exited_early"; exit 0; fi
echo "canary_miner_failed status=$status" >&2
exit "$status"
