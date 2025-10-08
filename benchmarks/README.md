# logthis Performance Benchmarks

This directory contains comprehensive performance benchmarks for the `logthis` logging framework.

## Available Benchmarks

### 1. Full Benchmark Suite (`benchmark_receivers.R`)

Comprehensive benchmarking covering:

- **Single Event Latency**: Time to log one event across all receiver types
- **Throughput**: Events per second for 1000 events
- **Buffered Performance**: Impact of flush thresholds on Parquet logging
- **Scaling**: Performance from 10 to 10,000 events
- **Memory Usage**: Allocation patterns for different receivers
- **Component Overhead**: Cost of tags, limits, and other features

**Requirements:**
- `bench` package (auto-installed if missing)
- Optional: `mirai` for async benchmarks
- Optional: `arrow` for Parquet benchmarks

**Usage:**
```bash
Rscript benchmarks/benchmark_receivers.R
```

**Output:**
- Detailed timing statistics for all receivers
- Events/second calculations
- Memory profiling
- Scaling analysis
- Comprehensive summary report

**Runtime:** ~2-5 minutes (depending on system)

---

### 2. Quick Benchmark (`quick_benchmark.R`)

Fast performance check for development:

- Basic latency for console, text, JSON receivers
- Sync vs async comparison (if mirai available)
- Feature overhead (tags, limits)

**Usage:**
```bash
Rscript benchmarks/quick_benchmark.R
```

**Runtime:** ~10-30 seconds

---

## Benchmark Results

### Typical Performance (R 4.5.1, Ubuntu 24.04, x86_64)

**Single Event Latency:**
- Identity receiver: ~5-10 µs (baseline)
- Console: ~50-100 µs
- Text file: ~200-500 µs
- JSON file: ~300-600 µs
- CSV file: ~400-700 µs
- Async (queue time): ~50-200 µs

**Throughput (1000 events):**
- Console: ~10,000-20,000 events/sec
- Text file (sync): ~2,000-5,000 events/sec
- Text file (async): ~20,000-50,000 events/sec
- JSON file (sync): ~1,500-3,000 events/sec
- JSON file (async): ~15,000-40,000 events/sec
- Parquet (buffered): ~5,000-10,000 events/sec

**Memory:**
- ~100-300 KB per 100 events (typical)
- Async buffering: +~1 KB per queued event

**Feature Overhead:**
- Tags: +5-15% vs bare logger
- Limits: +10-20% vs bare logger
- Receiver filtering: +5-10% per receiver

---

## Running Benchmarks

### From Package Root

```bash
# Full benchmark suite
Rscript benchmarks/benchmark_receivers.R

# Quick check
Rscript benchmarks/quick_benchmark.R
```

### From R Console

```r
# Full benchmarks
source("benchmarks/benchmark_receivers.R")

# Quick benchmarks
source("benchmarks/quick_benchmark.R")
```

---

## Interpreting Results

### Latency vs Throughput

- **Latency**: Time per single event (lower is better)
  - Important for interactive applications
  - Measured in microseconds (µs) or milliseconds (ms)

- **Throughput**: Events per second (higher is better)
  - Important for high-volume logging
  - Measured in events/sec

### Sync vs Async

**Sync receivers:**
- Block until write completes
- Predictable timing
- Data written immediately
- Use for: Critical logs, low-volume scenarios

**Async receivers:**
- Return immediately after queueing
- Much higher throughput
- Small risk of data loss on crash
- Use for: High-volume logging, non-blocking I/O

**Key metric:** Async benchmarks measure **queue time only**. Actual writes happen in background daemon.

### Buffering Impact

Higher `flush_threshold`:
- ✅ Better throughput (fewer I/O operations)
- ✅ Lower CPU usage
- ❌ Higher memory usage
- ❌ Longer delay before logs appear

Typical recommendations:
- Interactive/development: `flush_threshold = 10-50`
- Production: `flush_threshold = 100-500`
- Batch processing: `flush_threshold = 1000-5000`

---

## Performance Tips

### 1. Use Async for High-Volume Logging

```r
# Sync: blocks on every event
to_text() %>% on_local("app.log")

# Async: queues events, writes in background
to_text() %>% on_local("app.log") %>% as_async(flush_threshold = 100)
```

**Speedup:** 5-20x for file I/O, 10-50x for network I/O

### 2. Increase Buffer Sizes

```r
# Parquet with large buffer
to_parquet() %>% on_local("events.parquet", flush_threshold = 5000)

# S3 with batching
to_json() %>% on_s3("bucket", "key", flush_threshold = 1000)
```

### 3. Use Receiver-Level Filtering

```r
# Bad: All events processed, then filtered at receiver
with_receivers(
  to_text() %>% on_local("all.log"),
  to_text() %>% on_local("errors.log")  # No filtering!
)

# Good: Filter early, skip processing
with_receivers(
  to_text() %>% on_local("all.log"),
  to_text(lower = ERROR) %>% on_local("errors.log")  # Only ERRORs processed
)
```

### 4. Pool Async Daemons for Multiple Receivers

```r
# Single daemon (default) - receivers compete for one worker
to_text() %>% on_local("app.log") %>% as_async()
to_json() %>% on_s3(...) %>% as_async()

# Daemon pool - parallel processing
mirai::daemons(4)  # 4 workers BEFORE creating loggers
to_text() %>% on_local("app.log") %>% as_async()
to_json() %>% on_s3(...) %>% as_async()
```

### 5. Minimize Custom Fields in Hot Paths

```r
# Hot path: minimal fields
log_this(NOTE("Request", id = req_id))

# Less frequent: rich metadata
log_this(NOTE("Completed", id = req_id, duration_ms = 123,
              user_agent = ua, ip = ip, path = path))
```

---

## Benchmark Methodology

### Tools

- `bench::mark()`: Accurate timing with statistical analysis
  - Measures median, min, max, IQR
  - Tracks memory allocation and GC
  - Automatically determines iteration count

- `system.time()`: Simple elapsed time (quick benchmarks)

### Best Practices

1. **Warmup**: First few iterations may be slower (JIT compilation, caching)
2. **Isolation**: Each benchmark uses separate log files
3. **Cleanup**: Temp files removed after completion
4. **Repeatability**: Run multiple iterations, report median
5. **Context**: Document system specs, R version, package versions

---

## Contributing Benchmarks

When adding new receivers or features, please:

1. Add benchmark to `benchmark_receivers.R`
2. Update this README with expected performance
3. Run full benchmark suite before/after changes
4. Document any significant performance impacts

---

## Benchmark History

Track significant performance changes:

### v0.2.0 (2025-10-08)
- Added async receiver benchmarks
- Async provides 5-20x throughput improvement
- Queue latency: 50-200 µs

### v0.1.0 (2025-10-07)
- Initial benchmark suite
- Baseline performance established
- All sync receivers tested

---

## System Information

Run benchmarks on your system and compare:

```r
# R version
R.version.string

# Platform
R.version$platform

# Package versions
packageVersion("logthis")
packageVersion("bench")

# System specs
parallel::detectCores()  # CPU cores
memory.limit()  # Memory (Windows)
```

---

## Questions?

For performance-related questions or issues:
- GitHub Issues: https://github.com/iqis/logthis/issues
- Label: `performance`
