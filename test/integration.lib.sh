#!/usr/bin/env bash
set -euo pipefail

export TEST_LOG_TAG="INTEGRATION TEST"

source "${ROOT_DIR}/test/env.sh"
source "${ROOT_DIR}/test/utils.sh"
source "${ROOT_DIR}/test/common/huatuo-bamai.sh"

integration_test_huatuo_bamai_config() {
	cat >"${HUATUO_BAMAI_TEST_TMPDIR}/bamai.conf" <<'EOF'
# the blacklist for tracing and metrics
BlackList = ["softlockup", "ethtool", "netstat_hw", "iolatency", "memory_free", "memory_reclaim", "reschedipi", "softirq"]
EOF
}

integration_test_huatuo_bamai_start() {
	[[ -x ${HUATUO_BAMAI_BIN} ]] || fatal "❌ binary not found: ${HUATUO_BAMAI_BIN}"
	[[ -d ${HUATUO_BAMAI_TEST_EXPECTED} ]] || fatal "❌ expected metrics directory not found: ${HUATUO_BAMAI_TEST_EXPECTED}"

	log_info "starting huatuo-bamai (mock fixture fs)"

	integration_test_huatuo_bamai_config

	huatuo_bamai_start "${HUATUO_BAMAI_ARGS_INTEGRATION[@]}"
	log_info "huatuo-bamai started"
}

integration_test_teardown() {
	local exit_code=$1

	huatuo_bamai_stop || true

	# Print details on failure
	if [ "${exit_code}" -ne 0 ]; then
		log_info "the exit code: $exit_code"
		log_info "
========== HUATUO INTEGRATION TEST FAILED ================

Summary:
  - One or more expected metrics are missing.

Temporary artifacts preserved at:
  ${HUATUO_BAMAI_TEST_TMPDIR}

Key files:
  - metrics.txt
  - huatuo.log
  - bamai.conf

=========================================================
"
	fi
}

fetch_huatuo_bamai_metrics() {
	huatuo_bamai_metrics >${HUATUO_BAMAI_TEST_TMPDIR}/metrics.txt
}

wait_and_fetch_metrics() {
	wait_until "${WAIT_HUATUO_BAMAI_TIMEOUT}" \
		"${WAIT_HUATUO_BAMAI_INTERVAL}" \
		"metrics endpoint ready" \
		fetch_huatuo_bamai_metrics
}

# Verify all expected metric files and dump metrics on success.
check_procfs_metrics() {
	for f in "${HUATUO_BAMAI_TEST_EXPECTED}"/*.txt; do
		prefix="$(basename "$f" .txt)"

		check_metrics_from_file "${f}"

		log_info "metric prefix ok: huatuo_bamai_${prefix}"
		grep "^huatuo_bamai_${prefix}" "${HUATUO_BAMAI_TEST_TMPDIR}/metrics.txt" || log_info "(no metrics found)"
	done
}

check_metrics_from_file() {
	local file="$1"

	missing_metrics=$(
		grep -v '^[[:space:]]*\(#\|$\)' "${file}" |
			grep -Fvw -f "${HUATUO_BAMAI_TEST_TMPDIR}/metrics.txt" || true
	)

	if [[ -z "${missing_metrics}" ]]; then
		return
	fi

	log_info "the missing metrics:"
	log_info "${missing_metrics}"
	log_info "the metrics file ${HUATUO_BAMAI_TEST_TMPDIR}/metrics.txt:"
	log_info "$(cat ${HUATUO_BAMAI_TEST_TMPDIR}/metrics.txt)"
	exit 1
}

test_huatuo_bamai_metrics() {
	wait_and_fetch_metrics
	check_procfs_metrics
	# ...
}
