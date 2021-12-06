#! /bin/bash -e

################################################################################
#                                                                              #
# Script for running the benchmarks of the fastcall repo. Multiple reboots     #
# will be required for collecting all results. Benchmarks will be run for      #
# multiple mitigation options of the kernel, depending on the CPU arch in use. #
#                                                                              #
################################################################################

#
# Mitigation option table (space-separated list for each vendor)
#

# AMD
MITI_AMD="mitigations=off"

#
# Other globals variables
#

# list of mitigation options to iterate over, set automatically
MITIS=""

# list of benchmarks to run
BENCHS="fastcall syscall ioctl vdso"

################################################################################
#                                                                              #
#                          Function Implementation                             #
#                                                                              #
################################################################################


#
# Prints a small help text to stdout.
#
usage () {
  echo "Usage: execute.sh <command>"
  echo
  echo "List of Accepted Commands:"
  echo "=========================="
  echo
  echo "run   - Runs benchmarks for the CPU type of this machine. May require "
  echo "        multiple reboots with different kernels to complete. Watch the"
  echo "        output of the script for instructions."
  echo
  echo "reset - Clears benchmark results for the CPU type of this machine."
  echo
  echo "help  - Outputs this help and exits."
  echo "        Options: none"
  echo 
  echo "Options:"
  echo "=========================="
}

#
# Selects the list of suitable mitigations accoring to CPU manufacturer.
#
get_mitigation_list () {
  case "$VENDOR" in
    "AuthenticAMD")
      MITIS="$MITI_AMD";;
    *)
      echo "Unknown CPU vendor. Please extend this script to handle this!"
      echo "Aborting..."
      exit 1;;
  esac
}

#
# Checks whether the kernel is configured properly for the next experiment,
# outputs a line to pass to load_kernel.sh if needed.
#
# $1 - Expected mitigation list.
# $2 - Benchmark to run.
#
check_kernel () {
  typeset kversion=`uname -r`
  typeset opts=`echo "$1" | tr "%" " "`
  # cmdline for kernel that is currently running
  typeset cmdline=`cat /proc/cmdline`

  # check if proper kernel (fastcall / fccmp) was loaded
  if [ "$2" == "fastcall" ]
    then
    if [[ ! $kversion == *"fastcall"* ]]
      then
      # name of kernel that should be booted instead
      typeset nkernv=`ls /boot | grep vmlinuz-.* | grep -v old | grep fastcall`
      nkernv=${nkernv##vmlinuz-}

      echo "ERROR: Wrong kernel version!"
      echo "Run the following command, reboot and continue execution: "
      echo 
      echo "./load_kernel.sh set --version $nkernv --options $opts"
      exit 2
    fi
  else
    if [[ ! $kversion == *"fccmp"* ]]
      then
      # name of kernel that should be booted instead
      typeset nkernv=`ls /boot | grep vmlinuz-.* | grep -v old | grep fccmp`
      nkernv=${nkernv##vmlinuz-}

      echo "ERROR: Wrong kernel version!"
      echo "Run the following command, reboot and continue execution: "
      echo 
      echo "./load_kernel.sh set --version $nkernv --options $opts"
      exit 2
    fi
  fi

  # check if proper mitigations have been set
  for opt in "$opts"
    do
    if [[ ! $cmdline == *"$opt"* ]]
      then
      echo "ERROR: Kernel mitigation options are incorrect for the benchmark!"
      echo "Run the following command, reboot and continue execution: "
      echo 
      echo "./load_kernel.sh set --version $nkernv --options $opts"
      exit 2
    fi
  done
}

#
# Runs experiments. Multiple reboots and kernel switches may be required in
# between!
#
do_run () {
  get_mitigation_list

  for miti in $MITIS
    do
    # create results directory
    mkdir -p ${SPATH}/results/${CPUID}/${miti}

    for bench in $BENCHS
      do
      echo "Running benchmark $bench for kernel config ${miti}..."
      
      # check if benchmark was already conducted
      if [ -f ${SPATH}/results/${CPUID}/${miti}/${bench}.csv ]
        then
        echo "Benchmark results already present. Skipping..."
        continue
      fi

      # check if kernel config fits the next benchmark
      check_kernel "$miti" "$bench"

      csv=`${SPATH}/fastcall-benchmarks/build/benchmark/fastcall-benchmark \
           --benchmark_filter=${bench} --benchmark_format=csv \
           2>${SPATH}/results/${CPUID}/${miti}/${bench}.out`

      if [ $? -ne 0 ]
        then
        echo "Benchmark $bench failed. See output below: "
        echo 
        cat ${SPATH}/results/${CPUID}/${miti}/${bench}.out
        continue
      fi

      # benchmark successful, store plain csv
      echo "$csv" > ${SPATH}/results/${CPUID}/${miti}/${bench}.csv

      echo "Done."
    done
  done
}

#
# Resets benchmark results for current CPU by deleting the corresponding
# subdirectory in results
#
do_reset () {
  echo "Resetting benchmark results for CPU type $CPUID..."

  # prevent shell exit if directory is not present
  rm -rf $SPATH/results/$CPUID || true
}

#
# General setup
#

# Path of this script
SPATH=`dirname $0`

# CPU vendor, serves as a indicator for mitigation list
VENDOR=`cat /proc/cpuinfo | grep vendor_id | head -n 1 | cut -d " " -f 2`

# CPU version string
CPUID=`cat /proc/cpuinfo | grep "model name" \
                         | head -n 1 \
                         | tr "\t" " " \
                         | awk -v FS=":" '{ print($2); }' \
                         | xargs \
                         | tr " " "_"`

#
# Argument parsing
#

# At least a command must be provided
if [ $# -lt 1 ]
  then
  usage
  exit 1
fi

CMD=$1
shift 1

# Branch depending on command
case "$CMD" in
  "run")
    do_run

    echo
    echo "Benchmarks finished for local CPU type $CPUID."
    echo;;
  "reset")
    do_reset;;
  "help")
    usage;;
  *)
    echo "ERROR: Unknown command $CMD. Aborting..."
    exit 1;;
esac

exit 0
