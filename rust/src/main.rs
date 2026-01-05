use aws_config::BehaviorVersion;
use aws_sdk_s3_transfer_manager::{
    types::{ConcurrencyMode, PartSize},
    Client,
};
use clap::Parser;
use serde::Serialize;
use std::time::Instant;

#[derive(Parser, Debug)]
#[command(name = "s3bench-rust")]
#[command(about = "S3 download benchmark using Rust Transfer Manager")]
struct Args {
    #[arg(long)]
    bucket: String,

    #[arg(long)]
    key: String,

    #[arg(long, default_value = "us-east-1")]
    region: String,

    #[arg(long)]
    profile: Option<String>,

    #[arg(long, default_value = "10")]
    concurrency: usize,

    #[arg(long, default_value = "16")]
    part_size_mb: u64,

    #[arg(long, default_value = "3")]
    iterations: u32,

    #[arg(long)]
    file_size: u64,
}

#[derive(Serialize)]
struct Result {
    tool: String,
    concurrency: usize,
    part_size_mb: u64,
    iterations: u32,
    avg_elapsed: f64,
    avg_throughput_mbps: f64,
    min_elapsed: f64,
    max_elapsed: f64,
}

async fn download_file(
    client: &Client,
    bucket: &str,
    key: &str,
) -> std::result::Result<std::time::Duration, Box<dyn std::error::Error + Send + Sync>> {
    let start = Instant::now();

    let mut handle = client
        .download()
        .bucket(bucket)
        .key(key)
        .initiate()?;

    // Consume the body by reading all bytes (discarding them)
    let body = handle.body_mut();
    while let Some(chunk) = body.next().await {
        let _ = chunk?;
    }

    Ok(start.elapsed())
}

#[tokio::main]
async fn main() -> std::result::Result<(), Box<dyn std::error::Error + Send + Sync>> {
    let args = Args::parse();

    eprintln!(
        "Rust Transfer Manager benchmark: concurrency={}, part_size={}MB",
        args.concurrency, args.part_size_mb
    );

    // Build AWS config
    let mut config_loader = aws_config::defaults(BehaviorVersion::latest())
        .region(aws_config::Region::new(args.region.clone()));

    if let Some(profile) = &args.profile {
        config_loader = config_loader.profile_name(profile);
    }

    let sdk_config = config_loader.load().await;
    let s3_client = aws_sdk_s3::Client::new(&sdk_config);

    // Create transfer manager with configured concurrency and part size
    let tm_config = aws_sdk_s3_transfer_manager::Config::builder()
        .client(s3_client)
        .concurrency(ConcurrencyMode::Explicit(args.concurrency))
        .part_size(PartSize::Target(args.part_size_mb * 1024 * 1024))
        .build();

    let client = Client::new(tm_config);

    let mut results: Vec<(f64, f64)> = Vec::new();

    for i in 0..args.iterations {
        let elapsed = download_file(&client, &args.bucket, &args.key).await?;
        let elapsed_secs = elapsed.as_secs_f64();
        let throughput = (args.file_size as f64 / (1024.0 * 1024.0)) / elapsed_secs;

        results.push((elapsed_secs, throughput));
        eprintln!("  Iteration {}: {:.2}s ({:.1} MB/s)", i + 1, elapsed_secs, throughput);
    }

    // Calculate stats
    let avg_elapsed: f64 = results.iter().map(|(e, _)| e).sum::<f64>() / results.len() as f64;
    let avg_throughput: f64 = results.iter().map(|(_, t)| t).sum::<f64>() / results.len() as f64;
    let min_elapsed = results.iter().map(|(e, _)| *e).fold(f64::INFINITY, f64::min);
    let max_elapsed = results.iter().map(|(e, _)| *e).fold(f64::NEG_INFINITY, f64::max);

    let result = Result {
        tool: "rust-transfer-manager".to_string(),
        concurrency: args.concurrency,
        part_size_mb: args.part_size_mb,
        iterations: args.iterations,
        avg_elapsed,
        avg_throughput_mbps: avg_throughput,
        min_elapsed,
        max_elapsed,
    };

    println!("{}", serde_json::to_string(&result)?);

    Ok(())
}
