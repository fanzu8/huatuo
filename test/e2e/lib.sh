#!/usr/bin/env bash
set -euo pipefail

export TEST_LOG_TAG="E2E TEST"

source ${ROOT_DIR}/test/env.sh
source ${ROOT_DIR}/test/common/utils.sh
source ${ROOT_DIR}/test/common/huatuo-bamai.sh
source ${ROOT_DIR}/test/e2e/common/kubelet.sh

assert_kubelet_pod_count() {
	local ns=$1 regex=$2 expect=$3 desc=${4:-"kubelet pod count"}

	_assert() {
		local actual
		actual="$(kubelet_pod_count "$ns" "$regex")"
		assert_eq "$actual" "$expect" "$desc"
	}

	wait_until \
		"$((WAIT_HUATUO_BAMAI_TIMEOUT / 2))" \
		"${WAIT_HUATUO_BAMAI_INTERVAL}" \
		"$desc" \
		_assert
}

assert_huatuo_bamai_pod_count() {
	local regex=$1 expect=$2 desc=${3:-"huatuo-bamai pod count"}
	_assert() {
		local actual
		actual="$(huatuo_bamai_pod_count "$regex")"
		assert_eq "$actual" "$expect" "$desc"
	}

	wait_until \
		"$((WAIT_HUATUO_BAMAI_TIMEOUT / 2))" \
		"${WAIT_HUATUO_BAMAI_INTERVAL}" \
		"$desc" \
		_assert
}

e2e_test_teardown() {
	local code=$?

	huatuo_bamai_stop || true
	huatuo_bamai_log_check || true

	if [[ $code -ne 0 ]]; then
		fatal "❌ test failed with exit code: $code"
	fi
}
