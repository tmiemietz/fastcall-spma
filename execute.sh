#! /bin/bash

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
MITI_AMD="mitigations=off nopti%mds=off mitigations=auto"

# Intel
MITI_INTEL="mitigations=off nopti%mds=off mitigations=auto"

# ARM (we don't support mitigated kernels yet)
MITI_ARM="mitigations=off"

#
# Other globals variables
#

# list of mitigation options to iterate over, set automatically
MITIS=""

# list of microbenchmarks to run
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
  echo "run-micro    - Runs microbenchmarks for the CPU type of this machine. May"
  echo "               require multiple reboots with different kernels to"
  echo "               complete. Watch the output of the script for instructions."
  echo "               Options: none"
  echo
  echo "run-cycle    - Runs microbenchmarks for the CPU type of this machine with"
  echo "               cycle accurate measurement. May require multiple reboots "
  echo "               with different kernels to complete. Watch the output of "
  echo "               the script for instructions."
  echo "               Options: none"
  echo
  echo "run-misc     - Runs the misc benchmarks for the CPU type of this machine."
  echo "               May require multiple reboots with different kernels to"
  echo "               complete. Watch the output of the script for instructions."
  echo "               Options: none"
  echo
  echo "run-syscall  - Runs the syscall benchmark for the CPU type of this machine."
  echo "               May require multiple reboots with different mitigations to"
  echo "               complete. Watch the output of the script for instructions."
  echo "               Options: none"
  echo
  echo "reset        - Clears benchmark results for the CPU type of this machine."
  echo "               Options: none"
  echo
  echo "help         - Outputs this help and exits."
  echo "               Options: none"
  echo
  echo "Options:"
  echo "=========================="
}

#
# Selects the list of suitable mitigations accoring to CPU manufacturer.
#
get_mitigation_list () {
  # first, distinguish by ISA type, then further by vendor
  if [ "$ISA" == "x86_64" ]
    then
    case "$VENDOR" in
      "AuthenticAMD")
        MITIS="$MITI_AMD";;
      "GenuineIntel")
        MITIS="$MITI_INTEL";;
      *)
        echo "Unknown CPU vendor \"$VENDOR\"."
        echo "Please extend this script to handle this!"
        echo "Aborting..."
        exit 1;;
    esac
  elif [ "$ISA" == "aarch64" ]
    then
    case "$VENDOR" in
      "ARM")
        MITIS="$MITI_ARM";;
      *)
        echo "Unknown CPU vendor \"$VENDOR\"."
        echo "Please extend this script to handle this!"
        echo "Aborting..."
        exit 1;;
    esac
  else
    echo "Unknown ISA \"$ISA\" found. Please extend this script to handle this."
    echo "Aborting..."
    exit 1
  fi
}

