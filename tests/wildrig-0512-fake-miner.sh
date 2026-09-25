#!/bin/sh
test "$(stat -Lc %F /proc/self/fd/0)" = fifo || { echo 'stdin must be FIFO for libuv' >&2; exit 70; }
printf "%s\n" fifo > "${WILDRIG_TEST_STDIN_FILE:-/tmp/wildrig-stdin-kind}"
printf "%s\n" "$@" > "${WILDRIG_TEST_ARGS_FILE:-/tmp/wildrig-args}"
trap 'printf "%s\n" term > "${WILDRIG_TEST_TERM_FILE:-/tmp/wildrig-term}"; exit 0' TERM
while :; do sleep 1 & wait $! || :; done
