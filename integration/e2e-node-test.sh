#!/usr/bin/env bash

# Copyright 2026 The HuaTuo Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -xeuo pipefail

export BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT=$(cd ${BASEDIR}/.. && pwd)

HUATUO_BAMAI_BIN="${ROOT}/_output/bin/huatuo-bamai"
HUATUO_BAMAI_PIDFILE="/var/run/huatuo-bamai.pid"
HUATUO_BAMAI_CONF="${ROOT}/_output/conf/huatuo-bamai.conf"
HUATUO_BAMAI_RUN_TIMEOUT=90 # seconds
HUATUO_BAMAI_LOG_FILE="/tmp/huatuo-bamai.log"
HUATUO_BAMAI_MATCH_KEYWORDS="\"error\"|panic"
HUATUO_BAMAI_ADDR="http://127.0.0.1:19704"
HUATUO_BAMAI_METRICS_API="${HUATUO_BAMAI_ADDR}/metrics"
HUATUO_BAMAI_PODS_API="${HUATUO_BAMAI_ADDR}/containers/json"

# k8s: metadata.name == pod-name, ct-hostname
# huatuo-bamai: name == ct-hostname, hostname == pod-name == metadata.name
BUSINESS_POD_NS="default"
BUSINESS_POD_IMAGE="busybox:1.36.1"
BUSINESS_DEFAULT_POD_NAME="busybox-business"
BUSINESS_DEFAULT_POD_NAME_REGEX="^${BUSINESS_DEFAULT_POD_NAME}$"
BUSINESS_DEFAULT_POD_COUNT=1 # default only one pod
BUSINESS_E2E_TEST_POD_NAME="business-e2e-test"
BUSINESS_E2E_TEST_POD_NAME_REGEX="^${BUSINESS_E2E_TEST_POD_NAME}-([0-9]+)?$"
BUSINESS_E2E_TEST_POD_LABEL="app=${BUSINESS_E2E_TEST_POD_NAME}"
BUSINESS_E2E_TEST_POD_COUNT=2

KUBELET_PODS_API="https://127.0.0.1:10250/pods"
KUBELET_CERT="/var/lib/kubelet/pki/kubelet-client-current.pem"
KUBELET_KEY="/var/lib/kubelet/pki/kubelet-client-current.pem"

CURL_TIMEOUT=(
	"--connect-timeout" "2"
	"--max-time" "3"
)

log_info() {
	echo "[E2E TEST] $*"
}

log_warn() {
	echo "[E2E TEST][WARN] $*" >&2
}

log_error_exit() {
	echo "[E2E TEST][ERROR] $*" >&2
	exit 1
}

prepare_test_env() {
	rm -f ${HUATUO_BAMAI_PIDFILE} ${HUATUO_BAMAI_LOG_FILE}
	kill -9 $(pidof huatuo-bamai) 2>/dev/null || true
}

setup_huatuo_bamai() {
	mkdir -p $(dirname ${HUATUO_BAMAI_LOG_FILE})
	timeout -s SIGINT ${HUATUO_BAMAI_RUN_TIMEOUT}s \
		${HUATUO_BAMAI_BIN} \
		--region e2e-node \
		--disable-storage \
		--config-dir ${ROOT}/_output/conf/ \
		--config huatuo-bamai.conf \
		>${HUATUO_BAMAI_LOG_FILE} 2>&1 &
}

wait_huatuo_bamai_ok() {
	local timeout=$((HUATUO_BAMAI_RUN_TIMEOUT / 4))
	local interval=2 # seconds

	for ((i = 1; i <= timeout; i += interval)); do
		if curl -sf "${CURL_TIMEOUT[@]}" ${HUATUO_BAMAI_METRICS_API} >/dev/null; then
			return 0
		fi
		sleep ${interval}
	done

	log_error_exit "❌ huatuo-bamai not running after ${timeout}s"
}

test_metrics() {
	local count=10
	for ((i = 1; i <= count; i += 1)); do
		curl -sf "${CURL_TIMEOUT[@]}" ${HUATUO_BAMAI_METRICS_API} 2>&1 >/dev/null || true
		sleep 0.5
	done
}

check_huatuo_bamai_log() {
	# print colored log and check if contains keywords
	sed -E "s/(${HUATUO_BAMAI_MATCH_KEYWORDS})/\x1b[31m\1\x1b[0m/gI" ${HUATUO_BAMAI_LOG_FILE}
	! grep -qE "${HUATUO_BAMAI_MATCH_KEYWORDS}" ${HUATUO_BAMAI_LOG_FILE}
}

kubelet_pods_json() {
	curl -sk "${CURL_TIMEOUT[@]}" \
		--cert ${KUBELET_CERT} \
		--key ${KUBELET_KEY} \
		--header "Content-Type: application/json" \
		${KUBELET_PODS_API}
}

kubelet_pod_count() {
	local ns=$1
	local regex=$2
	kubelet_pods_json |
		jq --arg ns "$ns" --arg re "$regex" '
        [ .items[]
          | select(.metadata.namespace == $ns)
          | select(.metadata.name | test($re))
          | select(.status.phase == "Running")
        ] | length
        ' 2>/dev/null || echo 0
}

huatuo_bamai_pod_count() {
	local regex=$1
	curl -sf "${CURL_TIMEOUT[@]}" ${HUATUO_BAMAI_PODS_API} |
		jq --arg re "$regex" '
      [ .[]
        | select(.hostname != null)
        | select(.hostname | test($re))
      ] | length
    ' 2>/dev/null || echo 0
}

