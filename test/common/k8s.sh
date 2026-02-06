#!/usr/bin/env bash
set -euo pipefail

k8s_create_pod() {
	local ns=$1
	local name=$2
	local image=$3
	local label=$4
	local num=$5

	for i in $(seq 1 ${num}); do
		kubectl run "${name}-${i}" \
			-n ${ns} \
			--image=${image} \
			--restart=Never \
			-l ${label} \
			-- sleep infinity
	done
}

k8s_delete_pod() {
	local ns=$1
	local label=$2
	kubectl delete pod --namespace "$ns" -l "$label"
}
