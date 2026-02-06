#!/usr/bin/env bash
set -euo pipefail

source "./test/env.sh"
source "${ROOT_DIR}/test/e2e/lib.sh"
source "${ROOT_DIR}/test/e2e/container.sh"
source "${ROOT_DIR}/test/e2e/metrics.sh"

trap "
    e2e_test_teardown
" EXIT

huatuo_bamai_start "${HUATUO_BAMAI_ARGS_E2E[@]}"
test_huatuo_bamai_metrics
test_huatuo_bamai_default_container_exists
test_huatuo_bamai_e2e_container_create
test_huatuo_bamai_e2e_container_delete