wait_kubelet_pod_count() {
	local ns=$1
	local regex=$2
	local expect=$3
	local timeout=$((HUATUO_BAMAI_RUN_TIMEOUT / 2))
	local interval=2
	local cnt=0
	for ((i = 0; i < timeout; i += interval)); do
		cnt=$(kubelet_pod_count ${ns} ${regex})
		if [[ "$cnt" -eq "$expect" ]]; then
			return 0
		fi
		sleep ${interval}
	done

	kubelet_pods_json || true
	log_error_exit "❌ kubelet [${ns}] [${regex}] expect=${expect}, actual=${cnt}"
}

wait_huatuo_bamai_pod_count() {
	local regex=$1
	local expect=$2
	local timeout=$((HUATUO_BAMAI_RUN_TIMEOUT / 2))
	local interval=2
	local cnt=0
	for ((i = 0; i < timeout; i += interval)); do
		cnt=$(huatuo_bamai_pod_count ${regex})

		if [[ "$cnt" -eq "$expect" ]]; then
			return 0
		fi
		sleep ${interval}
	done

	curl -sf "${CURL_TIMEOUT[@]}" ${HUATUO_BAMAI_PODS_API} | jq .
	log_error_exit "❌ huatuo-bamai [${regex}] expect=${expect}, actual=${cnt}"
}

# if not exists, not exit
test_container_exists() {
	local cnt=$(huatuo_bamai_pod_count ${BUSINESS_DEFAULT_POD_NAME_REGEX})
	if [[ "$cnt" -ne "${BUSINESS_DEFAULT_POD_COUNT}" ]]; then
		log_warn "⚠️ huatuo-bamai default business pod expect=${BUSINESS_DEFAULT_POD_COUNT}, actual=${cnt}"
		return 0
	fi
}

test_container_create() {
	# clean up
	kubectl delete pod -n ${BUSINESS_POD_NS} -l ${BUSINESS_E2E_TEST_POD_LABEL} 2>/dev/null || true
	wait_kubelet_pod_count ${BUSINESS_POD_NS} ${BUSINESS_E2E_TEST_POD_NAME_REGEX} 0
	wait_huatuo_bamai_pod_count ${BUSINESS_E2E_TEST_POD_NAME_REGEX} 0
	kubectl get pods -A || true
	log_info "✔ clean e2e-test business pods ok"

	# create business pod
	for i in $(seq 1 ${BUSINESS_E2E_TEST_POD_COUNT}); do
		kubectl run "${BUSINESS_E2E_TEST_POD_NAME}-${i}" \
			-n ${BUSINESS_POD_NS} \
			--image=${BUSINESS_POD_IMAGE} \
			--restart=Never \
			--labels ${BUSINESS_E2E_TEST_POD_LABEL} \
			-- sleep 3600
	done

	# check
	wait_kubelet_pod_count ${BUSINESS_POD_NS} ${BUSINESS_E2E_TEST_POD_NAME_REGEX} ${BUSINESS_E2E_TEST_POD_COUNT}
	kubectl get pods -A || true
	log_info "✔ k8s e2e-test business pods ${BUSINESS_E2E_TEST_POD_COUNT} created"
	wait_huatuo_bamai_pod_count ${BUSINESS_E2E_TEST_POD_NAME_REGEX} ${BUSINESS_E2E_TEST_POD_COUNT}
}

test_container_delete() {
	if [[ "$(kubelet_pod_count ${BUSINESS_POD_NS} ${BUSINESS_E2E_TEST_POD_NAME_REGEX})" -eq 0 ]]; then
		kubectl get pods -A
		log_error_exit "❌ no e2e-test business pods exists in kubelet"
	fi

	wait_huatuo_bamai_pod_count ${BUSINESS_E2E_TEST_POD_NAME_REGEX} ${BUSINESS_E2E_TEST_POD_COUNT}
	log_info "✔ huatuo-bamai has e2e-test business pods ${BUSINESS_E2E_TEST_POD_COUNT}"

	# delete all e2e-test business pods
	kubectl delete pod -n ${BUSINESS_POD_NS} -l ${BUSINESS_E2E_TEST_POD_LABEL}
	log_info "✔ e2e-test business pods deleted in k8s"

	wait_kubelet_pod_count ${BUSINESS_POD_NS} ${BUSINESS_E2E_TEST_POD_NAME_REGEX} 0
	log_info "✔ e2e-test business pods deleted in kubelet"
	wait_huatuo_bamai_pod_count ${BUSINESS_E2E_TEST_POD_NAME_REGEX} 0
}

prepare_test_env

# defer
trap '
    log_info "dumping huatuo-bamai log..."
    check_huatuo_bamai_log
' EXIT

setup_huatuo_bamai
wait_huatuo_bamai_ok
log_info "✅ huatuo-bamai server ok"

test_metrics

# Test container management:
# - There is exactly ${BUSINESS_DEFAULT_POD_COUNT} default running in the cluster by default.
#   busybox-business   1/1     Running   1 (18h ago)   11d

# Case 1: Existing Container
# - Verify huatuo-bamai can observe existing container.

# Case 2: Create Container
# - Create ${BUSINESS_E2E_TEST_POD_COUNT} pods, named "${BUSINESS_E2E_TEST_POD_NAME}-${i}".
# - Verify both kubelet and huatuo-bamai report the containers correctly.

# Case 3: Delete Container
# - Delete the ${BUSINESS_E2E_TEST_POD_COUNT} pods by label "${BUSINESS_E2E_TEST_POD_LABEL}".
# - Verify both kubelet and huatuo-bamai no longer report the container.
log_info "⬅️ test_container_exists..."
test_container_exists
log_info "✅ test_container_exists ok"

log_info "⬅️ test_container_create..."
test_container_create
log_info "✅ test_container_create ok"

log_info "⬅️ test_container_delete..."
test_container_delete
log_info "✅ test_container_delete ok"

sleep 10 # wait more logs
kill -9 $(pidof huatuo-bamai) 2>/dev/null || true
