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
DELOPTS=""                              # Options to delete if not specified in
                                        # $SETOPTS
SETOPTS=""                              # New options for starting the kernel


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
  echo "        If --setopts is given, this must be the last option since the "
  echo "        entire following command line will be taken verbatim as a "
  echo "        string of multiple kernel parameters that will be injected "
  echo "        into the booting config. The script will try to preserve the "
  echo "        existing kernel options, only changing those "
  echo "        specified by the option strings. The --delopts option must be"
  echo "        followed by a comma-separated list of kernel option names that"
  echo "        should be removed from the kernel command line if not included"
  echo "        in the option names passed to --setopts."
  echo "        Options: --version , --delopts (optional), --setopts (optional)"
  echo
  echo "help -  Outputs this help and exits."
  echo "        Options: none"
  echo 
  echo "Options:"
  echo "============================================"
  echo
  echo "--delopts - A comma-separated list of kernel options that should be"
  echo "            removed from the kernel's command line parameters. If"
  echo "            the respective option name is included in the option"
  echo "            string of --setopts as well, the option will be replaced"
  echo "            with the value specified in --setopts instead of removing"
  echo "            it. Also note the the list of --delopts must only contain"
  echo "            the option *names*, not any values assigned to it. E.g."
  echo "            if your kernel config contains the option mitigations=auto"
  echo "            and you want to remove it, just specify "
  echo "            --delopts mitigations"
  echo "--setopts - A comma-separated list of kernel options that should be"
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

  # find out path to bootloader config
  typeset bl_cfg_path=""
  if [ -d "/boot/grub2" ]
    then
    bl_cfg_path="/boot/grub2/grub.cfg"
  elif [ -d "/boot/grub" ]
    then
    bl_cfg_path="/boot/grub/grub.cfg"
  else
    echo "ERROR: Unable to locate bootloader config script. Aborting..."
    exit 1
  fi

  # Find out id of advanced booting options menu, it's the second last field
  # of the submenu line
  typeset -i menuline_wcnt=`cat $bl_cfg_path | grep submenu | head -n 1 | wc -w`
  typeset -i menuid_idx=$((menuline_wcnt - 1))

  typeset menuid=`cat $bl_cfg_path | grep "submenu" \
	                           | head -n 1 \
                                   | cut -d' ' -f${menuid_idx} \
                                   | tr -d "'"`

  # Find out id of specified kernel. Note the trailing ' when grepping: this
  # prevents us from running into prefixing issues (i.e., one kernel version
  # is an prefix of another, leading to ambiguous grep results). Again,
  # actual id is the second last field on the line.
  typeset -i kernid_wcnt=`cat $bl_cfg_path \
                                | grep "with Linux $VERSION'" | wc -w`
  typeset -i kernid_idx=$((kernid_wcnt - 1))

  # Remove leading whitespace from menu entry by piping stuff through xargs
  typeset kernid=`cat $bl_cfg_path | grep "with Linux $VERSION'" \
                                   | xargs \
                                   | cut -d' ' -f${kernid_idx} \
                                   | tr -d "'"`

  # update default boot entry, disable silent booting, and set kernel options 
  typeset grubconf=`cat /etc/default/grub | \
                    awk -v krn="$kernid" -v men="$menuid" -v opt="$SETOPTS" \
                        -v delopt="$DELOPTS" '
     
     # catch default boot entry
     /^GRUB_DEFAULT=.*$/ { print("GRUB_DEFAULT=\"" men ">" krn "\""); 
                           next;
                         }

     # replace option string with the one passed by the user.
     /^GRUB_CMDLINE_LINUX=.*$/ {
            # options that are currently active in the system
            gsub("GRUB_CMDLINE_LINUX=", "");
            gsub("\"", "");

            cur_opt_cnt = split($0, cur_opt_arr, " ");
            new_opt_cnt = split(opt, new_opt_arr, " ");
            del_opt_cnt = split(delopt, del_opt_arr, ",");

            # transform del_opt_arr into a list of del_opt tags for easier 
            # search for existence of array members
            for (idx in del_opt_arr) {
                del_opt_tags[del_opt_arr[idx]] = "";
            }

            for (i = 1; i <= new_opt_cnt; i++) {
                idx = index(new_opt_arr[i], "=");
                if (idx == 0) {
                    new_opt_tag[new_opt_arr[i]] = i;
                }
                else {
                    tag = substr(new_opt_arr[i], 0, idx - 1);
                    new_opt_tag[tag] = i;
                }
            }

            # print bracketing variable name
            printf("GRUB_CMDLINE_LINUX=\"");
            
            for (j = 1; j <= cur_opt_cnt; j++) {
                cur_tag = "";

                idx = index(cur_opt_arr[j], "=");
                if (idx == 0) {
                    cur_tag = cur_opt_arr[j];
                }
                else {
                    cur_tag = substr(cur_opt_arr[j], 0, idx - 1);
                }
                
                if (cur_tag in new_opt_tag) {
                    printf(new_opt_arr[new_opt_tag[cur_tag]]);
                    delete new_opt_arr[new_opt_tag[cur_tag]];
                }
                else {
                    # skip options that should be deleted and are not in the
                    # list of new / modified options
                    if (cur_tag in del_opt_tags) {
                        continue;
                    }
                    else {
                        printf(cur_opt_arr[j]);
                    }
                }

                printf(" ");
            }

            # output remaining new options
            for (new_opt in new_opt_arr) {
                printf(new_opt_arr[new_opt] " ");
            }

            # close option string (with newline at the end)
            print("\"");
            next;
          }

     # clear GRUB_CMDLINE_LINUX_DEFAULT, too
     /^GRUB_CMDLINE_LINUX_DEFAULT=.*$/ { 
            # options that are currently active in the system
            gsub("GRUB_CMDLINE_LINUX_DEFAULT=", "");
            gsub("\"", "");

            cur_opt_cnt = split($0, cur_opt_arr, " ");
            new_opt_cnt = split(opt, new_opt_arr, " ");
            del_opt_cnt = split(delopt, del_opt_arr, ",");

            # transform del_opt_arr into a list of del_opt tags for easier 
            # search for existence of array members
            for (idx in del_opt_arr) {
                del_opt_tags[del_opt_arr[idx]] = "";
            }

            for (i = 1; i <= new_opt_cnt; i++) {
                idx = index(new_opt_arr[i], "=");
                if (idx == 0) {
                    new_opt_tag[new_opt_arr[i]] = i;
                }
                else {
                    tag = substr(new_opt_arr[i], 0, idx - 1);
                    new_opt_tag[tag] = i;
                }
            }

            # print bracketing variable name
            printf("GRUB_CMDLINE_LINUX_DEFAULT=\"");
            
            for (j = 1; j <= cur_opt_cnt; j++) {
                cur_tag = "";

                idx = index(cur_opt_arr[j], "=");
                if (idx == 0) {
                    cur_tag = cur_opt_arr[j];
                }
                else {
                    cur_tag = substr(cur_opt_arr[j], 0, idx - 1);
                }
                
                if (cur_tag in new_opt_tag) {
                    printf(new_opt_arr[new_opt_tag[cur_tag]]);
                    delete new_opt_arr[new_opt_tag[cur_tag]];
                }
                else {
                    # skip options that should be deleted and are not in the
                    # list of new / modified options
                    if (cur_tag in del_opt_tags) {
                        continue;
                    }
                    else {
                        printf(cur_opt_arr[j]);
                    }
                }

                printf(" ");
            }

            # output remaining new options
            for (new_opt in new_opt_arr) {
                printf(new_opt_arr[new_opt] " ");
            }

            # close option string (with newline at the end)
            print("\"");
            next;
          }

     # default, output line without modifications
     { print($0); }
  '`

  # Show user the new bootloader config file and ask for acknowledgement
  echo
  echo "Attempting to write the following into /etc/default/grub:"
  echo "========================================================="
  echo
  echo "$grubconf"
  echo 
  echo "========================================================="
  echo "If you are sure that this is reasonable, type "YeS" to "
  echo "continue. If in doubt, type anything else to abort."
  echo
  echo "Do you want to continue updating your bootloader config?"

  read confirm

  if [ ! "$confirm" == "YeS" ]
    then
    echo "User decided do refuse suggested change to bootloader config."
    echo "Exiting..."
    exit 1
  fi

  echo "$grubconf" > /etc/default/grub
  # update bootloader 
  if [ -f "/sbin/update-bootloader" ]
    then
    update-bootloader
  elif [ -f "/usr/sbin/update-grub" ]
    then
    update-grub
  else
    echo "ERROR: No known tool for updating the booloader config. Aborting..."
    exit 1
  fi

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
    "--delopts")
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
        echo "ERROR: --delopts expects list with kernel options!"
        echo
        usage
        exit 1
      fi

      # take second arg as comma-separated list of option names to remove from
      # the kernel command line if not specified lateron via --setopts
      DELOPTS="$2"
      shift 2;;
    "--setopts")
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
        echo "ERROR: --setopts expects list with kernel options!"
        echo
        usage
        exit 1
      fi

      shift 1
    
      # take entire remaining command line as booting options
      SETOPTS="$@"
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
