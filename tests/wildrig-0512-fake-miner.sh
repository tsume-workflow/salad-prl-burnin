#!/bin/sh
printf "%s\n" "$@" > "${WILDRIG_TEST_ARGS_FILE:-/tmp/wildrig-args}"
trap 'printf "%s\n" term > "${WILDRIG_TEST_TERM_FILE:-/tmp/wildrig-term}"; exit 0' TERM
while :; do sleep 1 & wait $! || :; done
