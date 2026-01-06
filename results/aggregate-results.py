#!/usr/bin/env python3
"""
Aggregate benchmark results from multiple EC2 instance types.
Finds optimal settings (concurrency, part_size) per tool per instance type.
"""
import json
import sys
import re
from pathlib import Path
from collections import defaultdict


def extract_instance_type(filename: str) -> str:
    """Extract instance type from filename like 'c5n.xlarge_20240105_123456.json'"""
    name = Path(filename).stem
    # Match patterns like t3.micro, m5.large, c5n.xlarge, c5n.4xlarge, etc.
    match = re.match(r'([a-z0-9]+\.[a-z0-9]+)', name)
    if match:
        return match.group(1)
    return name.split('_')[0]


def load_results(files: list[str]) -> dict:
    """Load results from JSON files, grouped by instance type."""
    by_instance = defaultdict(list)

    for filepath in files:
        instance_type = extract_instance_type(filepath)
        with open(filepath) as f:
            data = json.load(f)
            for entry in data:
                entry['instance_type'] = instance_type
            by_instance[instance_type].extend(data)

    return dict(by_instance)


def find_best_settings(results: list[dict]) -> dict:
    """Find best settings per tool based on throughput."""
    by_tool = defaultdict(list)
    for r in results:
        by_tool[r['tool']].append(r)

    best = {}
    for tool, entries in by_tool.items():
        best_entry = max(entries, key=lambda x: x['avg_throughput_mbps'])
        best[tool] = {
            'concurrency': best_entry['concurrency'],
            'part_size_mb': best_entry['part_size_mb'],
            'throughput_mbps': best_entry['avg_throughput_mbps'],
        }

    return best


def main():
    if len(sys.argv) < 2:
        print("Usage: aggregate-results.py <result1.json> [result2.json ...]", file=sys.stderr)
        sys.exit(1)

    files = sys.argv[1:]
    results_by_instance = load_results(files)

    # Instance bandwidth estimates (baseline / burst)
    bandwidth_map = {
        't3.micro': '32 Mbps',
        't3.small': '128 Mbps',
        't3.medium': '256 Mbps',
        't3.large': '512 Mbps',
        't3.xlarge': '1 Gbps',
        'm5.large': '750 Mbps',
        'm5.xlarge': '1.25 Gbps',
        'c5n.xlarge': '5 Gbps',
        'c5n.2xlarge': '10 Gbps',
        'c5n.4xlarge': '15 Gbps',
        'c5n.9xlarge': '50 Gbps',
        'c5n.18xlarge': '100 Gbps',
    }

    print("=" * 80)
    print("S3 Download Benchmark - Optimal Settings by Instance Type")
    print("=" * 80)
    print()

    summary = {}

    for instance_type in sorted(results_by_instance.keys()):
        results = results_by_instance[instance_type]
        best = find_best_settings(results)
        bandwidth = bandwidth_map.get(instance_type, 'unknown')

        summary[instance_type] = {
            'bandwidth': bandwidth,
            'best_settings': best,
        }

        print(f"Instance: {instance_type} ({bandwidth})")
        print("-" * 60)
        print(f"{'Tool':<25} {'Concurrency':>12} {'Part Size':>12} {'Throughput':>15}")
        print(f"{'-'*25} {'-'*12} {'-'*12} {'-'*15}")

        for tool in sorted(best.keys()):
            settings = best[tool]
            print(f"{tool:<25} {settings['concurrency']:>12} {settings['part_size_mb']:>10} MB {settings['throughput_mbps']:>12.1f} MB/s")

        print()

    # Output JSON summary
    summary_file = Path(files[0]).parent / 'summary.json'
    with open(summary_file, 'w') as f:
        json.dump(summary, f, indent=2)
    print(f"Summary saved to: {summary_file}")


if __name__ == '__main__':
    main()