#
# Checks whether the kernel is configured properly for the next experiment,
# outputs a line to pass to load_kernel.sh if needed.
#
# $1 - Expected mitigation list.
# $2 - Benchmark to run.
#
check_kernel () {
  # kernel version that is currently running
  typeset kversion=`uname -r`
  # kernel version that should be running for benchmark
  typeset nkernv=""

  typeset opts=`echo "$1" | tr "%" " "`
  # cmdline for kernel that is currently running
  typeset cmdline=`cat /proc/cmdline`

  # check if proper kernel (fastcall / fccmp) was loaded
  if [ "$2" == "fastcall" ]
    then
    # name of kernel that should be booted
    nkernv=`ls /boot | grep vmlinuz-.* | grep -v old | grep fastcall`
    nkernv=${nkernv##vmlinuz-}

    if [[ ! $kversion == *"fastcall"* ]]
      then
      echo "ERROR: Wrong kernel version!"
      echo "Run the following command, reboot and continue execution: "
      echo
      echo "./load_kernel.sh set --version $nkernv --options $opts"
      exit 2
    fi
  elif [ "$2" == "fccmp" ]
  then
    # name of kernel that should be booted
    nkernv=`ls /boot | grep vmlinuz-.* | grep -v old | grep fccmp`
    nkernv=${nkernv##vmlinuz-}

    if [[ ! $kversion == *"fccmp"* ]]
      then
      echo "ERROR: Wrong kernel version!"
      echo "Run the following command, reboot and continue execution: "
      echo
      echo "./load_kernel.sh set --version $nkernv --options $opts"
      exit 2
    fi
  elif [ "$2" == "syscall-bench" ]
  then
    # name of kernel that should be booted
    nkernv=`ls /boot | grep vmlinuz-.* | grep -v old | grep syscall-bench`
    nkernv=${nkernv##vmlinuz-}

    if [[ ! $kversion == *"syscall-bench"* ]]
      then
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
# Set the CPU governor to performance mode to guarantee stable measurement
# results. Depending on the OS distro, the way of doing this may differ, so
# this is done in a separate function to preserve modularity.
# This function furthermore tries to disable turbo mode and hyperthreading.
#
# Note: The modifications done inside this function should be temporary, i.e.,
#       they should be reset after the next reboot.
#
disable_cpu_scaling () {
  # CPU scaling config depends on both ISA and vendor
  if [ "$ISA" == "x86_64" ]
    then
    # switch off turbo mode and hyperthreading; depends on vendor type
    case "$VENDOR" in
      "AuthenticAMD")
        # disable turbo mode
        echo 0 > /sys/devices/system/cpu/cpufreq/boost

        # turn off SMT
        echo "off" > /sys/devices/system/cpu/smt/control;;
      "GenuineIntel")
        # disable turbo mode
        echo 1 > /sys/devices/system/cpu/intel_pstate/no_turbo

        # turn off SMT
        echo "off" > /sys/devices/system/cpu/smt/control;;
      *)
        echo "Unknown CPU vendor. Please extend this script to handle this!"
        echo "Aborting..."
        exit 1;;
    esac
  elif [ "$ISA" == "aarch64" ]
    then
    case "$VENDOR" in
      "ARM")
        # ARM has to hyper-threading, also no frequency boosting
        :;;
      *)
        echo "Can't configure CPU settings: Unknown CPU vendor \"$VENDOR\"."
        echo "Please extend this script to handle this!"
        echo "Aborting..."
        exit 1;;
    esac
  else
    echo "Unknown ISA \"$ISA\" found. Please extend this script to handle this."
    echo "Aborting..."
    exit 1
  fi

  # lastly, set CPU governor for remaining cores

  # way for doing this on SuSE / Debian
  cpupower frequency-set -g performance

  # abort upon error to avoid bogus benchmark results due to active CPU
  # scaling
  if [ $? -ne 0 ]
    then
    echo
    echo "##################################################################"
    echo "WARNING: Failed to disable CPU scaling. Check benchmark output to "
    echo "         assure that the CPU governor is set to \"performance\"!"
    echo "##################################################################"
    echo
  fi
}

