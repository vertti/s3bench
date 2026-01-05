#!/bin/bash
# EC2 user-data script for s3bench setup
set -ex

# Log everything
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting s3bench setup..."

# Install dependencies
yum install -y git

# Switch to ec2-user for the rest
su - ec2-user << 'USERSCRIPT'
set -ex

# Install mise
curl https://mise.run | sh
echo 'eval "$(/home/ec2-user/.local/bin/mise activate bash)"' >> ~/.bashrc

# Clone repo
cd /home/ec2-user
git clone https://github.com/vertti/s3bench.git
cd s3bench

# Trust and install tools
/home/ec2-user/.local/bin/mise trust
/home/ec2-user/.local/bin/mise install

# Install s5cmd
/home/ec2-user/.local/bin/mise exec -- go install github.com/peak/s5cmd/v2@latest

# Create config
cat > config.sh << 'EOF'
export S3_BUCKET="s3bench-test-eu-central-1"
export S3_KEY="test-3gb.bin"
export S3_REGION="eu-central-1"
export AWS_PROFILE=""
export ITERATIONS=3
export FILE_SIZE_BYTES=3221225472
export CONCURRENCY_LEVELS="8 16 32 64 128"
export PART_SIZES_MB="16 32 64 128"
EOF

echo "s3bench setup complete!"
USERSCRIPT

echo "User-data script finished!"
