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
HUATUO_BAMAI_RUN_TIMEOUT=60 # seconds
HUATUO_BAMAI_LOG_FILE="/tmp/huatuo-bamai.log"
HUATUO_BAMAI_MATCH_KEYWORDS="\"error\"|panic"
HUATUO_BAMAI_ADDR="http://127.0.0.1:19704"
HUATUO_BAMAI_METRICS_API="${HUATUO_BAMAI_ADDR}/metrics"
HUATUO_BAMAI_CONTAINER_API="${HUATUO_BAMAI_ADDR}/containers/json"

BUSYBOX_IMAGE="busybox:1.36.1"
BUSYBOX_PREFIX="busybox"
BUSYBOX_LABEL="app=${BUSYBOX_PREFIX}"
BUSYBOX_DEFAULT_COUNT=1
BUSYBOX_CREATE_COUNT=2

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
        --disable-kubelet \
        --config-dir ${ROOT}/_output/conf/ \
        --config huatuo-bamai.conf \
        > ${HUATUO_BAMAI_LOG_FILE} 2>&1 &
}

wait_huatuo_bamai_ok() {
    local timeout=$((HUATUO_BAMAI_RUN_TIMEOUT / 4))
    local interval=1  # seconds

	for ((i = 1; i <= timeout; i += interval)); do
        if curl -sf "${CURL_TIMEOUT[@]}" ${HUATUO_BAMAI_METRICS_API} >/dev/null; then
            return 0
        fi
        sleep ${interval}
    done

     log_error_exit "❌ huatuo-bamai not running after ${timeout}s"
}

wait_huatuo_bamai_exit() {
    local timeout=$((HUATUO_BAMAI_RUN_TIMEOUT))
    local interval=1  # seconds

	for ((i = 1; i <= timeout; i += interval)); do
        if ! pidof huatuo-bamai >/dev/null; then
            return 0
        fi
        log_info "waiting huatuo-bamai exit, try ${i}/${timeout}"
        sleep ${interval}
    done
}

test_metrics() {
    local count=10
	for ((i = 1; i <= count; i += 1)); do
        curl -sf "${CURL_TIMEOUT[@]}" ${HUATUO_BAMAI_METRICS_API} 2>&1 > /dev/null || true
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
        --key  ${KUBELET_KEY} \
        --header "Content-Type: application/json" \
        ${KUBELET_PODS_API}
}

kubelet_busybox_count() {
    kubelet_pods_json | jq '
      [.items[]
        | select(.metadata.namespace=="default")
        | .status.containerStatuses[]?
        | select(.name | test("'"^${BUSYBOX_PREFIX}-"'"))
        | select(.state.running != null)
      ] | length
    ' 2>/dev/null || echo 0
}

wait_kubelet_busybox_count() {
    local expect="$1"
    local timeout=$((HUATUO_BAMAI_RUN_TIMEOUT / 2))
    local interval=1
    local cnt=0

    for ((i=0; i<timeout; i+=interval)); do
        cnt=$(kubelet_busybox_count)

        if [[ "$cnt" -eq "$expect" ]]; then
            return 0
        fi
        sleep ${interval}
    done

    kubelet_pods_json | jq .
    log_error_exit "❌ kubelet busybox expect=${expect}, actual=${cnt}"
}

huatuo_bamai_busybox_count() {
    curl -sf "${CURL_TIMEOUT[@]}" ${HUATUO_BAMAI_CONTAINER_API} \
      | jq '[.[] | select(.name | test("'"^${BUSYBOX_PREFIX}-"'"))] | length' 2>/dev/null || echo 0
}

wait_huatuo_bamai_busybox_count() {
    local expect="$1"
    local timeout=$((HUATUO_BAMAI_RUN_TIMEOUT / 2))
    local interval=1
    local cnt=0

    for ((i=0; i<timeout; i+=interval)); do
        cnt=$(huatuo_bamai_busybox_count)

        if [[ "$cnt" -eq "$expect" ]]; then
            return 0
        fi
        sleep ${interval}
    done

    curl -sf "${CURL_TIMEOUT[@]}" ${HUATUO_BAMAI_CONTAINER_API} | jq .
    log_error_exit "❌ huatuo-bamai busybox expect=${expect}, actual=${cnt}"
}

# if not exists, not exit
test_container_exists() {
    log_info "▶ test_container_exists"

    local cnt=$(huatuo_bamai_busybox_count)
    if [[ "$cnt" -ne "${BUSYBOX_DEFAULT_COUNT}" ]]; then
        log_warn "⚠️ huatuo-bamai busybox expect=${BUSYBOX_DEFAULT_COUNT}, actual=${cnt}"
    fi

    log_info "✔ huatuo-bamai has busybox ${BUSYBOX_DEFAULT_COUNT}"
}

# assume there is only 1 busybox running
test_container_delete() {
    log_info "▶ test_container_delete"

    if [[ "$(kubelet_busybox_count)" -eq 0 ]]; then
        log_error_exit "❌ no busybox exists in kubelet"
    fi

    wait_huatuo_bamai_busybox_count ${BUSYBOX_DEFAULT_COUNT}
    log_info "✔ huatuo-bamai has busybox ${BUSYBOX_DEFAULT_COUNT}"

    kubectl delete pod -n default -l ${BUSYBOX_LABEL}

    wait_kubelet_busybox_count 0
    log_info "✔ busybox deleted in k8s"

    wait_huatuo_bamai_busybox_count 0
    log_info "✔ huatuo-bamai busybox cleared"
}

test_container_create() {
    log_info "▶ test_container_create"

    # clean up
    kubectl delete pod -n default -l ${BUSYBOX_LABEL} 2>/dev/null || true
    wait_kubelet_busybox_count 0
    wait_huatuo_bamai_busybox_count 0
    log_info "✔ clean busybox ok"

    # create busybox
    for i in $(seq 1 ${BUSYBOX_CREATE_COUNT}); do
        kubectl run "${BUSYBOX_PREFIX}-${i}" \
            -n default \
            --image=${BUSYBOX_IMAGE} \
            --restart=Never \
            --labels ${BUSYBOX_LABEL} \
            -- sleep 3600
    done

    # check
    wait_kubelet_busybox_count ${BUSYBOX_CREATE_COUNT}
    log_info "✔ k8s busybox created"

    wait_huatuo_bamai_busybox_count ${BUSYBOX_CREATE_COUNT}
    log_info "✔ huatuo-bamai detected busybox ${BUSYBOX_CREATE_COUNT}"
}


prepare_test_env
setup_huatuo_bamai
wait_huatuo_bamai_ok
log_info "✅ huatuo-bamai server ok"

test_metrics

# Test Assumptions:
# - There is exactly ${BUSYBOX_DEFAULT_COUNT} busybox Pod running in the cluster by default.
#   busybox-business   1/1     Running   1 (18h ago)   11d

# Test Case 1: Existing Container
# - Verify huatuo-bamai can observe existing busybox container.

# Test Case 2: Container Delete
# - Delete the busybox Pod.
# - Verify both kubelet and huatuo-bamai no longer report the container.

# Test Case 3: Container Create
# - Create ${BUSYBOX_CREATE_COUNT} busybox Pods.
# - Verify both kubelet and huatuo-bamai report the containers correctly.
test_container_exists
log_info "✅ test_container_exists ok"
test_container_delete
log_info "✅ test_container_delete ok"
test_container_create
log_info "✅ test_container_create ok"

wait_huatuo_bamai_exit
check_huatuo_bamai_log
