# First download is 3-4x slower than subsequent downloads

## Summary

When running repeated downloads of the same file, the first iteration is consistently 3-4x slower than subsequent iterations. This behavior is not observed with other S3 SDKs (Go, Python boto3, s5cmd).

## Environment

- Instance: EC2 c5n.2xlarge (eu-central-1)
- File size: 3 GB
- Rust version: 1.83
- Dependencies:
```toml
aws-config = { version = "1.5", features = ["behavior-version-latest"] }
aws-sdk-s3 = "1.65"
aws-sdk-s3-transfer-manager = "0.1"
tokio = { version = "1", features = ["full"] }
```

## Code

Minimal reproduction:

```rust
use aws_config::BehaviorVersion;
use aws_sdk_s3_transfer_manager::{
    types::{ConcurrencyMode, PartSize},
    Client,
};
use std::time::Instant;

async fn download_file(
    client: &Client,
    bucket: &str,
    key: &str,
) -> Result<std::time::Duration, Box<dyn std::error::Error + Send + Sync>> {
    let start = Instant::now();

    let mut handle = client
        .download()
        .bucket(bucket)
        .key(key)
        .initiate()?;

    let body = handle.body_mut();
    while let Some(chunk) = body.next().await {
        let _ = chunk?;
    }

    Ok(start.elapsed())
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let sdk_config = aws_config::defaults(BehaviorVersion::latest())
        .region(aws_config::Region::new("eu-central-1"))
        .load()
        .await;

    let s3_client = aws_sdk_s3::Client::new(&sdk_config);

    let tm_config = aws_sdk_s3_transfer_manager::Config::builder()
        .client(s3_client)
        .concurrency(ConcurrencyMode::Explicit(32))
        .part_size(PartSize::Target(128 * 1024 * 1024))
        .build();

    let client = Client::new(tm_config);

    // Run 3 iterations
    for i in 1..=3 {
        let elapsed = download_file(&client, "my-bucket", "3gb-file.bin").await?;
        eprintln!("Iteration {}: {:.2}s", i, elapsed.as_secs_f64());
    }

    Ok(())
}
```

## Results

**Rust transfer-manager** (concurrency=32, part_size=128MB):
```
Iteration 1: 4.08s (752.9 MB/s)
Iteration 2: 1.76s (1742.7 MB/s)
Iteration 3: 1.78s (1728.4 MB/s)
```

The pattern is consistent across different concurrency/part-size configurations:

| Config | Iter 1 | Iter 2 | Iter 3 | Slowdown |
|--------|--------|--------|--------|----------|
| c=32, p=128MB | 4.08s | 1.76s | 1.78s | 2.3x |
| c=64, p=32MB | 4.75s | 1.34s | 1.29s | 3.5x |
| c=128, p=64MB | 5.18s | 1.30s | 1.36s | 4.0x |

## Comparison with other SDKs

Running the same benchmark with other implementations shows **no first-iteration penalty**:

**Go aws-sdk-go-v2** (concurrency=32, part_size=128MB):
```
Iteration 1: 2.73s (1126.0 MB/s)
Iteration 2: 2.72s (1127.7 MB/s)
Iteration 3: 2.70s (1137.9 MB/s)
```

**Python boto3** (concurrency=32, part_size=128MB):
```
Iteration 1: 6.70s (458.5 MB/s)
Iteration 2: 6.41s (479.1 MB/s)
Iteration 3: 6.25s (491.5 MB/s)
```

**s5cmd** (concurrency=32, part_size=128MB):
```
Iteration 1: 3.49s (880.7 MB/s)
Iteration 2: 3.51s (874.8 MB/s)
Iteration 3: 3.57s (860.1 MB/s)
```

## Impact

This means that for single-file downloads (a common use case), the transfer-manager performs significantly worse than expected. The steady-state throughput of ~2 GB/s is excellent, but the ~3-4 second warmup cost makes single downloads slower than Go despite Rust being faster at steady-state.

## Questions

1. Are we using the API incorrectly?
2. Is there a way to "warm up" the client before timing-sensitive operations?
3. Is this a known issue or expected behavior?

Full benchmark code: https://github.com/vertti/s3bench
