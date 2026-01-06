#!/usr/bin/env python3
"""S3 download benchmark using boto3 with parallel chunk downloads."""

import argparse
import os
import sys
import tempfile
import time
from pathlib import Path

import boto3
from boto3.s3.transfer import TransferConfig


def create_client(region: str, profile: str | None = None) -> boto3.client:
    """Create S3 client with optional profile."""
    session_kwargs = {}
    # Only set profile if it's a non-empty string
    if profile and profile.strip():
        session_kwargs["profile_name"] = profile

    session = boto3.Session(**session_kwargs)
    return session.client("s3", region_name=region)


def download_file(
    client,
    bucket: str,
    key: str,
    concurrency: int,
    part_size_mb: int,
    output_path: str,
    use_crt: bool = False,
) -> float:
    """Download file and return elapsed time in seconds."""
    config_kwargs = {
        "max_concurrency": concurrency,
        "multipart_chunksize": part_size_mb * 1024 * 1024,
    }
    if use_crt:
        config_kwargs["preferred_transfer_client"] = "crt"
    else:
        config_kwargs["use_threads"] = True

    config = TransferConfig(**config_kwargs)

    start = time.perf_counter()
    client.download_file(bucket, key, output_path, Config=config)
    elapsed = time.perf_counter() - start

    return elapsed


def run_benchmark(
    bucket: str,
    key: str,
    region: str,
    profile: str | None,
    concurrency: int,
    part_size_mb: int,
    iterations: int,
    file_size_bytes: int,
    use_crt: bool = False,
) -> dict:
    """Run benchmark with given parameters."""
    client = create_client(region, profile)

    results = []

    for i in range(iterations):
        # Use temp file, delete after each iteration
        with tempfile.NamedTemporaryFile(delete=True) as tmp:
            elapsed = download_file(
                client, bucket, key, concurrency, part_size_mb, tmp.name, use_crt
            )
            throughput_mbps = (file_size_bytes / (1024 * 1024)) / elapsed
            results.append({"elapsed": elapsed, "throughput_mbps": throughput_mbps})
            print(
                f"  Iteration {i + 1}: {elapsed:.2f}s ({throughput_mbps:.1f} MB/s)",
                file=sys.stderr,
            )

    avg_elapsed = sum(r["elapsed"] for r in results) / len(results)
    avg_throughput = sum(r["throughput_mbps"] for r in results) / len(results)
    min_elapsed = min(r["elapsed"] for r in results)
    max_elapsed = max(r["elapsed"] for r in results)

    return {
        "concurrency": concurrency,
        "part_size_mb": part_size_mb,
        "iterations": iterations,
        "avg_elapsed": avg_elapsed,
        "avg_throughput_mbps": avg_throughput,
        "min_elapsed": min_elapsed,
        "max_elapsed": max_elapsed,
    }


def main():
    parser = argparse.ArgumentParser(description="S3 download benchmark")
    parser.add_argument("--bucket", required=True, help="S3 bucket name")
    parser.add_argument("--key", required=True, help="S3 object key")
    parser.add_argument("--region", default="us-east-1", help="AWS region")
    parser.add_argument("--profile", default=None, help="AWS profile name")
    parser.add_argument("--concurrency", type=int, default=10, help="Max concurrent downloads")
    parser.add_argument("--part-size-mb", type=int, default=16, help="Part size in MB")
    parser.add_argument("--iterations", type=int, default=3, help="Number of iterations")
    parser.add_argument("--file-size", type=int, required=True, help="File size in bytes")
    parser.add_argument("--crt", action="store_true", help="Use AWS CRT transfer client")

    args = parser.parse_args()

    tool_name = "python-boto3-crt" if args.crt else "python-boto3"
    print(f"{tool_name} benchmark: concurrency={args.concurrency}, part_size={args.part_size_mb}MB", file=sys.stderr)

    result = run_benchmark(
        bucket=args.bucket,
        key=args.key,
        region=args.region,
        profile=args.profile,
        concurrency=args.concurrency,
        part_size_mb=args.part_size_mb,
        iterations=args.iterations,
        file_size_bytes=args.file_size,
        use_crt=args.crt,
    )

    # Output JSON for easy parsing
    import json
    print(json.dumps({"tool": tool_name, **result}))


if __name__ == "__main__":
    main()
