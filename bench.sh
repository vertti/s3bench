#!/bin/bash
# Main S3 Download Benchmark Runner
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Load config
if [[ ! -f "$SCRIPT_DIR/config.sh" ]]; then
    echo "Error: config.sh not found. Copy config.sh.example to config.sh and configure it."
    exit 1
fi
source "$SCRIPT_DIR/config.sh"

# Unset AWS_PROFILE if empty to prevent boto3/SDKs from looking for empty profile
if [[ -z "$AWS_PROFILE" ]]; then
    unset AWS_PROFILE
fi

# Default values if not set in config
: "${ITERATIONS:=3}"
: "${CONCURRENCY_LEVELS:=10 20 50}"
: "${PART_SIZES_MB:=16 32 64}"

# Results file
RESULTS_DIR="$SCRIPT_DIR/results"
mkdir -p "$RESULTS_DIR"
RESULTS_FILE="$RESULTS_DIR/benchmark_$(date +%Y%m%d_%H%M%S).json"

echo "S3 Download Benchmark"
echo "===================="
echo "Bucket: $S3_BUCKET"
echo "Key: $S3_KEY"
echo "Region: $S3_REGION"
echo "File size: $(echo "scale=2; $FILE_SIZE_BYTES / 1073741824" | bc) GiB"
echo "Iterations per config: $ITERATIONS"
echo ""

# Build tools first
echo "Building tools..."

# Python setup
echo "  Setting up Python..."
(cd "$SCRIPT_DIR/python" && mise exec -- uv sync --quiet)

# Go build
echo "  Building Go..."
(cd "$SCRIPT_DIR/go" && mise exec -- go mod tidy && mise exec -- go build -o s3bench .)

# Rust build
echo "  Building Rust..."
(cd "$SCRIPT_DIR/rust" && mise exec -- cargo build --release --quiet)

# Check s5cmd - look in mise's go bin directory
S5CMD_PATH="$(mise where go)/bin/s5cmd"
if [[ -f "$S5CMD_PATH" ]]; then
    S5CMD_AVAILABLE=true
    echo "  s5cmd found at $S5CMD_PATH"
else
    S5CMD_AVAILABLE=false
    echo "  s5cmd not found, skipping (install with: mise exec -- go install github.com/peak/s5cmd/v2@latest)"
fi

echo ""
echo "Running benchmarks..."
echo ""

# Collect all results
ALL_RESULTS="["
FIRST=true

# Common args (no --profile when using aws-vault since it exports credentials)
COMMON_ARGS="--bucket $S3_BUCKET --key $S3_KEY --file-size $FILE_SIZE_BYTES --iterations $ITERATIONS --region $S3_REGION"

for CONCURRENCY in $CONCURRENCY_LEVELS; do
    for PART_SIZE in $PART_SIZES_MB; do
        echo "=== Config: concurrency=$CONCURRENCY, part_size=${PART_SIZE}MB ==="
        echo ""

        ARGS="$COMMON_ARGS --concurrency $CONCURRENCY --part-size-mb $PART_SIZE"

        # Python
        echo "Python (boto3):"
        RESULT=$(cd "$SCRIPT_DIR/python" && mise exec -- uv run python download.py $ARGS)
        if [[ "$FIRST" == "true" ]]; then
            ALL_RESULTS="$ALL_RESULTS$RESULT"
            FIRST=false
        else
            ALL_RESULTS="$ALL_RESULTS,$RESULT"
        fi
        echo ""

        # Go
        echo "Go (aws-sdk-go-v2):"
        RESULT=$("$SCRIPT_DIR/go/s3bench" $ARGS)
        ALL_RESULTS="$ALL_RESULTS,$RESULT"
        echo ""

        # Rust
        echo "Rust (transfer-manager):"
        RESULT=$("$SCRIPT_DIR/rust/target/release/s3bench-rust" $ARGS)
        ALL_RESULTS="$ALL_RESULTS,$RESULT"
        echo ""

        # s5cmd
        if [[ "$S5CMD_AVAILABLE" == "true" ]]; then
            echo "s5cmd:"
            RESULT=$(S5CMD_PATH="$S5CMD_PATH" bash "$SCRIPT_DIR/s5cmd/bench.sh" --bucket "$S3_BUCKET" --key "$S3_KEY" \
                --concurrency "$CONCURRENCY" --part-size-mb "$PART_SIZE" \
                --iterations "$ITERATIONS" --file-size "$FILE_SIZE_BYTES")
            ALL_RESULTS="$ALL_RESULTS,$RESULT"
            echo ""
        fi

        echo ""
    done
done

ALL_RESULTS="$ALL_RESULTS]"

# Save results
echo "$ALL_RESULTS" | python3 -m json.tool > "$RESULTS_FILE"
echo "Results saved to: $RESULTS_FILE"
echo ""

# Print summary table
echo "Summary"
echo "======="
echo ""
printf "%-25s %12s %12s %15s\n" "Tool" "Concurrency" "Part Size" "Throughput"
printf "%-25s %12s %12s %15s\n" "----" "-----------" "---------" "----------"

echo "$ALL_RESULTS" | python3 -c "
import json
import sys
data = json.load(sys.stdin)
for r in data:
    print(f\"{r['tool']:<25} {r['concurrency']:>12} {r['part_size_mb']:>10} MB {r['avg_throughput_mbps']:>12.1f} MB/s\")
"
