#!/usr/bin/env bash
set -euo pipefail

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
