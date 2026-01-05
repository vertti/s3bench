# s3bench

Benchmark S3 download performance across Python, Go, and Rust with parallel chunk downloads.

## Goal

Compare S3 download speeds using:
- **Python** - boto3 with TransferConfig
- **Go** - aws-sdk-go-v2 s3manager
- **Rust** - aws-sdk-s3-transfer-manager
- **s5cmd** - High-performance S3 CLI (baseline)

## Setup

### Prerequisites

Install [mise](https://mise.jdx.dev/) for tool management:

```bash
curl https://mise.run | sh
```

### Install tools

```bash
cd s3bench
mise trust
mise install
```

This installs Python 3.12, Go 1.23, Rust (stable), and uv.

Optionally install s5cmd for baseline comparison:
```bash
mise exec -- go install github.com/peak/s5cmd/v2@latest
```

### Configure

```bash
cp config.sh.example config.sh
# Edit config.sh with your S3 bucket/key/region
```

## Run Benchmarks

### With aws-vault (SSO profiles)

```bash
aws-vault exec <your-profile> -- ./bench.sh
```

### With standard AWS credentials

```bash
./bench.sh
```

## Project Structure

```
s3bench/
├── .mise.toml           # Tool versions
├── config.sh.example    # Config template
├── bench.sh             # Main benchmark runner
├── python/
│   ├── pyproject.toml
│   └── download.py
├── go/
│   ├── go.mod
│   └── main.go
├── rust/
│   ├── Cargo.toml
│   └── src/main.rs
└── s5cmd/
    └── bench.sh
```

## Results

Benchmarks run on EC2 c5n.2xlarge in eu-central-1, downloading a 3 GB file from S3 in the same region.

### Peak Throughput (concurrency=32, part_size=32MB)

| Implementation | Throughput | Notes |
|----------------|------------|-------|
| **Rust** (transfer-manager) | ~2.3 GB/s | Fastest at steady-state |
| **Go** (aws-sdk-go-v2) | ~1.8 GB/s | Consistent across iterations |
| **s5cmd** | ~1.1 GB/s | Stable baseline |
| **Python** (boto3) | ~450 MB/s | Limited by GIL |

### Key Findings

1. **Rust is fastest at steady-state** - achieves ~2.3 GB/s with optimal settings (concurrency=32-64, part_size=32MB)

2. **Go is most consistent** - no warmup penalty, performs the same on every download

3. **Python is bottlenecked** - likely by GIL, tops out around 450-500 MB/s regardless of concurrency

4. **Rust has a first-download penalty** - the first download in a process is 3-4x slower than subsequent ones:

   ```
   Rust (c=32, p=128MB):
     Iteration 1: 4.08s (753 MB/s)   <- 3-4 seconds of warmup overhead
     Iteration 2: 1.76s (1743 MB/s)
     Iteration 3: 1.78s (1728 MB/s)

   Go (c=32, p=128MB):
     Iteration 1: 2.73s (1126 MB/s)  <- No warmup penalty
     Iteration 2: 2.72s (1128 MB/s)
     Iteration 3: 2.70s (1138 MB/s)
   ```

   This appears to be specific to the Rust transfer-manager - Go, Python, and s5cmd don't exhibit this behavior. We've [reported this issue](https://github.com/awslabs/aws-s3-transfer-manager-rs/issues/128) upstream.

   **Note:** The Rust transfer-manager is currently in [developer preview](https://github.com/awslabs/aws-s3-transfer-manager-rs) - it shows great promise at steady-state and this issue may well be addressed before stable release.

### Recommendation

- For **single file downloads**: Go is currently the best choice (no warmup penalty)
- For **multiple sequential downloads**: Rust after the first download
- For **simplicity**: s5cmd is a solid CLI option

## Running on EC2

Scripts are provided to run benchmarks on EC2 for higher bandwidth:

```bash
# One-time setup (creates IAM role)
aws-vault exec <admin-profile> -- ./ec2/setup-role.sh

# Launch instance
aws-vault exec <admin-profile> -- ./ec2/launch.sh

# Connect via SSM
aws-vault exec <admin-profile> -- ./ec2/connect.sh

# Cleanup when done
aws-vault exec <admin-profile> -- ./ec2/cleanup.sh
```

## License

MIT
