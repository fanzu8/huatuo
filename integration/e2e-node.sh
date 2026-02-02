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
E2E_TEST_LOG_FILE="/tmp/huatuo-bamai.log"
MATCH_KEYWORDS="error|panic"


append_case_to_blacklist() {
    local case_name="$1"

    if grep -q "\"$case_name\"" ${HUATUO_BAMAI_CONF}; then
        echo "$case_name already exists in Blacklist"
        return
    fi

    # Blacklist = ["softlockup", "ethtool"]
    sed -i "/Blacklist =/ s/\[/\[\"$case_name\", /" ${HUATUO_BAMAI_CONF}
}

append_ifce_to_netdev_whitelist() {
    local netdev_name="$1"
    if grep -q "\"$netdev_name\"" ${HUATUO_BAMAI_CONF}; then
        echo "$netdev_name already exists in netdev Whitelist"
        return
    fi

    # [Tracing.Netdev]
    #     Whitelist = ["eth0", "eth1", "bond4", "lo"]
    sed -i "/       Whitelist =/ s/\[/\[\"$netdev_name\", /" ${HUATUO_BAMAI_CONF}
}

prepare_test_env() {
    rm -f ${HUATUO_BAMAI_PIDFILE} ${E2E_TEST_LOG_FILE}
    kill -9 $(pidof huatuo-bamai) 2>/dev/null || true
    # append_case_to_blacklist "netdev_rdma_link"
    append_ifce_to_netdev_whitelist "enp2s0"
}

setup_runtime() {
    mkdir -p $(dirname ${E2E_TEST_LOG_FILE})
    timeout -s SIGINT ${HUATUO_BAMAI_RUN_TIMEOUT}s \
        ${HUATUO_BAMAI_BIN} \
        --region e2e-node \
        --disable-storage \
        --disable-kubelet \
        --config-dir ${ROOT}/_output/conf/ \
        --config huatuo-bamai.conf \
        > ${E2E_TEST_LOG_FILE} 2>&1 &
}

wait_runtime_ok() {
    local timeout=$((HUATUO_BAMAI_RUN_TIMEOUT / 4))
    local interval=1  # seconds

	for ((i = 1; i <= timeout; i += interval)); do
        if curl -sf "localhost:19704/metrics" >/dev/null; then
            return 0
        fi
        sleep ${interval}
    done

    echo -e "❌ runtime not running after ${timeout}s" && exit 1 
}

wait_runtime_exit() {
    local timeout=$((HUATUO_BAMAI_RUN_TIMEOUT))
    local interval=1  # seconds

	for ((i = 1; i <= timeout; i += interval)); do
        if ! pidof huatuo-bamai >/dev/null; then
            return 0
        fi
        echo -e "waiting runtime exit, try ${i}/${timeout}"
        sleep ${interval}
    done
}

test_metrics() {
    local count=10
	for ((i = 1; i <= count; i += 1)); do
        curl -sf "localhost:19704/metrics" 2>&1 > /dev/null || true
    done
}

# test_container_create() {

# }

# test_container_delete() {

# }

check_log() {
    # print and check content of log file
    sed -E "s/(${MATCH_KEYWORDS})/\x1b[31m\1\x1b[0m/gI" $E2E_TEST_LOG_FILE
    ! grep -qE "$MATCH_KEYWORDS" $E2E_TEST_LOG_FILE
}


prepare_test_env
setup_runtime
wait_runtime_ok
echo -e "✅ runtime server ok"

test_metrics
# test_container_create
# test_container_delete
wait_runtime_exit
check_log
