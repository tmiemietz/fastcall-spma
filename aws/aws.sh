#!/bin/bash

# This script automatically executes the benchmarks on AWS EC2 instance(s) and
# downloads the created results.
# Please make sure that you have the aws-cli version 2 installed and configured.
# This will incur costs in your AWS account.
#
# Usage: ./aws.sh

set -euo pipefail
umask 077

# AWS region where the instance(s) should be started.
REGION="${REGION:-eu-central-1}"
# Optional aws-cli profile.
PROFILE="${PROFILE:-}"
# Used for creating unique names in AWS.
NONCE="${NONCE:-$(
	set +o pipefail
	tr --delete --complement A-Za-z0-9 </dev/urandom | head --bytes 8
)}"
# Instance types for EC2 to spin up; space-separated.
# Please select instance types which support hardware performance counters.
read -a INSTANCE_TYPES <<<"${INSTANCE_TYPES:-t3.micro t4g.micro}"
# The disk image to use for each architecture.
# The script is designed for Debian Bullseye.
# Please make sure that the AMI is available in the specified region.
AMI_ID_X86="${AMI_ID_X86:-ami-0a5b5c0ea66ec560d}"
AMI_ID_ARM="${AMI_ID_ARM:-ami-07751393ac2b1c0ed}"
read -a INSTANCE_TYPES <<<"${INSTANCE_TYPES:-t3.micro t4g.micro}"
# Available storage space.
VOLUME_SIZE="${VOLUME_SIZE:-20}"
# Allow incoming SSH traffic from following IP range to the created instance(s).
INGRESS="${INGRESS:-0.0.0.0/0}"
# User name of the default user for use with SSH. This is AMI-specific.
SSH_USER="${SSH_USER:-admin}"
# The branch/commit of this repository which will be cloned onto the
# instance(s).
GIT_CHECKOUT="${GIT_CHECKOUT:-master}"
# Upload all changes between GIT_CHECKOUT and HEAD to the instance(s)?
UPLOAD_CHANGES="${UPLOAD_CHANGES:-}"

# Assert that the (by-name) given variable does not contain spaces.
check_var() {
	if [[ "${!1}" == *" "* ]]; then
		echo "$1 must not contain spaces"
		exit 1
	fi
}

check_var PROFILE
check_var REGION
check_var SSH_USER
check_var GIT_CHECKOUT

SPATH="$(realpath "$(dirname $0)")"
# Name for the AWS SSH key.
KEY_NAME="fastcall-key-$NONCE"
# Name for the security group.
SECURITY_NAME="fastcall-security-group-$NONCE"
OUTPUT="--output json"
REGION="--region $REGION"
JQ="jq --raw-output --exit-status"
# We do not want to pollute the known_hosts file.
SSH_OPT="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
-o LogLevel=ERROR"

if [[ -n "${PROFILE}" ]]; then
	PROFILE="--profile $PROFILE"
else
	PROFILE=
fi

AWS="aws ec2 $OUTPUT $REGION $PROFILE"

# Assert that all required programs are installed.
check_dependencies() {
	if ! (aws --version 2>/dev/null | grep -E '^aws-cli/2' &>/dev/null); then
		echo "AWS CLI (aws) version 2 must be installed."
		echo "  Website: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
		exit 1
	fi

	if ! jq --version &>/dev/null; then
		echo "jq must be installed."
		echo "  Debian: apt install jq"
		echo "  Arch Linux: pacman -S jq"
		echo "  Website: https://stedolan.github.io/jq/"
		exit 1
	fi

	if ! git --version &>/dev/null; then
		echo "git must be installed."
		echo "  Debian: apt install git"
		echo "  Arch Linux: pacman -S git"
		exit 1
	fi

	if ! ssh -V &>/dev/null; then
		echo "ssh must be installed."
		echo "  Debian: apt install ssh"
		echo "  Arch Linux: pacman -S openssh"
		exit 1
	fi
}

# Terminate current instance.
terminate() {
	if [[ -n "${INSTANCE_ID-}" ]]; then
		$AWS terminate-instances \
			--instance-ids "$INSTANCE_ID" \
			&>/dev/null
		echo "waiting for instance to terminate..."
		$AWS wait instance-terminated \
			--instance-ids "$INSTANCE_ID" \
			&>/dev/null

		INSTANCE_ID=
	fi
}

# Cleanup routine to delete created AWS resources.
finish() {
	EXIT="$?"
	set +e

	if [[ "$EXIT" -ne 0 ]]; then
		# Give the user a chance to manually connect to the instance before
		# cleanup.
		if [[ -n "${SSH-}" ]]; then
			echo "You can connect to the failed instance via:"
			echo "  $SSH"
		fi
		read -p "Press Enter to tear AWS environment down"
	fi

	terminate

	# Delete key pair.
	$AWS delete-key-pair --key-name "$KEY_NAME" &>/dev/null

	# Delete security group.
	if [[ -n "${SECURITY_ID-}" ]]; then
		$AWS delete-security-group \
			--group-id "$SECURITY_ID"
	fi

	# Delete temporary directory.
	rm --recursive --force "$TMP_DIR"
}

# Helper function to wait for SSH connectivity.
wait_ssh() {
	echo "waiting for SSH server to come up..."
	until $SSH true; do
		sleep 5
	done
	echo "SSH working"
}

