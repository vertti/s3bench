# s3bench

Benchmark S3 download performance across Python, Go, and Rust with parallel chunk downloads.

## Results

Benchmarks run on various EC2 instance types in eu-central-1, downloading a 3 GB file from S3 in the same region. Each configuration runs 3 iterations.

### Tools Tested

| Tool | Language | Library |
|------|----------|---------|
| go-sdk | Go 1.24 | aws-sdk-go-v2 s3manager |
| rust-transfer-manager | Rust 1.92 | aws-s3-transfer-manager (preview) |
| python-boto3-crt | Python 3.13 | boto3 + AWS CRT |
| python-boto3 | Python 3.13 | boto3 |
| s5cmd | Go | s5cmd v2.3 |

### Results by Instance Type

#### c5n.9xlarge (50 Gbps sustained)

| Tool | Throughput | Concurrency | Part Size |
|------|------------|-------------|-----------|
| go-sdk | 4,023 MB/s | 128 | 16 MB |
| rust-transfer-manager | 2,852 MB/s | 64 | 32 MB |
| python-boto3-crt | 1,810 MB/s | 32 | 16 MB |
| s5cmd | 1,628 MB/s | 64 | 16 MB |
| python-boto3 | 746 MB/s | 16 | 32 MB |

[Full results →](results/c5n.9xlarge_20260106_201850.json)

#### c5n.xlarge (5 Gbps baseline, 25 Gbps burst)

| Tool | Throughput | Concurrency | Part Size |
|------|------------|-------------|-----------|
| go-sdk | 2,419 MB/s | 64 | 16 MB |
| rust-transfer-manager | 1,403 MB/s | 32 | 16 MB |
| python-boto3-crt | 1,168 MB/s | 32 | 16 MB |
| s5cmd | 1,138 MB/s | 128 | 16 MB |
| python-boto3 | 465 MB/s | 8 | 128 MB |

[Full results →](results/c5n.xlarge_20260106_204712.json)

#### m5.large (750 Mbps baseline, 10 Gbps burst)

| Tool | Throughput | Concurrency | Part Size |
|------|------------|-------------|-----------|
| go-sdk | 900 MB/s | 16 | 16 MB |
| rust-transfer-manager | 707 MB/s | 16 | 16 MB |
| s5cmd | 651 MB/s | 16 | 32 MB |
| python-boto3-crt | 639 MB/s | 8 | 32 MB |
| python-boto3 | 401 MB/s | 16 | 64 MB |

[Full results →](results/m5.large_20260107_105637.json)

#### t3.xlarge (1 Gbps baseline, 5 Gbps burst)

| Tool | Throughput | Concurrency | Part Size |
|------|------------|-------------|-----------|
| rust-transfer-manager | 530 MB/s | 8 | 16 MB |
| go-sdk | 529 MB/s | 32 | 16 MB |
| s5cmd | 506 MB/s | 16 | 16 MB |
| python-boto3-crt | 505 MB/s | 8 | 16 MB |
| python-boto3 | 272 MB/s | 16 | 32 MB |

[Full results →](results/t3.xlarge_20260107_112321.json)

#### t3.medium (256 Mbps baseline, 5 Gbps burst)

| Tool | Throughput | Concurrency | Part Size |
|------|------------|-------------|-----------|
| rust-transfer-manager | 523 MB/s | 8 | 16 MB |
| go-sdk | 516 MB/s | 8 | 16 MB |
| python-boto3-crt | 493 MB/s | 8 | 16 MB |
| s5cmd | 489 MB/s | 8 | 16 MB |
| python-boto3 | 331 MB/s | 4 | 64 MB |

[Full results →](results/t3.medium_20260107_114832.json)


### About EC2 Network Bandwidth

EC2 instances have two bandwidth limits:
- **Baseline**: Guaranteed sustained bandwidth
- **Burst**: Higher bandwidth available temporarily using network credits

For example, m5.large has 750 Mbps (~94 MB/s) baseline but can burst to 10 Gbps. Once burst credits are exhausted, throughput drops to baseline. This is why we test fewer concurrency levels on smaller instances - high concurrency quickly exhausts burst credits, making benchmarks take hours at throttled speeds.

High-bandwidth instances like c5n.9xlarge have 50 Gbps *sustained* (no burst limit), so we can test the full concurrency range.

### Known Issues

**Rust has a first-download penalty** - the first download in a process is 2-3x slower than subsequent ones due to lazy connection initialization:

```
Rust (c=32, p=128MB):
  Iteration 1: 4.08s (753 MB/s)   <- connection setup overhead
  Iteration 2: 1.76s (1743 MB/s)
  Iteration 3: 1.78s (1728 MB/s)

Go (c=32, p=128MB):
  Iteration 1: 2.73s (1126 MB/s)  <- no warmup penalty
  Iteration 2: 2.72s (1128 MB/s)
  Iteration 3: 2.70s (1138 MB/s)
```

This is specific to the Rust transfer-manager. We've [reported this issue](https://github.com/awslabs/aws-s3-transfer-manager-rs/issues/128) upstream.

**Note:** The Rust transfer-manager is in [developer preview](https://github.com/awslabs/aws-s3-transfer-manager-rs) - this may be addressed before stable release.

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

This installs Python 3.13, Go 1.24, Rust 1.92, and uv.

Install s5cmd for baseline comparison:
```bash
mise exec -- go install github.com/peak/s5cmd/v2@v2.3.0
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

## License

MIT
