#!/bin/bash
# Cleanup s3bench resources
set -e

REGION="${AWS_REGION:-eu-central-1}"
ROLE_NAME="s3bench-ec2-role"
BUCKET_NAME="s3bench-test-eu-central-1"

echo "S3bench cleanup"
echo "==============="

# Terminate EC2 instances
echo ""
echo "Looking for s3bench instances..."
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region "$REGION" \
  --filters "Name=tag:Name,Values=s3bench" "Name=instance-state-name,Values=running,stopped" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text)

if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
  echo "Terminating instances: $INSTANCE_IDS"
  aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region "$REGION"
  echo "Waiting for termination..."
  aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region "$REGION"
  echo "Instances terminated."
else
  echo "No s3bench instances found."
fi

# Ask about IAM role
echo ""
read -p "Delete IAM role '$ROLE_NAME'? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Deleting IAM role..."

  # Remove role from instance profile
  aws iam remove-role-from-instance-profile \
    --instance-profile-name "$ROLE_NAME" \
    --role-name "$ROLE_NAME" 2>/dev/null || true

  # Delete instance profile
  aws iam delete-instance-profile \
    --instance-profile-name "$ROLE_NAME" 2>/dev/null || true

  # Detach managed policy
  aws iam detach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore" 2>/dev/null || true

  # Delete inline policy
  aws iam delete-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "s3bench-s3-access" 2>/dev/null || true

  # Delete role
  aws iam delete-role --role-name "$ROLE_NAME" 2>/dev/null || true

  echo "IAM role deleted."
fi

# Ask about S3 bucket
echo ""
read -p "Delete S3 bucket '$BUCKET_NAME'? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Deleting S3 bucket..."
  aws s3 rb "s3://$BUCKET_NAME" --force --region "$REGION" 2>/dev/null || true
  echo "S3 bucket deleted."
fi

echo ""
echo "Cleanup complete!"
