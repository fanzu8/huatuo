#!/usr/bin/env bash
set -euo pipefail

# Run the core integration tests.
unshare --uts --mount bash -c '
	mount --make-rprivate /
	echo "huatuo-dev" > /proc/sys/kernel/hostname
	hostname huatuo-dev 2>/dev/null || true

	set -xeuo pipefail
    source ./test/env.sh
	source "${ROOT_DIR}/test/integration/lib.sh"
    source "${ROOT_DIR}/test/integration/metrics.sh"

	# Always cleanup the tests.
	trap "integration_test_teardown \$?" EXIT

	integration_test_huatuo_bamai_start
	test_huatuo_bamai_metrics
	# more tests ...
	'
