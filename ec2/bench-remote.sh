#!/bin/bash
# Full automation: launch EC2 → run benchmarks → get results → terminate
set -e

INSTANCE_TYPE="${1:?Usage: $0 <instance-type> (e.g., c5n.xlarge, c5n.4xlarge, c5n.9xlarge)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGION="${AWS_REGION:-eu-central-1}"
RESULTS_DIR="${SCRIPT_DIR}/../results"

mkdir -p "$RESULTS_DIR"

# Set concurrency levels based on instance bandwidth tier
# High concurrency is pointless on bandwidth-limited instances
case "$INSTANCE_TYPE" in
    c5n.9xlarge|c5n.18xlarge|c5n.metal)
        # 50-100 Gbps - test full range
        CONCURRENCY_LEVELS="8 16 32 64 128"
        ;;
    c5n.xlarge|c5n.2xlarge|c5n.4xlarge)
        # 10-25 Gbps burst - test full range
        CONCURRENCY_LEVELS="8 16 32 64 128"
        ;;
    m5.xlarge|t3.xlarge|t3.large)
        # 1-10 Gbps burst - moderate concurrency
        CONCURRENCY_LEVELS="8 16 32"
        ;;
    m5.large)
        # 750 Mbps baseline, 10 Gbps burst - burst exhausts quickly at high concurrency
        CONCURRENCY_LEVELS="8 16"
        ;;
    t3.medium|t3.small|t3.micro|t3.nano)
        # Very limited bandwidth - minimal concurrency
        CONCURRENCY_LEVELS="4 8"
        ;;
    *)
        # Default: moderate range
        CONCURRENCY_LEVELS="8 16 32"
        ;;
esac

echo "Using concurrency levels: $CONCURRENCY_LEVELS" >&2

# Cleanup function to ensure instance is terminated
INSTANCE_ID=""
cleanup() {
    if [ -n "$INSTANCE_ID" ]; then
        echo "" >&2
        echo "Terminating instance $INSTANCE_ID..." >&2
        aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" --region "$REGION" >/dev/null 2>&1 || true
        echo "Instance terminated." >&2
    fi
}
trap cleanup EXIT

echo "========================================" >&2
echo "Benchmark: $INSTANCE_TYPE" >&2
echo "========================================" >&2
echo "" >&2

# 1. Launch instance
echo "Step 1: Launching EC2 instance..." >&2
INSTANCE_ID=$("$SCRIPT_DIR/launch.sh" "$INSTANCE_TYPE")
echo "Instance ID: $INSTANCE_ID" >&2

# 2. Wait for bootstrap
echo "" >&2
echo "Step 2: Waiting for bootstrap..." >&2
"$SCRIPT_DIR/wait-for-bootstrap.sh" "$INSTANCE_ID"

# 3. Run benchmark via SSM
echo "" >&2
echo "Step 3: Running benchmarks (this may take 30-60 minutes)..." >&2

# Send command with extended timeout (4 hours for slow instances)
# Run as ec2-user since mise is installed there
# Use CONCURRENCY_OVERRIDE env var to set instance-appropriate concurrency
COMMAND_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"sudo -u ec2-user bash -c 'cd /home/ec2-user/s3bench && source ~/.bashrc && CONCURRENCY_OVERRIDE=\\\"$CONCURRENCY_LEVELS\\\" ./bench.sh' 2>&1\"]" \
    --timeout-seconds 14400 \
    --region "$REGION" \
    --output text \
    --query 'Command.CommandId')

echo "SSM Command ID: $COMMAND_ID" >&2

# Poll for completion
POLL_FAILURES=0
MAX_POLL_FAILURES=30
LAST_STATUS=""
SEEN_IN_PROGRESS=false

while true; do
    RESULT=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --output json 2>/dev/null) || {
        POLL_FAILURES=$((POLL_FAILURES + 1))
        # Only give up if we haven't seen the command running yet
        if [ "$SEEN_IN_PROGRESS" = "false" ] && [ "$POLL_FAILURES" -ge "$MAX_POLL_FAILURES" ]; then
            echo "  Command never started after $POLL_FAILURES attempts, giving up" >&2
            exit 1
        fi
        echo "  SSM API error (attempt $POLL_FAILURES, will retry)..." >&2
        sleep 10
        continue
    }

    # Reset failure counter on successful API call
    POLL_FAILURES=0

    STATUS=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Status'])")

    case "$STATUS" in
        "Success")
            echo "Benchmark completed successfully!" >&2
            break
            ;;
        "Failed"|"Cancelled"|"TimedOut")
            echo "Benchmark failed with status: $STATUS" >&2
            echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('StandardErrorContent', ''))" >&2
            exit 1
            ;;
        "InProgress"|"Pending")
            SEEN_IN_PROGRESS=true
            if [ "$STATUS" != "$LAST_STATUS" ]; then
                echo "  Status: $STATUS" >&2
            fi
            LAST_STATUS="$STATUS"
            sleep 30
            ;;
        *)
            if [ "$STATUS" != "$LAST_STATUS" ]; then
                echo "  Status: $STATUS" >&2
            fi
            LAST_STATUS="$STATUS"
            sleep 30
            ;;
    esac
done

# 4. Get results file from instance
echo "" >&2
echo "Step 4: Retrieving results..." >&2

# Find the latest results file
FIND_CMD_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["ls -t /home/ec2-user/s3bench/results/*.json 2>/dev/null | head -1"]' \
    --region "$REGION" \
    --output text \
    --query 'Command.CommandId')

sleep 3

REMOTE_FILE=$(aws ssm get-command-invocation \
    --command-id "$FIND_CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --output text \
    --query 'StandardOutputContent' | tr -d '\n')

if [ -z "$REMOTE_FILE" ]; then
    echo "ERROR: No results file found on instance!" >&2
    exit 1
fi

echo "Remote results file: $REMOTE_FILE" >&2

# Read the results via SSM
CAT_CMD_ID=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters "commands=[\"cat $REMOTE_FILE\"]" \
    --region "$REGION" \
    --output text \
    --query 'Command.CommandId')

sleep 3

RESULTS_JSON=$(aws ssm get-command-invocation \
    --command-id "$CAT_CMD_ID" \
    --instance-id "$INSTANCE_ID" \
    --region "$REGION" \
    --output text \
    --query 'StandardOutputContent')

# Save results locally with instance type in filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOCAL_FILE="${RESULTS_DIR}/${INSTANCE_TYPE}_${TIMESTAMP}.json"
echo "$RESULTS_JSON" > "$LOCAL_FILE"

echo "Results saved to: $LOCAL_FILE" >&2
echo "" >&2

# 5. Instance will be terminated by cleanup trap
echo "Step 5: Cleanup..." >&2

# Output the local file path to stdout for scripting
echo "$LOCAL_FILE"
