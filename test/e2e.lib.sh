#!/usr/bin/env bash
set -euo pipefail

export TEST_LOG_TAG="E2E TEST"

source ${ROOT_DIR}/test/env.sh
source ${ROOT_DIR}/test/utils.sh
source ${ROOT_DIR}/test/common/k8s.sh
source ${ROOT_DIR}/test/common/kubelet.sh
source ${ROOT_DIR}/test/common/huatuo-bamai.sh

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

test_huatuo_bamai_metrics() {
	log_info "⬅️ test huatuo-bamai metrics"
	for i in {1..10}; do
		huatuo_bamai_metrics >/dev/null
		sleep 0.2
	done
	log_info "✅ test huatuo-bamai metrics ok"
}

test_huatuo_bamai_default_container_exists() {
	log_info "⬅️ test huatuo-bamai default container exists"

	assert_kubelet_pod_count \
		"${BUSINESS_POD_NS}" \
		"${BUSINESS_DEFAULT_POD_NAME_REGEX}" \
		"${BUSINESS_DEFAULT_POD_COUNT}" \
		"default pod exists in kubelet"

	assert_huatuo_bamai_pod_count \
		"${BUSINESS_DEFAULT_POD_NAME_REGEX}" \
		"${BUSINESS_DEFAULT_POD_COUNT}" \
		"default pod exists in huatuo-bamai"

	log_info "✅ test huatuo-bamai default container exists ok"
}

test_huatuo_bamai_e2e_container_create() {
	log_info "⬅️ creating e2e test pods"

	# ensure clean
	k8s_delete_pod "${BUSINESS_POD_NS}" "${BUSINESS_E2E_TEST_POD_LABEL}" || true

	assert_kubelet_pod_count \
		"${BUSINESS_POD_NS}" \
		"${BUSINESS_E2E_TEST_POD_NAME_REGEX}" \
		"0" \
		"kubelet e2e pods cleaned"

	assert_huatuo_bamai_pod_count \
		"${BUSINESS_E2E_TEST_POD_NAME_REGEX}" \
		"0" \
		"huatuo-bamai e2e pods cleaned"

	# create
	k8s_create_pod \
		"${BUSINESS_POD_NS}" \
		"${BUSINESS_E2E_TEST_POD_NAME}" \
		"${BUSINESS_POD_IMAGE}" \
		"${BUSINESS_E2E_TEST_POD_LABEL}" \
		"${BUSINESS_E2E_TEST_POD_COUNT}"

	assert_kubelet_pod_count \
		"${BUSINESS_POD_NS}" \
		"${BUSINESS_E2E_TEST_POD_NAME_REGEX}" \
		"${BUSINESS_E2E_TEST_POD_COUNT}" \
		"kubelet e2e pods created"

	assert_huatuo_bamai_pod_count \
		"${BUSINESS_E2E_TEST_POD_NAME_REGEX}" \
		"${BUSINESS_E2E_TEST_POD_COUNT}" \
		"huatuo-bamai e2e pods created"

	log_info "✅ test huatuo-bamai e2e container create ok"
}

test_huatuo_bamai_e2e_container_delete() {
	log_info "⬅️ deleting e2e test pods"

	assert_kubelet_pod_count \
		"${BUSINESS_POD_NS}" \
		"${BUSINESS_E2E_TEST_POD_NAME_REGEX}" \
		"${BUSINESS_E2E_TEST_POD_COUNT}" \
		"kubelet e2e pods exist before delete"

	assert_huatuo_bamai_pod_count \
		"${BUSINESS_E2E_TEST_POD_NAME_REGEX}" \
		"${BUSINESS_E2E_TEST_POD_COUNT}" \
		"huatuo-bamai e2e pods exist before delete"

	k8s_delete_pod "${BUSINESS_POD_NS}" "${BUSINESS_E2E_TEST_POD_LABEL}"

	assert_kubelet_pod_count \
		"${BUSINESS_POD_NS}" \
		"${BUSINESS_E2E_TEST_POD_NAME_REGEX}" \
		"0" \
		"kubelet e2e pods deleted"

	assert_huatuo_bamai_pod_count \
		"${BUSINESS_E2E_TEST_POD_NAME_REGEX}" \
		"0" \
		"huatuo-bamai e2e pods deleted"

	log_info "✅ test huatuo-bamai e2e container delete ok"
}

e2e_test_teardown() {
	local code=$?

	huatuo_bamai_stop || true
	huatuo_bamai_log_check || true

	if [[ $code -ne 0 ]]; then
		fatal "❌ test failed with exit code: $code"
	fi
}
