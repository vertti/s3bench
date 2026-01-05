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

## Benchmark Parameters

| Concurrency | Part Size |
|-------------|-----------|
| 10          | 16 MB     |
| 20          | 32 MB     |
| 50          | 64 MB     |

Each configuration runs 3 iterations.

## License

MIT
