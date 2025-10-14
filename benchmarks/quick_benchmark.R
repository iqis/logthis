# ==============================================================================
# Quick Performance Check
# ==============================================================================
# Fast benchmark for development - tests basic performance metrics
# Run from package root: Rscript benchmarks/quick_benchmark.R

library(logthis)
library(magrittr)

cat("\n=== Quick logthis Performance Check ===\n\n")

# Create temp directory
bench_dir <- tempfile("logthis_quick_")
dir.create(bench_dir)

# Test 1: Basic latency
cat("1. Single event latency (1000 iterations):\n")

log_console <- logger() %>% with_receivers(to_console())
log_text <- logger() %>% with_receivers(
  to_text() %>% on_local(file.path(bench_dir, "test.log"))
)
log_json <- logger() %>% with_receivers(
  to_json() %>% on_local(file.path(bench_dir, "test.jsonl"))
)

test_event <- NOTE("Test event", id = 1, value = 42)

# Console
t_console <- system.time({
  for (i in 1:1000) log_console(test_event)
})

# Text file
t_text <- system.time({
  for (i in 1:1000) log_text(test_event)
})

# JSON file
t_json <- system.time({
  for (i in 1:1000) log_json(test_event)
})

cat(sprintf("   Console: %.2f ms/event (%.0f events/sec)\n",
            t_console["elapsed"] * 1000 / 1000,
            1000 / t_console["elapsed"]))

cat(sprintf("   Text:    %.2f ms/event (%.0f events/sec)\n",
            t_text["elapsed"] * 1000 / 1000,
            1000 / t_text["elapsed"]))

cat(sprintf("   JSON:    %.2f ms/event (%.0f events/sec)\n",
            t_json["elapsed"] * 1000 / 1000,
            1000 / t_json["elapsed"]))

# Test 2: Async vs sync
if (requireNamespace("mirai", quietly = TRUE)) {
  cat("\n2. Async vs Sync (1000 events):\n")

  mirai::daemons(2)

  log_sync <- logger() %>% with_receivers(
    to_text() %>% on_local(file.path(bench_dir, "sync.log"))
  )

  log_async <- logger() %>% with_receivers(
    to_text() %>% on_local(file.path(bench_dir, "async.log")) %>% as_async(flush_threshold = 100)
  )

  t_sync <- system.time({
    for (i in 1:1000) log_sync(NOTE("Event", id = i))
  })

  t_async <- system.time({
    for (i in 1:1000) log_async(NOTE("Event", id = i))
  })

  cat(sprintf("   Sync:  %.2f ms total (%.0f events/sec)\n",
              t_sync["elapsed"] * 1000,
              1000 / t_sync["elapsed"]))

  cat(sprintf("   Async: %.2f ms total (%.0f events/sec)\n",
              t_async["elapsed"] * 1000,
              1000 / t_async["elapsed"]))

  speedup <- t_sync["elapsed"] / t_async["elapsed"]
  cat(sprintf("   Speedup: %.1fx faster (queue time only)\n", speedup))

  # Wait for async to finish
  Sys.sleep(0.5)
  mirai::daemons(0)
} else {
  cat("\n2. Async benchmarks skipped (mirai not installed)\n")
}

# Test 3: Overhead of features
cat("\n3. Feature overhead (1000 events):\n")

log_bare <- logger() %>% with_receivers(to_identity())

log_tags <- logger() %>%
  with_receivers(to_identity()) %>%
  with_tags("prod", "api", "us-west")

log_limits <- logger() %>%
  with_receivers(to_identity()) %>%
  with_limits(lower = DEBUG, upper = ERROR)

t_bare <- system.time({
  for (i in 1:1000) log_bare(NOTE("Event", id = i))
})

t_tags <- system.time({
  for (i in 1:1000) log_tags(NOTE("Event", id = i))
})

t_limits <- system.time({
  for (i in 1:1000) log_limits(NOTE("Event", id = i))
})

cat(sprintf("   Bare logger: %.3f ms/event\n", t_bare["elapsed"] * 1000 / 1000))
cat(sprintf("   With tags:   %.3f ms/event (+%.0f%%)\n",
            t_tags["elapsed"] * 1000 / 1000,
            ((t_tags["elapsed"] - t_bare["elapsed"]) / t_bare["elapsed"]) * 100))
cat(sprintf("   With limits: %.3f ms/event (+%.0f%%)\n",
            t_limits["elapsed"] * 1000 / 1000,
            ((t_limits["elapsed"] - t_bare["elapsed"]) / t_bare["elapsed"]) * 100))

# Cleanup
unlink(bench_dir, recursive = TRUE)

cat("\n✅ Quick benchmark complete!\n")
cat("   For detailed benchmarks, run: Rscript benchmarks/benchmark_receivers.R\n\n")
