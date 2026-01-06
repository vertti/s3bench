#!/bin/bash
# Run benchmarks across multiple EC2 instance types
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/../results"

# Default instance types: distinct sustained bandwidth tiers
# c5n.xlarge:  ~10 Gbps  ($0.22/hr)
# c5n.4xlarge: 25 Gbps   ($0.86/hr)
# c5n.9xlarge: 50 Gbps   ($1.94/hr)
INSTANCE_TYPES="${INSTANCE_TYPES:-c5n.xlarge c5n.4xlarge c5n.9xlarge}"

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
