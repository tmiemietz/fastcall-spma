#!/bin/bash

set -euo pipefail

LOAD_KERNEL=

finish() {
	if [[ "$?" -ne 0 ]]; then
		exit 2
	elif [[ -n "$LOAD_KERNEL" ]]; then
		exit 1
	fi
}
trap finish EXIT

execute() {
	echo "Performing \"$1\" benchmark..."
	RET=0
	OUTPUT="$(sudo ./execute.sh "run-$1" 2>/dev/null)" || RET="$?"
	if [[ "$RET" -eq 0 ]]; then
		echo "Benchmark \"$1\" finished"
	else
		LOAD_KERNEL="$(echo "$OUTPUT" | grep "load_kernel.sh")"
		echo "Benchmark \"$1\" requires different kernel(-configuration)"
	fi
}

for BENCH in "micro" "cycle" "misc" "syscall"; do
	execute "$BENCH"
done

if [[ -n "$LOAD_KERNEL" ]]; then
	echo "YeS" | sudo $LOAD_KERNEL
fi
