#!/usr/bin/env bash
set -euo pipefail

source ./test/e2e.lib.sh

trap '
    huatuo_bamai_stop
    huatuo_bamai_log_check
' EXIT

huatuo_bamai_start "${HUATUO_BAMAI_ARGS_E2E[@]}"
test_huatuo_bamai_metrics
test_huatuo_bamai_default_container_exists
test_huatuo_bamai_e2e_container_create
test_huatuo_bamai_e2e_container_delete
