package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/s3/manager"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

type Result struct {
	Tool             string  `json:"tool"`
	Concurrency      int     `json:"concurrency"`
	PartSizeMB       int     `json:"part_size_mb"`
	Iterations       int     `json:"iterations"`
	AvgElapsed       float64 `json:"avg_elapsed"`
	AvgThroughputMBPS float64 `json:"avg_throughput_mbps"`
	MinElapsed       float64 `json:"min_elapsed"`
	MaxElapsed       float64 `json:"max_elapsed"`
}

type discardWriterAt struct{}

func (d discardWriterAt) WriteAt(p []byte, off int64) (n int, err error) {
	return len(p), nil
}

func downloadFile(ctx context.Context, downloader *manager.Downloader, bucket, key string) (time.Duration, error) {
	start := time.Now()

	_, err := downloader.Download(ctx, discardWriterAt{}, &s3.GetObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(key),
	})

	return time.Since(start), err
}

func runBenchmark(ctx context.Context, bucket, key, region, profile string, concurrency, partSizeMB, iterations int, fileSizeBytes int64) (*Result, error) {
	// Load AWS config
	var cfg aws.Config
	var err error

	opts := []func(*config.LoadOptions) error{
		config.WithRegion(region),
	}

	if profile != "" {
		opts = append(opts, config.WithSharedConfigProfile(profile))
	}

	cfg, err = config.LoadDefaultConfig(ctx, opts...)
	if err != nil {
		return nil, fmt.Errorf("failed to load config: %w", err)
	}

	// Create S3 client and downloader
	client := s3.NewFromConfig(cfg)
	downloader := manager.NewDownloader(client, func(d *manager.Downloader) {
		d.Concurrency = concurrency
		d.PartSize = int64(partSizeMB) * 1024 * 1024
	})

	var results []struct {
		elapsed       time.Duration
		throughputMBPS float64
	}

	for i := 0; i < iterations; i++ {
		elapsed, err := downloadFile(ctx, downloader, bucket, key)
		if err != nil {
			return nil, fmt.Errorf("download failed: %w", err)
		}

		throughput := float64(fileSizeBytes) / (1024 * 1024) / elapsed.Seconds()
		results = append(results, struct {
			elapsed       time.Duration
			throughputMBPS float64
		}{elapsed, throughput})

		fmt.Fprintf(os.Stderr, "  Iteration %d: %.2fs (%.1f MB/s)\n", i+1, elapsed.Seconds(), throughput)
	}

	// Calculate stats
	var totalElapsed time.Duration
	var totalThroughput float64
	minElapsed := results[0].elapsed
	maxElapsed := results[0].elapsed

	for _, r := range results {
		totalElapsed += r.elapsed
		totalThroughput += r.throughputMBPS
		if r.elapsed < minElapsed {
			minElapsed = r.elapsed
		}
		if r.elapsed > maxElapsed {
			maxElapsed = r.elapsed
		}
	}

	avgElapsed := totalElapsed.Seconds() / float64(len(results))
	avgThroughput := totalThroughput / float64(len(results))

	return &Result{
		Tool:             "go-sdk",
		Concurrency:      concurrency,
		PartSizeMB:       partSizeMB,
		Iterations:       iterations,
		AvgElapsed:       avgElapsed,
		AvgThroughputMBPS: avgThroughput,
		MinElapsed:       minElapsed.Seconds(),
		MaxElapsed:       maxElapsed.Seconds(),
	}, nil
}

func main() {
	bucket := flag.String("bucket", "", "S3 bucket name")
	key := flag.String("key", "", "S3 object key")
	region := flag.String("region", "us-east-1", "AWS region")
	profile := flag.String("profile", "", "AWS profile name")
	concurrency := flag.Int("concurrency", 10, "Max concurrent downloads")
	partSizeMB := flag.Int("part-size-mb", 16, "Part size in MB")
	iterations := flag.Int("iterations", 3, "Number of iterations")
	fileSize := flag.Int64("file-size", 0, "File size in bytes")

	flag.Parse()

	if *bucket == "" || *key == "" || *fileSize == 0 {
		fmt.Fprintln(os.Stderr, "Error: --bucket, --key, and --file-size are required")
		os.Exit(1)
	}

	fmt.Fprintf(os.Stderr, "Go SDK benchmark: concurrency=%d, part_size=%dMB\n", *concurrency, *partSizeMB)

	ctx := context.Background()
	result, err := runBenchmark(ctx, *bucket, *key, *region, *profile, *concurrency, *partSizeMB, *iterations, *fileSize)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}

	// Output JSON
	enc := json.NewEncoder(io.Discard)
	enc = json.NewEncoder(os.Stdout)
	enc.Encode(result)
}
