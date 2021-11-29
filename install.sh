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
SPATH=`dirname $0`

#
# Init repo if not done yet
#
echo 
echo "Cloning submodules..."
echo

cd $SPATH
git submodule update --init --recursive

#
# Build and install fastcall kernel
#
echo
echo "Building fastcall kernel..."
echo 

cd $SPATH/linux-fastcall
make defconfig
make -j 8

sudo make modules_install
sudo make install

#
# Build and install fccmp kernel
#
echo 
echo "Building fccmp kernel..."
echo

cd $SPATH/linux-fccmp
make defconfig
make -j 8

sudo make modules_install
sudo make install

#
# Build Google's benchmark library
#
echo 
echo "Building benchmark library..."
echo 

cd $SPATH/benchmark
cmake -E chdir "build" cmake -DBENCHMARK_DOWNLOAD_DEPENDENCIES=on \
        -DCMAKE_BUILD_TYPE=Release ../
cmake --build "build" --config Release
sudo cmake --build "build" --config Release --target install


#
# Build fastcall benchmarks
#
echo 
echo "Building fastcall benchmarks..."
echo 

cd $SPATH/fastcall-benchmarks
cmake -S . -B build/ -DCMAKE_BUILD_TYPE=Release
cmake --build build/

exit 0