#
# Runs microbenchmark experiments. Multiple reboots and kernel switches may be
# required in between!
#
do_run_micro () {
  get_mitigation_list

  # set CPU governor to performance for this boot cycle (will be reset to
  # system default after next reboot)
  disable_cpu_scaling

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
# Runs cycle-accurate microbenchmarks. Multiple reboots and kernel switches
# may be required in between!
#
do_run_cycle () {
  # list of misc benchmarks to run for a certain kernel type
  typeset cycle_benchs=""

  get_mitigation_list

  # set CPU governor to performance for this boot cycle (will be reset to
  # system default after next reboot)
  disable_cpu_scaling

  for miti in $MITIS
    do
    # create results directory
    mkdir -p ${SPATH}/results/${CPUID}/${miti}

    # do misc benchmarks for both the fastcall and the fccmp kernel
    for ktype in "fastcall" "fccmp"
      do
      echo "Running cycle benchmarks for kernel config ${ktype}/${miti}..."

      # check if benchmark was already conducted
      if [ -f ${SPATH}/results/${CPUID}/${miti}/cycles-${ktype}.csv ]
        then
        echo "Benchmark results already present. Skipping..."
        continue
      fi

      # set list of misc benchmarks to run for this kernel type
      if [ "$ktype" == "fastcall" ]
        then
        cycle_benchs="noop fastcall"
      else
        # leave some benchmarks out as they can only be performed with a
        # fastcall-enabled kernel.
        cycle_benchs="noop vdso syscall ioctl"
      fi

      for bench in $cycle_benchs
        do
        echo "Running cycle benchmark case ${bench}..."

        # check if kernel config fits the next benchmark, here: use ktype to
        # load appropriate kernel version (fastcall requires fastcall kernel,
        # everything else will be mapped to fccmp).
        check_kernel "$miti" "$ktype"

        csv=`${SPATH}/fastcall-benchmarks/build/cycles/fastcall-cycles \
             ${bench} \
             2>${SPATH}/results/${CPUID}/${miti}/cycles-${ktype}-${bench}.out`

        if [ $? -ne 0 ]
          then
          echo "Benchmark $bench failed. See output below: "
          echo
          cat ${SPATH}/results/${CPUID}/${miti}/cycles-${ktype}-${bench}.out
          continue
        fi

        # if result file does not exist, create it, otherwise do merging
        if [ ! -f ${SPATH}/results/${CPUID}/${miti}/cycles-${ktype}.csv ]
          then
          printf "${bench}\n${csv}" \
                  > ${SPATH}/results/${CPUID}/${miti}/cycles-${ktype}.csv
        else
          # write results to temporary file, merge result files later on
          printf "${bench}\n${csv}" > ${SPATH}/results/${CPUID}/${miti}/cycles.p

          # merge files
          paste -d "," ${SPATH}/results/${CPUID}/${miti}/cycles-${ktype}.csv \
                       ${SPATH}/results/${CPUID}/${miti}/cycles.p \
                       > ${SPATH}/results/${CPUID}/${miti}/cycles-${ktype}.csv.tmp

          # remove tempfiles
          mv ${SPATH}/results/${CPUID}/${miti}/cycles-${ktype}.csv.tmp \
             ${SPATH}/results/${CPUID}/${miti}/cycles-${ktype}.csv
          rm ${SPATH}/results/${CPUID}/${miti}/cycles.p
        fi
      done
      echo "Done."
    done
  done
}

#
# Runs "miscellaneous" experiments. Multiple reboots and kernel switches may be
# required in between!
#
do_run_misc () {
  # list of misc benchmarks to run for a certain kernel type
  typeset misc_benchs=""

  get_mitigation_list

  # set CPU governor to performance for this boot cycle (will be reset to
  # system default after next reboot)
  disable_cpu_scaling

  for miti in $MITIS
    do
    # create results directory
    mkdir -p ${SPATH}/results/${CPUID}/${miti}

    # do misc benchmarks for both the fastcall and the fccmp kernel
    for ktype in "fastcall" "fccmp"
      do
      echo "Running misc benchmarks for kernel config ${ktype}/${miti}..."

      # check if benchmark was already conducted
      if [ -f ${SPATH}/results/${CPUID}/${miti}/misc-${ktype}.csv ]
        then
        echo "Benchmark results already present. Skipping..."
        continue
      fi

      # set list of misc benchmarks to run for this kernel type
      if [ "$ktype" == "fastcall" ]
        then
        misc_benchs="noop
                     registration-minimal registration-mappings
                     deregistration-minimal deregistration-mappings
                     fork-simple fork-fastcall
                     vfork-simple vfork-fastcall"
      else
        # leave some benchmarks out as they can only be performed with a
        # fastcall-enabled kernel.
        misc_benchs="noop
                     fork-simple vfork-simple"
      fi

      for bench in $misc_benchs
        do
        echo "Running misc benchmark case ${bench}..."

        # check if kernel config fits the next benchmark, here: use ktype to
        # load appropriate kernel version (fastcall requires fastcall kernel,
        # everything else will be mapped to fccmp).
        check_kernel "$miti" "$ktype"

        csv=`${SPATH}/fastcall-benchmarks/build/misc/fastcall-misc \
             ${bench} \
             2>${SPATH}/results/${CPUID}/${miti}/misc-${ktype}-${bench}.out`

        if [ $? -ne 0 ]
          then
          echo "Benchmark $bench failed. See output below: "
          echo
          cat ${SPATH}/results/${CPUID}/${miti}/misc-${ktype}-${bench}.out
          continue
        fi

        # if result file does not exist, create it, otherwise do merging
        if [ ! -f ${SPATH}/results/${CPUID}/${miti}/misc-${ktype}.csv ]
          then
          printf "${bench}\n${csv}" \
                  > ${SPATH}/results/${CPUID}/${miti}/misc-${ktype}.csv
        else
          # write results to temporary file, merge result files later on
          printf "${bench}\n${csv}" > ${SPATH}/results/${CPUID}/${miti}/misc.p

          # merge files
          paste -d "," ${SPATH}/results/${CPUID}/${miti}/misc-${ktype}.csv \
                       ${SPATH}/results/${CPUID}/${miti}/misc.p \
                       > ${SPATH}/results/${CPUID}/${miti}/misc-${ktype}.csv.tmp

          # remove tempfiles
          mv ${SPATH}/results/${CPUID}/${miti}/misc-${ktype}.csv.tmp \
             ${SPATH}/results/${CPUID}/${miti}/misc-${ktype}.csv
          rm ${SPATH}/results/${CPUID}/${miti}/misc.p
        fi
      done
      echo "Done."
    done
  done
}

#
# Runs "syscall" experiments. Multiple reboots and config switches may be
# required in between!
#
do_run_syscall () {
  get_mitigation_list

  # set CPU governor to performance for this boot cycle (will be reset to
  # system default after next reboot)
  disable_cpu_scaling

  for miti in $MITIS
    do
    # create results directory
    mkdir -p ${SPATH}/results/${CPUID}/${miti}

    echo "Running syscall benchmarks for mitigation ${miti}..."

    file="${SPATH}/results/${CPUID}/${miti}/syscall-bench.csv"
    # check if benchmark was already conducted
    if [ -f "$file" ]
      then
      echo "Benchmark results already present. Skipping..."
      continue
    fi

    # check if kernel config fits the next benchmark
    check_kernel "$miti" syscall-bench

    out="${SPATH}/results/${CPUID}/${miti}/syscall-bench.out"
    csv=`${SPATH}/fastcall-benchmarks/build/syscall/syscall \
         >"$file" \
         2>"$out"`

    if [ $? -ne 0 ]
      then
      echo "Benchmark $bench failed. See output below: "
      echo
      cat "$out"
      continue
    fi

    echo "Done."
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

# ISA type of local machine
ISA=`uname -m`

if [ "$ISA" == "x86_64" ]
  then
  # CPU vendor, serves as a indicator for mitigation list
  VENDOR=`cat /proc/cpuinfo | grep vendor_id | head -n 1 | cut -d " " -f 2`

  # CPU version string
  CPUID=`cat /proc/cpuinfo | grep "model name" \
                           | head -n 1 \
                           | tr "\t" " " \
                           | awk -v FS=":" '{ print($2); }' \
                           | xargs \
                           | tr " " "_"`
elif [ "$ISA" == "aarch64" ]
  then
  # CPU vendor, serves as a indicator for mitigation list
  VENDOR=`lscpu | grep "Vendor ID:" | xargs | cut -d " " -f 3`

  # CPU version string
  CPUID=`lscpu | grep "Model name:" | xargs | cut -d " " -f 3`

  # Make sure that there is some human-readable output
  if [ -z "$VENDOR" ]
    then
    echo "ERROR: Your local version of lscpu seems to lack support for"
    echo "       decoding CPU names of ARM cores. Please install a version"
    echo "       of lscpu that provides these features and re-run this script."
    echo "Aborting..."
    exit 1
  fi
else
  echo "Unknown ISA \"$ISA\" found. Please extend this script to handle this."
  echo "Aborting..."
  exit 1
fi

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
  "run-micro")
    do_run_micro

    echo
    echo "Microbenchmarks finished for local CPU type $CPUID."
    echo;;
  "run-cycle")
    do_run_cycle

    echo
    echo "Cycle-accurate microbenchmarks finished for local CPU type $CPUID."
    echo;;
  "run-misc")
    do_run_misc

    echo
    echo "Miscellaneous benchmarks finished for local CPU type $CPUID."
    echo;;
  "run-syscall")
    do_run_syscall

    echo
    echo "Syscall benchmarks finished for local CPU type $CPUID."
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
