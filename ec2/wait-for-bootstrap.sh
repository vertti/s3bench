#!/bin/bash
# Wait for EC2 user-data bootstrap to complete
set -e

INSTANCE_ID="${1:?Usage: $0 <instance-id>}"
REGION="${AWS_REGION:-eu-central-1}"
TIMEOUT="${TIMEOUT:-600}"  # 10 minutes default

echo "Waiting for bootstrap to complete on $INSTANCE_ID..." >&2

START_TIME=$(date +%s)

while true; do
    ELAPSED=$(($(date +%s) - START_TIME))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "Timeout waiting for bootstrap after ${TIMEOUT}s" >&2
        exit 1
    fi

    # Try to run a command via SSM - this checks both SSM agent readiness and config.sh existence
    COMMAND_ID=$(aws ssm send-command \
        --instance-ids "$INSTANCE_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["test -f /home/ec2-user/s3bench/config.sh && echo READY"]' \
        --region "$REGION" \
        --output text \
        --query 'Command.CommandId' 2>/dev/null) || {
        echo "  SSM agent not ready yet (${ELAPSED}s elapsed)..." >&2
        sleep 10
        continue
    }

    # Wait for command to complete (with short timeout)
    sleep 3

    # Check command result
    RESULT=$(aws ssm get-command-invocation \
        --command-id "$COMMAND_ID" \
        --instance-id "$INSTANCE_ID" \
        --region "$REGION" \
        --output json 2>/dev/null) || {
        echo "  Command still running (${ELAPSED}s elapsed)..." >&2
        sleep 5
        continue
    }

    STATUS=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Status'])")
    OUTPUT=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('StandardOutputContent', ''))")

    if [ "$STATUS" = "Success" ] && [ "$OUTPUT" = "READY" ]; then
        echo "Bootstrap complete! (${ELAPSED}s)" >&2
        exit 0
    fi

    echo "  Bootstrap not complete yet (${ELAPSED}s elapsed)..." >&2
    sleep 10
done
