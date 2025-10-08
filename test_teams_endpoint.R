# Test script for to_teams() receiver with Power Automate endpoint
# This script tests the Microsoft Teams integration
#
# Usage: Rscript test_teams_endpoint.R

# Load required packages
library(magrittr)  # For %>% operator

# Load package
source("R/aaa.R")
source("R/log_event_levels.R")
source("R/logger.R")
source("R/receivers.R")

# Power Automate endpoint (from user)
TEAMS_WEBHOOK_URL <- "https://defaultfcb2b37b5da0466b9b830014b67a7c.78.environment.api.powerplatform.com:443/powerautomate/automations/direct/workflows/dbbc7728cd4b4abaa8c8f1ef7d582d78/triggers/manual/paths/invoke?api-version=1&sp=%2Ftriggers%2Fmanual%2Frun&sv=1.0&sig=wz3S4f_5sTBpvOYJA9Srit0C7oBGV8b_UgcxgarwEmg"

cat("Testing to_teams() receiver with Power Automate endpoint...\n\n")

# Test 1: Create Teams receiver
cat("Test 1: Creating Teams receiver...\n")
teams_recv <- tryCatch({
  to_teams(webhook_url = TEAMS_WEBHOOK_URL,
           title = "logthis Test Run",
           lower = NOTE,
           upper = HIGHEST)
}, error = function(e) {
  cat("  ERROR:", conditionMessage(e), "\n")
  NULL
})

if (is.null(teams_recv)) {
  cat("FAILED: Could not create Teams receiver\n")
  quit(status = 1)
}
cat("  SUCCESS: Teams receiver created\n\n")

# Test 2: Create logger with Teams receiver
cat("Test 2: Creating logger with Teams receiver...\n")
log_test <- logger() %>%
  with_receivers(teams_recv) %>%
  with_tags("test-run", "automated")

cat("  SUCCESS: Logger created\n\n")

# Test 3: Send test events
cat("Test 3: Sending test events to Teams...\n")

# NOTE level (should show as Steel Blue in Teams)
cat("  Sending NOTE event...\n")
log_test(NOTE("Test NOTE: logthis Teams integration working!",
              test_id = "T001",
              status = "success"))
Sys.sleep(2)  # Wait between requests to avoid rate limiting

# WARNING level (should show as Orange in Teams)
cat("  Sending WARNING event...\n")
log_test(WARNING("Test WARNING: This is a test warning message",
                 test_id = "T002",
                 component = "webhook-test"))
Sys.sleep(2)

# ERROR level (should show as Crimson in Teams)
cat("  Sending ERROR event...\n")
log_test(ERROR("Test ERROR: This is a test error message",
               test_id = "T003",
               error_code = 500,
               details = "Simulated error for testing"))
Sys.sleep(2)

# CRITICAL level with tags (should show as Crimson with tags in Facts)
cat("  Sending CRITICAL event with tags...\n")
event <- CRITICAL("Test CRITICAL: System-level test event") %>%
  with_tags("high-priority", "system")
log_test(event)

cat("\n")
cat("Test 3: COMPLETED\n\n")

cat("=====================================\n")
cat("All tests completed!\n")
cat("Check your Teams channel for 4 MessageCards:\n")
cat("  1. NOTE (blue) - Integration working\n")
cat("  2. WARNING (orange) - Test warning\n")
cat("  3. ERROR (crimson) - Test error\n")
cat("  4. CRITICAL (crimson with tags) - System event\n")
cat("=====================================\n")
