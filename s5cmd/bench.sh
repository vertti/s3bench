#!/bin/bash
# s5cmd benchmark script
set -e

# Parse arguments
BUCKET=""
KEY=""
CONCURRENCY=10
PART_SIZE_MB=16
ITERATIONS=3
FILE_SIZE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --bucket) BUCKET="$2"; shift 2 ;;
        --key) KEY="$2"; shift 2 ;;
        --concurrency) CONCURRENCY="$2"; shift 2 ;;
        --part-size-mb) PART_SIZE_MB="$2"; shift 2 ;;
        --iterations) ITERATIONS="$2"; shift 2 ;;
        --file-size) FILE_SIZE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

if [[ -z "$BUCKET" || -z "$KEY" || "$FILE_SIZE" -eq 0 ]]; then
    echo "Error: --bucket, --key, and --file-size are required" >&2
    exit 1
fi

echo "s5cmd benchmark: concurrency=$CONCURRENCY, part_size=${PART_SIZE_MB}MB" >&2

# Use S5CMD_PATH if provided, otherwise look in PATH
if [[ -n "$S5CMD_PATH" && -f "$S5CMD_PATH" ]]; then
    S5CMD="$S5CMD_PATH"
elif command -v s5cmd &> /dev/null; then
    S5CMD="s5cmd"
else
    echo "Error: s5cmd not found. Install with: go install github.com/peak/s5cmd/v2@latest" >&2
    exit 1
fi

results=()
total_elapsed=0
total_throughput=0
min_elapsed=999999
max_elapsed=0

TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

for i in $(seq 1 $ITERATIONS); do
    # Download to temp file using s5cmd
    # s5cmd uses --concurrency for part parallelism
    rm -f "$TMPFILE"
    start=$(date +%s.%N)
    "$S5CMD" --numworkers 1 cp --concurrency "$CONCURRENCY" --part-size "$PART_SIZE_MB" "s3://${BUCKET}/${KEY}" "$TMPFILE" >/dev/null 2>&1
    end=$(date +%s.%N)

    elapsed=$(echo "$end - $start" | bc)
    throughput=$(echo "scale=1; $FILE_SIZE / 1048576 / $elapsed" | bc)

    echo "  Iteration $i: ${elapsed}s (${throughput} MB/s)" >&2

    total_elapsed=$(echo "$total_elapsed + $elapsed" | bc)
    total_throughput=$(echo "$total_throughput + $throughput" | bc)

    if (( $(echo "$elapsed < $min_elapsed" | bc -l) )); then
        min_elapsed=$elapsed
    fi
    if (( $(echo "$elapsed > $max_elapsed" | bc -l) )); then
        max_elapsed=$elapsed
    fi
done

avg_elapsed=$(echo "scale=2; $total_elapsed / $ITERATIONS" | bc)
avg_throughput=$(echo "scale=1; $total_throughput / $ITERATIONS" | bc)

# Output JSON
cat << EOF
{"tool":"s5cmd","concurrency":$CONCURRENCY,"part_size_mb":$PART_SIZE_MB,"iterations":$ITERATIONS,"avg_elapsed":$avg_elapsed,"avg_throughput_mbps":$avg_throughput,"min_elapsed":$min_elapsed,"max_elapsed":$max_elapsed}
EOF
