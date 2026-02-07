#!/usr/bin/env bash
set -euo pipefail

source ${ROOT_DIR}/test/env.sh
source ${ROOT_DIR}/test/common/utils.sh
source ${ROOT_DIR}/test/common/huatuo-bamai.sh

test_huatuo_bamai_metrics() {
	log_info "⬅️ test huatuo-bamai metrics"
	for i in {1..10}; do
		huatuo_bamai_metrics >/dev/null
		sleep 0.2
	done
	log_info "✅ test huatuo-bamai metrics ok"
}
