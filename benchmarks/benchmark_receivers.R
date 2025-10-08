# ==============================================================================
# logthis Performance Benchmarks
# ==============================================================================
# Comprehensive benchmarking of all receiver types, sync vs async performance,
# throughput, latency, and memory usage.
#
# Requirements: bench, ggplot2 (optional for plots)
# Run from package root: Rscript benchmarks/benchmark_receivers.R

library(logthis)
library(magrittr)

# Install bench if needed
if (!requireNamespace("bench", quietly = TRUE)) {
  message("Installing bench package for accurate benchmarking...")
  install.packages("bench", repos = "https://cloud.r-project.org")
}

library(bench)

# Setup
message("\n", strrep("=", 80))
message("logthis Performance Benchmarks")
message(strrep("=", 80), "\n")

message("R version: ", R.version.string)
message("logthis version: ", packageVersion("logthis"))
message("Platform: ", R.version$platform)
message("Date: ", Sys.time(), "\n")

# Create temp directory for benchmark outputs
bench_dir <- tempfile("logthis_bench_")
dir.create(bench_dir)
message("Benchmark output directory: ", bench_dir, "\n")

# ==============================================================================
# Benchmark 1: Receiver Latency (Single Event)
# ==============================================================================

message("\n", strrep("-", 80))
message("Benchmark 1: Single Event Latency")
message(strrep("-", 80), "\n")

message("Measuring time to log a single event across different receivers...\n")

# Create test event
test_event <- NOTE("Benchmark event", id = 1, value = 42.5, status = "test")

# Define receivers to benchmark
receivers_latency <- list(
  console = logger() %>% with_receivers(to_console()),

  text_file = logger() %>% with_receivers(
    to_text() %>% on_local(file.path(bench_dir, "bench_text.log"))
  ),

  json_file = logger() %>% with_receivers(
    to_json() %>% on_local(file.path(bench_dir, "bench_json.jsonl"))
  ),

  csv_file = logger() %>% with_receivers(
    to_csv() %>% on_local(file.path(bench_dir, "bench_csv.csv"))
  ),

  identity = logger() %>% with_receivers(to_identity())
)

# Add async receivers if mirai available
if (requireNamespace("mirai", quietly = TRUE)) {
  mirai::daemons(2)

  receivers_latency$text_async <- logger() %>% with_receivers(
    to_text() %>% on_local(file.path(bench_dir, "bench_text_async.log")) %>% as_async(flush_threshold = 1)
  )

  receivers_latency$json_async <- logger() %>% with_receivers(
    to_json() %>% on_local(file.path(bench_dir, "bench_json_async.jsonl")) %>% as_async(flush_threshold = 1)
  )
}

# Run benchmarks
results_latency <- bench::mark(
  console = receivers_latency$console(test_event),
  text_file = receivers_latency$text_file(test_event),
  json_file = receivers_latency$json_file(test_event),
  csv_file = receivers_latency$csv_file(test_event),
  identity = receivers_latency$identity(test_event),
  iterations = 100,
  check = FALSE
)

print(results_latency[, c("expression", "min", "median", "mem_alloc")])

if (requireNamespace("mirai", quietly = TRUE)) {
  message("\nAsync receiver latency (includes queue time only):")
  results_async_latency <- bench::mark(
    text_async = receivers_latency$text_async(test_event),
    json_async = receivers_latency$json_async(test_event),
    iterations = 100,
    check = FALSE
  )
  print(results_async_latency[, c("expression", "min", "median", "mem_alloc")])
}

# ==============================================================================
# Benchmark 2: Throughput (Multiple Events)
# ==============================================================================

message("\n", strrep("-", 80))
message("Benchmark 2: Throughput (1000 Events)")
message(strrep("-", 80), "\n")

message("Measuring events/second for different receivers...\n")

# Create loggers for throughput test
log_text_sync <- logger() %>% with_receivers(
  to_text() %>% on_local(file.path(bench_dir, "throughput_text_sync.log"))
)

log_json_sync <- logger() %>% with_receivers(
  to_json() %>% on_local(file.path(bench_dir, "throughput_json_sync.jsonl"))
)

log_csv_sync <- logger() %>% with_receivers(
  to_csv() %>% on_local(file.path(bench_dir, "throughput_csv_sync.csv"))
)

log_identity <- logger() %>% with_receivers(to_identity())

# Throughput test function
run_throughput_test <- function(log_func, n = 1000) {
  for (i in 1:n) {
    log_func(NOTE("Event", id = i, value = runif(1), status = "test"))
  }
}

# Run throughput benchmarks
results_throughput <- bench::mark(
  text_1000 = run_throughput_test(log_text_sync, 1000),
  json_1000 = run_throughput_test(log_json_sync, 1000),
  csv_1000 = run_throughput_test(log_csv_sync, 1000),
  identity_1000 = run_throughput_test(log_identity, 1000),
  iterations = 10,
  check = FALSE
)

