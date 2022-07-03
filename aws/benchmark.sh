#!/bin/bash

# This script executes all benchmarks with ../execute.sh.
# Afterwards, an appropriate, new kernel configuration is applied when there
# are still benchmarks left to perform.

set -euo pipefail

LOAD_KERNEL=

# Exit with code 1 when a reboot is required.
finish() {
	if [[ "$?" -ne 0 ]]; then
		exit 2
	elif [[ -n "$LOAD_KERNEL" ]]; then
		exit 1
	fi
}
trap finish EXIT

# Execute the benchmark $1 and record the ../load_kernel.sh command if required.
execute() {
	echo "Performing \"$1\" benchmark..."
	RET=0
	OUTPUT="$(sudo ./execute.sh "run-$1" 2>/dev/null)" || RET="$?"
	if [[ "$RET" -eq 0 ]]; then
		# All required configurations have been tested.
		echo "Benchmark \"$1\" finished"
	else
		LOAD_KERNEL="$(echo "$OUTPUT" | grep "load_kernel.sh")"
		echo "Benchmark \"$1\" requires different kernel(-configuration)"
	fi
}

# Execute all benchmarks in a row.
for BENCH in "micro" "cycle" "misc" "syscall"; do
	execute "$BENCH"
done

# Load new kernel configuration.
if [[ -n "$LOAD_KERNEL" ]]; then
	echo "YeS" | sudo $LOAD_KERNEL
fi
