#!/bin/bash
# Connect to s3bench EC2 instance via SSM
set -e

REGION="${AWS_REGION:-eu-central-1}"

if [ -z "$1" ]; then
  # Find running s3bench instance
  INSTANCE_ID=$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=s3bench" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text)

  if [ "$INSTANCE_ID" == "None" ] || [ -z "$INSTANCE_ID" ]; then
    echo "No running s3bench instance found. Launch one with ./ec2/launch.sh"
    exit 1
  fi
else
  INSTANCE_ID="$1"
fi

echo "Connecting to instance: $INSTANCE_ID"
aws ssm start-session --target "$INSTANCE_ID" --region "$REGION"
