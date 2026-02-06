#!/usr/bin/env bash
set -euo pipefail

source ${ROOT_DIR}/test/env.sh
source ${ROOT_DIR}/test/utils.sh
source ${ROOT_DIR}/test/common/k8s.sh
source ${ROOT_DIR}/test/common/kubelet.sh
source ${ROOT_DIR}/test/common/huatuo-bamai.sh

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
