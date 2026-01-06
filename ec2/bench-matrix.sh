#!/bin/bash
# Run benchmarks across multiple EC2 instance types
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/../results"

# Default instance types: high bandwidth first (faster to complete)
# c5n.9xlarge: 50 Gbps sustained  ($1.94/hr) - high bandwidth
# c5n.xlarge:  5 Gbps baseline    ($0.22/hr) - network optimized
# m5.large:    750 Mbps baseline  ($0.10/hr) - general purpose
# t3.xlarge:   1 Gbps baseline    ($0.17/hr) - small workloads
# t3.medium:   256 Mbps baseline  ($0.04/hr) - common dev/test
# t3.small:    128 Mbps baseline  ($0.02/hr) - minimal test envs
# t3.micro:    32 Mbps baseline   ($0.01/hr) - free tier, CI runners
INSTANCE_TYPES="${INSTANCE_TYPES:-c5n.9xlarge c5n.xlarge m5.large t3.xlarge t3.medium t3.small t3.micro}"

echo "=========================================="
echo "S3 Benchmark Matrix Run"
echo "=========================================="
echo ""
echo "Instance types: $INSTANCE_TYPES"
echo "Results directory: $RESULTS_DIR"
echo ""

RESULT_FILES=""

for INSTANCE_TYPE in $INSTANCE_TYPES; do
    echo ""
    echo "=========================================="
    echo "Starting benchmark for: $INSTANCE_TYPE"
    echo "=========================================="
    echo ""

    RESULT_FILE=$("$SCRIPT_DIR/bench-remote.sh" "$INSTANCE_TYPE") || {
        echo "WARNING: Benchmark for $INSTANCE_TYPE failed, continuing with next..." >&2
        continue
    }

    RESULT_FILES="$RESULT_FILES $RESULT_FILE"

    echo ""
    echo "Completed: $INSTANCE_TYPE → $RESULT_FILE"
    echo ""
done

echo ""
echo "=========================================="
echo "All benchmarks complete!"
echo "=========================================="
echo ""
echo "Result files:"
for F in $RESULT_FILES; do
    echo "  $F"
done
echo ""

# Run aggregation if we have results
if [ -n "$RESULT_FILES" ]; then
    echo "Generating summary..."
    if [ -f "$SCRIPT_DIR/../results/aggregate-results.py" ]; then
        python3 "$SCRIPT_DIR/../results/aggregate-results.py" $RESULT_FILES
    else
        echo "Note: aggregate-results.py not found, skipping summary generation"
    fi
fi
