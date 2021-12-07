#! /bin/bash -e

################################################################################
#                                                                              #
# Script that sets the kernel to run upon next reboot of the machine. Can also #
# list available kernel versions and set side channel mitigation options for   #
# the next system reboot.                                                      #
#                                                                              #
################################################################################


#
# Global variables
#

CMD=""                                  # Action to be executed 
VERSION=""                              # Stores kernel version to apply
OPTIONS=""                              # Options for starting the kernel

################################################################################
#                                                                              #
#                          Function Implementation                             #
#                                                                              #
################################################################################

#
# Print a small help text to stdout.
#
usage () {
  echo "Usage: load_kernel.sh <command> <options>"
  echo
  echo "List of Accepted Commands:"
  echo "=========================="
  echo
  echo "list -  Prints a list of all Linux kernels installed."
  echo "        Options: none"
  echo
  echo "set  -  Sets the kernel that shall be used upon next system restart."
  echo "        If --options is given, this must be the last option since the "
  echo "        entire following command line will be taken verbatim as a "
  echo "        string of multiple kernel parameters that will be injected "
  echo "        into the booting config."
  echo "        Options: --version , --options (optional)"
  echo
  echo "help -  Outputs this help and exits."
  echo "        Options: none"
  echo 
  echo "Options:"
  echo "============================================"
  echo
  echo "--options - A comma-separated list of kernel options that should be"
  echo "            applied upon next system reboot."
  echo "            Compatible commands: set"
  echo
  echo "--version - Version string of the kernel that should be run after"
  echo "            restarting the system."
  echo "            Compatible commands: set"
}


#
# Lists installed kernel versions on the system
#
list_kernels () {
  echo "List of available Linux kernels:"
  echo 

  # Search /boot for kernel images, omit *.old images
  for kernel in `ls /boot | grep vmlinuz-.* | grep -v old`
    do
    echo ${kernel##vmlinuz-}
  done
}

#
# Configures the system to use a new kernel after reboot.
#
set_kernel () {
  # First look if desired kernel is present
  if [ ! -f /boot/vmlinuz-$VERSION ]
    then
    echo "ERROR: Can't find kernel image \"/boot/vmlinuz-$VERSION\""
    exit 1
  fi

  echo "Setting active kernel image to \"/boot/vmlinuz-$VERSION\" ."

  echo "Updating GRUB configuration..."

  # Find out id of advanced booting options menu, it's the second last field
  # of the submenu line
  typeset -i menuline_wcnt=`cat /boot/grub2/grub.cfg | grep submenu | wc -w`
  typeset -i menuid_idx=$((menuline_wcnt - 1))

  typeset menuid=`cat /boot/grub2/grub.cfg | grep "submenu" \
                                           | cut -d' ' -f${menuid_idx} \
                                           | tr -d "'"`

  # Find out id of specified kernel. Note the trailing ' when grepping: this
  # prevents us from running into prefixing issues (i.e., one kernel version
  # is an prefix of another, leading to ambiguous grep results). Again,
  # actual id is the second last field on the line.
  typeset -i kernid_wcnt=`cat /boot/grub2/grub.cfg \
                                | grep "with Linux $VERSION'" | wc -w`
  typeset -i kernid_idx=$((kernid_wcnt - 1))

  # Remove leading whitespace from menu entry by piping stuff through xargs
  typeset kernid=`cat /boot/grub2/grub.cfg | grep "with Linux $VERSION'" \
                                           | xargs \
                                           | cut -d' ' -f${kernid_idx} \
                                           | tr -d "'"`

  # update default boot entry, disable silent booting, and set kernel options 
  typeset grubconf=`cat /etc/default/grub | \
                    awk -v krn="$kernid" -v men="$menuid" -v opt="$OPTIONS" '
     
     # catch default boot entry
     /^GRUB_DEFAULT=.*$/ { print("GRUB_DEFAULT=\"" men ">" krn "\""); 
                           next;
                         }

     # replace option string with the one passed by the user.
     /^GRUB_CMDLINE_LINUX_DEFAULT=.*$/ { 
            print("GRUB_CMDLINE_LINUX_DEFAULT=\"" opt "\"");
            next;
          }

     # default, output line without modifications
     { print($0); }
  '`

  echo "$grubconf" > /etc/default/grub
  update-bootloader

  echo "Done."
}

#
# General setup
#

# Path of this script
SPATH=`dirname $0`

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

# Parse remaining options
while [ $# -gt 0 ]
  do
  case "$1" in
    "--options")
      # make sure that a kernel version has been specified *before* the
      # kernel options
      if [ -z "$VERSION" ]
        then
        echo "ERROR: Specify kernel version before options!"
        echo
        usage
        exit 1
      fi

      # no empty optarg allowed
      if [ $# -lt 2 ]
        then
        echo "ERROR: --options expects list with kernel options!"
        echo
        usage
        exit 1
      fi

      shift 1
    
      # take entire remaining command line as booting options
      OPTIONS="$@"
      break;;
    "--version")
      if [ $# -lt 2 ]
        then
        echo "ERROR: --version expects a kernel version string!"
        echo
        usage
        exit 1
      fi

      VERSION="$2"
      shift 2;;
    *)
      echo "ERROR: Unknown option \"$CMD\". Aborting..."
      echo

      usage
      exit 1;;
  esac
done


# Branch depending on command
case "$CMD" in 
  "list")
    list_kernels;;
  "set")
    if [ -z "$VERSION" ]
      then
      echo "ERROR: Missing version string. Did you specify --version?"
      exit 1
    fi

    set_kernel;;
  "help")
    usage;;
  *)
    echo "ERROR: Unknown command \"$CMD\". Aborting..."
    exit 1;;
esac

exit 0
