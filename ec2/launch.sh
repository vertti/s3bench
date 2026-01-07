#!/bin/bash
# Launch EC2 instance for s3bench
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-eu-central-1}"
AMI_ID="${AMI_ID:-ami-0669b163befffbdfc}"  # Amazon Linux 2023 in eu-central-1
ROLE_NAME="s3bench-ec2-role"

# Accept instance type as CLI arg, then env var, then default
INSTANCE_TYPE="${1:-${INSTANCE_TYPE:-c5n.2xlarge}}"

echo "Launching EC2 instance..." >&2
echo "  Region: $REGION" >&2
echo "  Instance type: $INSTANCE_TYPE" >&2
echo "  AMI: $AMI_ID" >&2

# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)

# Create or get security group with outbound access
SG_NAME="s3bench-sg"
SG_ID=$(aws ec2 describe-security-groups --region "$REGION" --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
  echo "Creating security group..." >&2
  SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "Security group for s3bench EC2 instances" \
    --vpc-id "$VPC_ID" \
    --region "$REGION" \
    --query 'GroupId' --output text)
  # Default SG has all outbound allowed, but let's be explicit
  aws ec2 authorize-security-group-egress \
    --group-id "$SG_ID" \
    --protocol -1 \
    --cidr 0.0.0.0/0 \
    --region "$REGION" 2>/dev/null || true
fi

echo "  Security group: $SG_ID" >&2

# Launch instance with 20GB root volume (default 8GB fills up on small instances)
RESULT=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --iam-instance-profile Name="$ROLE_NAME" \
  --security-group-ids "$SG_ID" \
  --region "$REGION" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=s3bench}]' \
  --user-data file://"$SCRIPT_DIR/user-data.sh" \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --output json)

INSTANCE_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Instances'][0]['InstanceId'])")

echo "" >&2
echo "Instance launched: $INSTANCE_ID" >&2
echo "" >&2
echo "Waiting for instance to start..." >&2
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

echo "Instance is running!" >&2

# Output instance ID to stdout for scripting
echo "$INSTANCE_ID"
