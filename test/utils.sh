#!/usr/bin/env bash
set -euo pipefail

log_prefix() {
	echo "[${TEST_LOG_TAG}]"
}

log_info() {
	echo "$(log_prefix) $*"
}

log_warn() {
	echo "$(log_prefix)[WARN] $*" >&2
}

log_error() {
	echo "$(log_prefix)[ERROR] $*" >&2
}

fatal() {
	echo "$(log_prefix)[FAIL] $*" >&2
	exit 1
}

assert_eq() {
	local actual=$1 expect=$2 msg=${3:-""}
	[[ "$actual" == "$expect" ]] || log_info "assert failed: ${msg} actual=${actual}, expect=${expect}"
}

wait_until() {
	local timeout=$1 interval=$2 desc=$3
	shift 3

	if [[ "$1" == *" "* ]]; then
		fatal "❌ wait_until expects function or command, got shell string: \"$1\""
	fi

	local end=$(($(date +%s) + timeout))
	local ret

	while (($(date +%s) < end)); do
		if "$@"; then
			return 0
		fi
		sleep "$interval"
	done

	fatal "❌ timeout waiting for: ${desc} after ${timeout}s"
}
