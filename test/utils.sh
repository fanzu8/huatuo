#!/usr/bin/env bash
set -euo pipefail

log_info() { echo "[TEST] $*"; }
log_warn() { echo "[TEST][WARN] $*" >&2; }
log_error() { echo "[TEST][ERROR] $*" >&2; }

fatal() {
	log_error "$*"
	exit 1
}

assert_eq() {
	local actual=$1 expect=$2 msg=${3:-""}
	[[ "$actual" == "$expect" ]] || log_info "assert failed: ${msg} actual=${actual}, expect=${expect}"
}

wait_until() {
	local timeout=$1 interval=$2 desc=$3
	shift 3

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
