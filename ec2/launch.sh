#!/bin/bash
# Launch EC2 instance for s3bench
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-eu-central-1}"
INSTANCE_TYPE="${INSTANCE_TYPE:-c5n.2xlarge}"
AMI_ID="${AMI_ID:-ami-0669b163befffbdfc}"  # Amazon Linux 2023 in eu-central-1
ROLE_NAME="s3bench-ec2-role"

echo "Launching EC2 instance..."
echo "  Region: $REGION"
echo "  Instance type: $INSTANCE_TYPE"
echo "  AMI: $AMI_ID"

# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" --filters "Name=isDefault,Values=true" --query 'Vpcs[0].VpcId' --output text)

# Create or get security group with outbound access
SG_NAME="s3bench-sg"
SG_ID=$(aws ec2 describe-security-groups --region "$REGION" --filters "Name=group-name,Values=$SG_NAME" "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)

if [ "$SG_ID" == "None" ] || [ -z "$SG_ID" ]; then
  echo "Creating security group..."
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

echo "  Security group: $SG_ID"

# Launch instance
RESULT=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --iam-instance-profile Name="$ROLE_NAME" \
  --security-group-ids "$SG_ID" \
  --region "$REGION" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=s3bench}]' \
  --user-data file://"$SCRIPT_DIR/user-data.sh" \
  --output json)

INSTANCE_ID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Instances'][0]['InstanceId'])")

echo ""
echo "Instance launched: $INSTANCE_ID"
echo ""
echo "Waiting for instance to start..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"

echo "Instance is running!"
echo ""
echo "Wait ~3-5 minutes for user-data setup to complete, then connect with:"
echo ""
echo "  ./ec2/connect.sh $INSTANCE_ID"
echo ""
echo "Or manually:"
echo "  aws ssm start-session --target $INSTANCE_ID --region $REGION"
echo ""
echo "To check setup progress, run in the session:"
echo "  tail -f /var/log/user-data.log"