# Calculate events/second
results_throughput$events_per_sec <- 1000 / as.numeric(results_throughput$median)

print(results_throughput[, c("expression", "median", "events_per_sec", "mem_alloc")])

# Async throughput if available
if (requireNamespace("mirai", quietly = TRUE)) {
  message("\nAsync throughput (includes queue time only, writes happen in background):")

  log_text_async <- logger() %>% with_receivers(
    to_text() %>% on_local(file.path(bench_dir, "throughput_text_async.log")) %>% as_async(flush_threshold = 100)
  )

  log_json_async <- logger() %>% with_receivers(
    to_json() %>% on_local(file.path(bench_dir, "throughput_json_async.jsonl")) %>% as_async(flush_threshold = 100)
  )

  results_async_throughput <- bench::mark(
    text_async_1000 = run_throughput_test(log_text_async, 1000),
    json_async_1000 = run_throughput_test(log_json_async, 1000),
    iterations = 10,
    check = FALSE
  )

  results_async_throughput$events_per_sec <- 1000 / as.numeric(results_async_throughput$median)

  print(results_async_throughput[, c("expression", "median", "events_per_sec", "mem_alloc")])

  # Wait for async writes to complete
  Sys.sleep(1)
}

# ==============================================================================
# Benchmark 3: Buffered vs Non-Buffered (Parquet)
# ==============================================================================

if (requireNamespace("arrow", quietly = TRUE)) {
  message("\n", strrep("-", 80))
  message("Benchmark 3: Buffered Parquet Performance")
  message(strrep("-", 80), "\n")

  message("Comparing different flush thresholds for Parquet logging...\n")

  log_parquet_10 <- logger() %>% with_receivers(
    to_parquet() %>% on_local(file.path(bench_dir, "parquet_10.parquet"), flush_threshold = 10)
  )

  log_parquet_100 <- logger() %>% with_receivers(
    to_parquet() %>% on_local(file.path(bench_dir, "parquet_100.parquet"), flush_threshold = 100)
  )

  log_parquet_1000 <- logger() %>% with_receivers(
    to_parquet() %>% on_local(file.path(bench_dir, "parquet_1000.parquet"), flush_threshold = 1000)
  )

  results_buffering <- bench::mark(
    flush_10 = run_throughput_test(log_parquet_10, 1000),
    flush_100 = run_throughput_test(log_parquet_100, 1000),
    flush_1000 = run_throughput_test(log_parquet_1000, 1000),
    iterations = 5,
    check = FALSE
  )

  results_buffering$events_per_sec <- 1000 / as.numeric(results_buffering$median)

  print(results_buffering[, c("expression", "median", "events_per_sec", "mem_alloc")])

  message("\nObservation: Higher flush thresholds = better throughput but higher latency")
}

# ==============================================================================
# Benchmark 4: Scaling Test (10 to 10,000 events)
# ==============================================================================

message("\n", strrep("-", 80))
message("Benchmark 4: Scaling Test")
message(strrep("-", 80), "\n")

message("Testing how performance scales with event volume...\n")

log_scale <- logger() %>% with_receivers(
  to_text() %>% on_local(file.path(bench_dir, "scale_test.log"))
)

scaling_results <- data.frame(
  n_events = integer(),
  median_time = numeric(),
  events_per_sec = numeric()
)

for (n in c(10, 100, 1000, 5000, 10000)) {
  message("Testing with ", n, " events...")

  result <- bench::mark(
    run_throughput_test(log_scale, n),
    iterations = 5,
    check = FALSE
  )

  scaling_results <- rbind(scaling_results, data.frame(
    n_events = n,
    median_time = as.numeric(result$median),
    events_per_sec = n / as.numeric(result$median)
  ))
}

print(scaling_results)

message("\nScaling factor (time ratio):")
for (i in 2:nrow(scaling_results)) {
  ratio <- scaling_results$median_time[i] / scaling_results$median_time[i-1]
  expected_ratio <- scaling_results$n_events[i] / scaling_results$n_events[i-1]
  message(sprintf("%d -> %d events: %.2fx time (expected: %.1fx)",
                  scaling_results$n_events[i-1],
                  scaling_results$n_events[i],
                  ratio,
                  expected_ratio))
}

# ==============================================================================
# Benchmark 5: Memory Usage
# ==============================================================================

message("\n", strrep("-", 80))
message("Benchmark 5: Memory Profiling")
message(strrep("-", 80), "\n")

message("Measuring memory footprint for different receivers...\n")

