#!/bin/bash

set -euo pipefail
umask 077

REGION="${REGION:-eu-central-1}"
PROFILE="${PROFILE:-}"
NONCE="${NONCE:-$(
	set +o pipefail
	tr --delete --complement A-Za-z0-9 </dev/urandom | head --bytes 8
)}"
AMI_ID="${AMI_ID:-ami-0a5b5c0ea66ec560d}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
VOLUME_SIZE="${VOLUME_SIZE:-20}"
CIDR="${CIDR:-10.13.37.0/24}"
INGRESS="${INGRESS:-0.0.0.0/0}"
SSH_USER="${SSH_USER:-admin}"
GIT_CHECKOUT="${GIT_CHECKOUT:-master}"
UPLOAD_CHANGES="${UPLOAD_CHANGES:-}"

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
KEY_NAME="fastcall-key-$NONCE"
SECURITY_NAME="fastcall-security-group-$NONCE"
OUTPUT="--output json"
REGION="--region $REGION"
JQ="jq --raw-output --exit-status"
SSH_OPT="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null \
-o LogLevel=ERROR"

if [[ -n "${PROFILE}" ]]; then
	PROFILE="--profile $PROFILE"
else
	PROFILE=
fi

AWS="aws ec2 $OUTPUT $REGION $PROFILE"

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

finish() {
	set +e

	read -p "Press Enter to tear instance down"

	if [[ -n "${INSTANCE_ID-}" ]]; then
		$AWS terminate-instances \
			--instance-ids "$INSTANCE_ID" \
			&>/dev/null
		echo "waiting for instance to terminate..."
		$AWS wait instance-terminated \
			--instance-ids "$INSTANCE_ID" \
			&>/dev/null
	fi

	$AWS delete-key-pair --key-name "$KEY_NAME" &>/dev/null

	if [[ -n ${SECURITY_ID-} ]]; then
		$AWS delete-security-group \
			--group-id "$SECURITY_ID"
	fi

	rm --recursive --force "$TMP_DIR"
}

wait_ssh() {
	echo "waiting for SSH server to come up..."
	until $SSH true; do
		sleep 5
	done
	echo "SSH working"
}

create_instance() {
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

	echo "creating instance..."
	OUTPUT="$(
		$AWS run-instances \
			--image-id "$AMI_ID" \
			--instance-type "$INSTANCE_TYPE" \
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
	SSH="ssh $SSH_OPT -i $IDENTITY $SSH_USER@$IP_ADDR"

	wait_ssh
}

prepare() {
	echo "preparing instance for bulding..."
	cat "$SPATH/prepare.sh" | $SSH "export GIT_CHECKOUT=$GIT_CHECKOUT; bash"
	echo "instance prepared"

	# This requires all necessary files to be tracked by Git!
	if [[ -n "$UPLOAD_CHANGES" ]]; then
		echo "uploading local changes..."
		cd "$SPATH/.."
		OUTPUT="$(
			git diff "$GIT_CHECKOUT" --
		)"
		if [[ -n "$OUTPUT" ]]; then
			echo "$OUTPUT" | $SSH "cd fastcall-spma; git apply"
			$SSH "cd fastcall-spma; git add --all; git commit --message 'local changes'"
		fi
		cd - >/dev/null
		echo "changes uploaded"
	fi

	echo "building and installing..."
	$SSH fastcall-spma/install.sh
	echo "instance ready for benchmarking"
}

benchmark() {
	while :; do
		RET=0
		$SSH "cd fastcall-spma; ./aws/benchmark.sh" || RET=$?
		if [[ "$RET" -eq 0 ]]; then
			return
		elif [[ "$RET" -ne 1 ]]; then
			exit "$RET"
		fi

		echo "rebooting instance..."
		$AWS reboot-instances --instance-ids "$INSTANCE_ID"
		# Wait for instance to start rebooting
		sleep 5
		$AWS wait instance-running --instance-ids "$INSTANCE_ID"
		echo "instance came back up"
		wait_ssh
	done
}

retrieve_data() {
	echo "retrieving benchmark results"
	cd "$SPATH/.."
	$SSH "cd fastcall-spma; git add --all; git diff --staged" | git apply
	cd - >/dev/null
	echo "benchmark results applied to local repository"
}

check_dependencies

trap finish EXIT

TMP_DIR="$(mktemp --directory --suffix .fastcall)"
IDENTITY="$TMP_DIR/id"

create_instance
prepare
benchmark
retrieve_data
