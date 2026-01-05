#!/bin/bash
# Create IAM role for EC2 with S3 + SSM access
set -e

ROLE_NAME="s3bench-ec2-role"
BUCKET_NAME="${S3BENCH_BUCKET:-s3bench-test-eu-central-1}"

echo "Creating IAM role: $ROLE_NAME"

# Create trust policy for EC2
cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Create S3 access policy
cat > /tmp/s3-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": [
      "arn:aws:s3:::${BUCKET_NAME}",
      "arn:aws:s3:::${BUCKET_NAME}/*"
    ]
  }]
}
EOF

# Create role
aws iam create-role \
  --role-name "$ROLE_NAME" \
  --assume-role-policy-document file:///tmp/trust-policy.json \
  --description "Role for S3 benchmark EC2 instance"

# Attach SSM managed policy
aws iam attach-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

# Create and attach S3 policy
aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name "s3bench-s3-access" \
  --policy-document file:///tmp/s3-policy.json

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name "$ROLE_NAME"

aws iam add-role-to-instance-profile \
  --instance-profile-name "$ROLE_NAME" \
  --role-name "$ROLE_NAME"

echo "Waiting for instance profile to propagate..."
sleep 10

echo "Done! Role '$ROLE_NAME' created with SSM and S3 access."
