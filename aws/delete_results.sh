#!/bin/bash

# This script deletes the existing results for this CPU.
# This allows the benchmark script to record new measurements.

set -euo pipefail

SPATH="$(realpath "$(dirname $0)")"
CPUID="$(
  cat /proc/cpuinfo |
  grep "model name" |
  head -n 1 |
  tr "\t" " " |
  awk -v FS=":" '{ print($2); }' |
  xargs |
  tr " " "_"
)"

sudo rm -rf "$SPATH/../results/$CPUID/"
