# Test script for as_async() wrapper
# Demonstrates async logging with multiple receivers

library(logthis)
library(magrittr)

# Install mirai if needed (commented out for safety)
# install.packages("mirai")

if (!requireNamespace("mirai", quietly = TRUE)) {
  stop("This demo requires mirai. Install with: install.packages('mirai')")
}

cat("\n=== Test 1: Simple async text logging ===\n")

# Auto-init with 1 daemon
log_simple <- logger() %>%
  with_receivers(
    to_console(),
    to_text() %>% on_local("test_async_simple.log") %>% as_async(flush_threshold = 5)
  )

# Log some events
for (i in 1:10) {
  log_simple(NOTE("Processing item", id = i))
}

cat("\nWaiting for async writes to complete...\n")
Sys.sleep(0.5)

cat("\n=== Test 2: Multiple async receivers with daemon pool ===\n")

# Create daemon pool
mirai::daemons(4)
cat("Created daemon pool: ", mirai::daemons()$n, " workers\n")

# Multiple async receivers
log_multi <- logger() %>%
  with_receivers(
    to_console(),
    to_text() %>% on_local("test_async_text.log") %>% as_async(flush_threshold = 10),
    to_json() %>% on_local("test_async_json.jsonl") %>% as_async(flush_threshold = 10),
    to_csv() %>% on_local("test_async_csv.csv") %>% as_async(flush_threshold = 10)
  ) %>%
  with_tags("production", "test")

# High-frequency logging
cat("Logging 100 events...\n")
start_time <- Sys.time()

for (i in 1:100) {
  log_multi(NOTE("Event",
                 id = i,
                 value = runif(1, 0, 100),
                 status = sample(c("success", "pending", "failed"), 1)))
}

end_time <- Sys.time()
cat("Logged 100 events in:", format(end_time - start_time), "\n")
cat("Rate:", round(100 / as.numeric(end_time - start_time, units = "secs")), "events/sec\n")

cat("\nWaiting for async writes to complete...\n")
Sys.sleep(1)

cat("\n=== Test 3: Using deferred() alias ===\n")

log_deferred <- logger() %>%
  with_receivers(
    to_text() %>% on_local("test_deferred.log") %>% deferred(flush_threshold = 5)
  )

for (i in 1:10) {
  log_deferred(WARNING("Deferred event", id = i))
}

Sys.sleep(0.5)

cat("\n=== Test 4: Async with different receivers ===\n")

# Even works with standalone receivers!
log_mixed <- logger() %>%
  with_receivers(
    to_console(),  # Sync
    to_text() %>% on_local("test_mixed.log") %>% as_async(),  # Async text
    to_json() %>% on_local("test_mixed.jsonl") %>% as_async()  # Async JSON
  )

log_mixed(NOTE("Sync and async together"))
log_mixed(WARNING("High latency detected", latency_ms = 1500))
log_mixed(ERROR("Connection failed", service = "database", retry_count = 3))

Sys.sleep(0.5)

cat("\n=== Cleanup ===\n")
mirai::daemons(0)
cat("Daemon pool stopped\n")

cat("\n=== Output files created ===\n")
list.files(pattern = "test_.*\\.(log|jsonl|csv)$")

cat("\n=== Sample from test_async_text.log ===\n")
if (file.exists("test_async_text.log")) {
  cat(paste(readLines("test_async_text.log", n = 5), collapse = "\n"), "\n")
}

cat("\n=== Sample from test_async_json.jsonl ===\n")
if (file.exists("test_async_json.jsonl")) {
  cat(paste(readLines("test_async_json.jsonl", n = 3), collapse = "\n"), "\n")
}

cat("\n✅ All async tests completed successfully!\n")