# Setup AWS environment.
setup_aws() {
	echo "creating security group ..."
	OUTPUT="$(
		$AWS create-security-group \
			--group-name "$SECURITY_NAME" \
			--description "fastcall security group"
	)"
	SECURITY_ID="$($JQ .GroupId <<<"$OUTPUT")"
	$AWS authorize-security-group-ingress \
		--group-id "$SECURITY_ID" \
		--protocol tcp \
		--port 22 \
		--cidr "$INGRESS" \
		>/dev/null
	echo "security group $SECURITY_NAME created"

	echo "creating SSH key pair..."
	$AWS create-key-pair \
		--key-name "$KEY_NAME" |
		$JQ '.KeyMaterial' >"$IDENTITY"
	echo "private SSH key of $KEY_NAME written to $IDENTITY"
}

# Create a new AWS instance.
create_instance() {
	echo "querying architecture for $1..."
	OUTPUT="$(
		$AWS describe-instance-types --instance-types "$1"
	)"
	ARCH="$(
		$JQ .InstanceTypes[0].ProcessorInfo.SupportedArchitectures[0] <<<"$OUTPUT"
	)"
	if [[ "$ARCH" == x86_64 ]]; then
		AMI_ID="$AMI_ID_X86"
	elif [[ "$ARCH" == arm64 ]]; then
		AMI_ID="$AMI_ID_ARM"
	else
		echo "architecture $ARCH unsupported"
		exit 1
	fi
	echo "architecture is $ARCH"

	echo "creating instance $1..."
	OUTPUT="$(
		$AWS run-instances \
			--image-id "$AMI_ID" \
			--instance-type "$1" \
			--key-name "$KEY_NAME" \
			--security-group-ids "$SECURITY_ID" \
			--associate-public-ip-address \
			--block-device-mappings "DeviceName=/dev/xvda,Ebs={VolumeSize=$VOLUME_SIZE}"
	)"
	INSTANCE_ID="$($JQ .Instances[0].InstanceId <<<"$OUTPUT")"
	echo "instance $INSTANCE_ID created"

	echo "waiting for instance to come up..."
	$AWS wait instance-running --instance-ids "$INSTANCE_ID"
	OUTPUT="$(
		$AWS describe-instances --instance-ids "$INSTANCE_ID"
	)"
	IP_ADDR="$($JQ .Reservations[0].Instances[0].PublicIpAddress <<<"$OUTPUT")"
	echo "instance came up with address $IP_ADDR"

	check_var IP_ADDR
	# Assemble SSH command.
	SSH="ssh $SSH_OPT -i $IDENTITY $SSH_USER@$IP_ADDR"

	wait_ssh
}

# Prepare the instance by installing packages and the custom kernels.
prepare() {
	# Execute ./prepare.sh on the instance.
	echo "preparing instance for building..."
	cat "$SPATH/prepare.sh" | $SSH "export GIT_CHECKOUT=$GIT_CHECKOUT; bash"
	echo "instance prepared"

	# This requires all necessary files to be tracked by Git!
	if [[ -n "$UPLOAD_CHANGES" ]]; then
		echo "uploading local changes..."
		cd "$SPATH/.."
		GIT_DIFF=${GIT_DIFF-"$(
			git diff "$GIT_CHECKOUT" --
		)"}
		if [[ -n "$GIT_DIFF" ]]; then
			echo "$GIT_DIFF" | $SSH "cd fastcall-spma; git apply"
			$SSH "cd fastcall-spma; git add --all; git commit --message 'local changes'"
		fi
		cd - >/dev/null
		echo "changes uploaded"
	fi

	# Execute the cloned ../install.sh on the server.
	echo "building and installing..."
	$SSH fastcall-spma/install.sh
	echo "instance ready for benchmarking"
}

# Execute all benchmarks and restart the server with different configurations
# until all measurements are taken.
benchmark() {
	$SSH "cd fastcall-spma; ./aws/delete_results.sh"

	while :; do
		# Execute the cloned ./benchmark.sh.
		RET=0
		$SSH "cd fastcall-spma; ./aws/benchmark.sh" || RET=$?
		if [[ "$RET" -eq 0 ]]; then
			# Return when all benchmarks are finished.
			return
		elif [[ "$RET" -ne 1 ]]; then
			exit "$RET"
		fi

		# Reboot instance to start with new kernel configuration.
		echo "rebooting instance..."
		$AWS reboot-instances --instance-ids "$INSTANCE_ID"
		# Wait for instance to start rebooting
		sleep 60
		$AWS wait instance-running --instance-ids "$INSTANCE_ID"
		echo "instance came back up"
		wait_ssh
	done
}

# Calculate changes remotely and apply them locally.
retrieve_data() {
	echo "retrieving benchmark results"
	cd "$SPATH/.."
	$SSH "cd fastcall-spma; git add --all; git diff --staged" | git apply
	cd - >/dev/null
	echo "benchmark results applied to local repository"
}

check_dependencies

# Execute cleanup code on error.
trap finish EXIT

# Create a temporary directory.
TMP_DIR="$(mktemp --directory --suffix .fastcall)"
# SSH private key location.
IDENTITY="$TMP_DIR/id"

# Iterate through all instance types and perform benchmarks for every type.
setup_aws
for type in "${INSTANCE_TYPES[@]}"; do
	create_instance "$type"
	prepare
	benchmark
	retrieve_data
	terminate
done