if (requireNamespace("bench", quietly = TRUE)) {
  # Memory test for sync receivers
  mem_test_sync <- bench::mark(
    text_100 = run_throughput_test(
      logger() %>% with_receivers(to_text() %>% on_local(file.path(bench_dir, "mem_text.log"))),
      100
    ),
    json_100 = run_throughput_test(
      logger() %>% with_receivers(to_json() %>% on_local(file.path(bench_dir, "mem_json.jsonl"))),
      100
    ),
    csv_100 = run_throughput_test(
      logger() %>% with_receivers(to_csv() %>% on_local(file.path(bench_dir, "mem_csv.csv"))),
      100
    ),
    iterations = 10,
    check = FALSE
  )

  print(mem_test_sync[, c("expression", "mem_alloc", "n_gc")])

  # Async memory test
  if (requireNamespace("mirai", quietly = TRUE)) {
    message("\nAsync receiver memory (queued events held in memory):")

    mem_test_async <- bench::mark(
      async_100 = run_throughput_test(
        logger() %>% with_receivers(
          to_text() %>% on_local(file.path(bench_dir, "mem_async.log")) %>% as_async(flush_threshold = 1000)
        ),
        100
      ),
      iterations = 10,
      check = FALSE
    )

    print(mem_test_async[, c("expression", "mem_alloc", "n_gc")])

    Sys.sleep(1)  # Let async writes complete
  }
}

# ==============================================================================
# Benchmark 6: Overhead of Logger Components
# ==============================================================================

message("\n", strrep("-", 80))
message("Benchmark 6: Component Overhead")
message(strrep("-", 80), "\n")

message("Measuring overhead of different logger features...\n")

log_bare <- logger() %>% with_receivers(to_identity())

log_with_tags <- logger() %>%
  with_receivers(to_identity()) %>%
  with_tags("prod", "api", "us-west-2")

log_with_limits <- logger() %>%
  with_receivers(to_identity()) %>%
  with_limits(lower = DEBUG, upper = ERROR)

results_overhead <- bench::mark(
  bare = log_bare(NOTE("Event", id = 1)),
  with_tags = log_with_tags(NOTE("Event", id = 1)),
  with_limits = log_with_limits(NOTE("Event", id = 1)),
  iterations = 1000,
  check = FALSE
)

print(results_overhead[, c("expression", "min", "median", "mem_alloc")])

message("\nOverhead analysis:")
baseline <- as.numeric(results_overhead$median[1])
for (i in 2:nrow(results_overhead)) {
  overhead_pct <- ((as.numeric(results_overhead$median[i]) - baseline) / baseline) * 100
  message(sprintf("  %s: +%.1f%% overhead vs bare logger",
                  results_overhead$expression[i],
                  overhead_pct))
}

# ==============================================================================
# Summary Report
# ==============================================================================

message("\n", strrep("=", 80))
message("BENCHMARK SUMMARY")
message(strrep("=", 80), "\n")

message("Key Findings:\n")

# Find fastest and slowest receivers
fastest <- results_latency[which.min(results_latency$median), ]
slowest <- results_latency[which.max(results_latency$median), ]

message("1. Single Event Latency:")
message(sprintf("   Fastest: %s (%.2f µs)",
                fastest$expression,
                as.numeric(fastest$median) * 1e6))
message(sprintf("   Slowest: %s (%.2f µs)",
                slowest$expression,
                as.numeric(slowest$median) * 1e6))

message("\n2. Throughput (1000 events):")
best_throughput <- results_throughput[which.max(results_throughput$events_per_sec), ]
message(sprintf("   Best: %s (%.0f events/sec)",
                best_throughput$expression,
                best_throughput$events_per_sec))

if (requireNamespace("mirai", quietly = TRUE)) {
  async_best <- results_async_throughput[which.max(results_async_throughput$events_per_sec), ]
  message(sprintf("   Async: %s (%.0f events/sec, queue time only)",
                  async_best$expression,
                  async_best$events_per_sec))
}

message("\n3. Scaling:")
linear_factor <- scaling_results$n_events[nrow(scaling_results)] / scaling_results$n_events[1]
time_factor <- scaling_results$median_time[nrow(scaling_results)] / scaling_results$median_time[1]
message(sprintf("   %d -> %d events: %.1fx time (%.1fx expected) - %.0f%% linear",
                scaling_results$n_events[1],
                scaling_results$n_events[nrow(scaling_results)],
                time_factor,
                linear_factor,
                (linear_factor / time_factor) * 100))

message("\n4. Memory Efficiency:")
message(sprintf("   Typical allocation per 100 events: %s",
                format(mem_test_sync$mem_alloc[1], units = "auto")))

message("\n5. Logger Overhead:")
message(sprintf("   Tags: +%.1f%% vs bare logger",
                ((as.numeric(results_overhead$median[2]) - baseline) / baseline) * 100))
message(sprintf("   Limits: +%.1f%% vs bare logger",
                ((as.numeric(results_overhead$median[3]) - baseline) / baseline) * 100))

message("\n", strrep("=", 80))
message("Benchmark files written to: ", bench_dir)
message(strrep("=", 80), "\n")

# Cleanup
if (requireNamespace("mirai", quietly = TRUE)) {
  mirai::daemons(0)
}

message("\n✅ All benchmarks completed successfully!\n")
