#!/bin/bash

set -euo pipefail
umask 077

: "${REGION:=eu-central-1}"
: "${PROFILE:=}"
: "${NONCE:="$(tr --delete --complement A-Za-z0-9 </dev/urandom | head --bytes 8)"}"
: "${AMI_ID:=ami-0a5b5c0ea66ec560d}"
: "${INSTANCE_TYPE:=t2.micro}"
: "${VOLUME_SIZE:=20}"
: "${CIDR:=10.13.37.0/24}"
: "${INGRESS:=0.0.0.0/0}"

check_var() {
	if [[ "${!1}" == *" "* ]]; then
		echo "$1 must not contain spaces"
		exit 1
	fi
}

check_var PROFILE
check_var REGION

KEY_NAME="fastcall-key-$NONCE"
SECURITY_NAME="fastcall-security-group-$NONCE"
OUTPUT="--output json"
REGION="--region $REGION"
JQ="jq --raw-output --exit-status"

if [[ -n "${PROFILE}" ]]; then
	PROFILE="--profile $PROFILE"
else
	PROFILE=
fi

AWS="aws ec2 $OUTPUT $REGION $PROFILE"

finish() {
	set +e

	if [[ -n "${INSTANCE_ID-}" ]]; then
		$AWS terminate-instances \
			--instance-ids "$INSTANCE_ID" \
			&>/dev/null
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
trap finish EXIT

TMP_DIR="$(mktemp --directory --suffix .fastcall)"
IDENTITY="$TMP_DIR/id"

check_dependencies() {
	if ! (aws --version 2>/dev/null | grep -E '^aws-cli/2' &>/dev/null); then
		echo "AWS CLI (aws) version 2 must be installed."
		echo "  Website: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
		exit 1
	fi

	if ! jq --version &>/dev/null; then
		echo "jq must be installed."
		echo "  Debian: apt install jq"
		echo "  Arch Linux: apt install jq"
		echo "  Website: https://stedolan.github.io/jq/"
		exit 1
	fi
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

	read -p "Press Enter to teardown instance"
}

check_dependencies
create_instance
