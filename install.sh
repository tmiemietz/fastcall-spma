#! /bin/bash -e

################################################################################
#                                                                              #
# Installation script for the kernels and libraries used by the fastcall       #
# benchmarks.                                                                  #
#                                                                              #
# Usage: ./install.sh                                                          #
#                                                                              #
################################################################################

#
# General setup
#

# Path of this script
SPATH="$(realpath `dirname $0`)"

#
# Build and install kernel
#
install_kernel() {
  echo
  echo "Building $1 kernel..."
  echo

  cd "$SPATH/linux-$1"
  if [ -e .config ]; then
    echo "Config exists, skipping config creation"
  else
    if [ -e /proc/config.gz ]; then
      echo "Using /proc/config.gz as .config"
      zcat /proc/config.gz > .config
    elif OUTPUT="$(ls /boot/config-*-cloud-* 2>/dev/null)"; then
      # This finds the latest kernel config at least on AWS.
      OUTPUT="$(echo "$OUTPUT" | sort | tail --lines=1)"
      echo "Using $OUTPUT as .config"
      cp "$OUTPUT" .config
    else
      echo "Using defconfig"
      make defconfig
    fi
    # CONFIG_DEBUG_INFO_BTF must not be set on low-memory AWS instances.
    sed -i 's/CONFIG_DEBUG_INFO_BTF=y/# CONFIG_DEBUG_INFO_BTF is not set/g' \
      .config
    if [[ "$1" == syscall-bench ]]; then
      # CONFIG_ARM64_PAN must not be set on ARM.
      sed -i 's/CONFIG_ARM64_PAN=y/# CONFIG_ARM64_PAN is not set/g' .config
      # CONFIG_XEN_PV must not be set on x86.
      sed -i 's/CONFIG_XEN_PV=y/# CONFIG_XEN_PV is not set/g' \
        .config
    fi
    if [[ "$1" == fastcall ]]; then
      # CONFIG_UNMAP_KERNEL_AT_EL0 must not be set on ARM.
      sed -i \
        's/CONFIG_UNMAP_KERNEL_AT_EL0=y/# CONFIG_UNMAP_KERNEL_AT_EL0 is not set/g' \
        .config
      # CONFIG_ARM64_SW_TTBR0_PAN must not be set on ARM.
      sed -i \
        's/CONFIG_ARM64_SW_TTBR0_PAN=y/# CONFIG_ARM64_SW_TTBR0_PAN is not set/g' \
        .config
    fi
    make olddefconfig
    make localmodconfig
    # CONFIG_X86_MSR should be set for CPU power management.
    sed -i 's/# CONFIG_X86_MSR is not set/CONFIG_X86_MSR=m/g' .config
  fi
  make -j `nproc`

  sudo make modules_install
  sudo make install
}

#
# Init repo if not done yet
#
echo
echo "Cloning submodules..."
echo

cd $SPATH
git submodule update --init --recursive --depth=1

#
# Build and install kernels
#
install_kernel fastcall

install_kernel fccmp

install_kernel syscall-bench

#
# Build Google's benchmark library
#
echo
echo "Building benchmark library..."
echo

cd $SPATH/benchmark
mkdir -p $SPATH/benchmark/build
cmake -DCMAKE_BUILD_TYPE=Release -DBENCHMARK_DOWNLOAD_DEPENDENCIES=on \
      -S . -B "build"
cmake --build "build" --config Release -j `nproc`
sudo cmake --build "build" --config Release --target install


#
# Build fastcall benchmarks
#
echo
echo "Building fastcall benchmarks..."
echo

cd $SPATH/fastcall-benchmarks
cmake -S . -B build/ -DCMAKE_BUILD_TYPE=Release
cmake --build build/ -j `nproc`

exit 0
