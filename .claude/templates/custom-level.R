# Template: Custom Log Event Level
# Purpose: Define application-specific log levels
# Pattern: Use log_event_level() to create level constructor

# ============================================================================
# Standard Levels Reference (0-100 scale)
# ============================================================================
#
# LOWEST    = 0   (virtual boundary, filtering only)
# TRACE     = 10  (ultra-verbose debugging)
# DEBUG     = 20  (debugging information)
# NOTE      = 30  (notable events, not just debugging)
# MESSAGE   = 40  (general informational messages)
# WARNING   = 60  (warning conditions)
# ERROR     = 80  (error conditions)
# CRITICAL  = 90  (critical conditions)
# HIGHEST   = 100 (virtual boundary, filtering only)

# ============================================================================
# Creating a Custom Level
# ============================================================================

# Step 1: Choose a number
# - Must be in range [1, 99] (0 and 100 reserved for LOWEST/HIGHEST)
# - Place between existing levels based on severity
# - Consider spacing for future levels

# Step 2: Create level using log_event_level()
AUDIT <- log_event_level("AUDIT", 35)  # Between NOTE(30) and MESSAGE(40)

# Step 3: Use like any standard level
if (FALSE) {
  library(logthis)

  log_this <- logger() %>%
    with_receivers(to_console())

  log_this(AUDIT("User accessed sensitive data",
                 user_id = 12345,
                 resource = "customer_pii",
                 action = "read"))
}

# ============================================================================
# Example Custom Levels by Use Case
# ============================================================================

# Business/Audit Logging
AUDIT <- log_event_level("AUDIT", 35)        # Between NOTE and MESSAGE
METRIC <- log_event_level("METRIC", 38)      # Between NOTE and MESSAGE

# Performance Monitoring
PERF_TRACE <- log_event_level("PERF_TRACE", 15)   # Between TRACE and DEBUG
PERF_WARN <- log_event_level("PERF_WARN", 65)     # Between WARNING and ERROR

# Security Events
SEC_INFO <- log_event_level("SEC_INFO", 45)       # Between MESSAGE and WARNING
SEC_ALERT <- log_event_level("SEC_ALERT", 70)     # Between WARNING and ERROR
SEC_BREACH <- log_event_level("SEC_BREACH", 95)   # Between CRITICAL and HIGHEST

# Application Lifecycle
STARTUP <- log_event_level("STARTUP", 42)         # Between MESSAGE and WARNING
SHUTDOWN <- log_event_level("SHUTDOWN", 43)       # Between MESSAGE and WARNING

# ============================================================================
# Adding Console Colors (Optional)
# ============================================================================

# To add color for your custom level in console output, extend .LEVEL_COLOR_MAP
# in R/aaa.R

# Example: Adding AUDIT level color
if (FALSE) {
  # In R/aaa.R, modify .LEVEL_COLOR_MAP:

  .LEVEL_COLOR_MAP <- list(
    levels = c(0, 10, 20, 30, 35, 40, 60, 80, 90),  # Added 35
    colors = list(
      crayon::white,                              # LOWEST (0)
      crayon::silver,                             # TRACE (10)
      crayon::cyan,                               # DEBUG (20)
      crayon::green,                              # NOTE (30)
      crayon::magenta,                            # AUDIT (35) - NEW!
      crayon::yellow,                             # MESSAGE (40)
      crayon::red,                                # WARNING (60)
      purrr::compose(crayon::red, crayon::bold),  # ERROR (80)
      purrr::compose(crayon::red, crayon::bold)   # CRITICAL+ (90-100)
    )
  )
}

# ============================================================================
# Level Comparison and Filtering
# ============================================================================

# Custom levels work with comparison operators
if (FALSE) {
  AUDIT <- log_event_level("AUDIT", 35)

  # Comparison
  AUDIT > NOTE       # TRUE (35 > 30)
  AUDIT < MESSAGE    # TRUE (35 < 40)

  # Filtering
  log_this <- logger() %>%
    with_receivers(to_console()) %>%
    with_limits(lower = AUDIT, upper = HIGHEST)  # Only AUDIT+ events

  log_this(NOTE("Filtered out"))           # Ignored (30 < 35)
  log_this(AUDIT("Appears"))               # Logged (35 >= 35)
  log_this(MESSAGE("Also appears"))        # Logged (40 > 35)
}

# ============================================================================
# Complete Example: Security Logging System
# ============================================================================

if (FALSE) {
  library(logthis)

  # Define security levels
  SEC_INFO <- log_event_level("SEC_INFO", 45)
  SEC_ALERT <- log_event_level("SEC_ALERT", 70)
  SEC_BREACH <- log_event_level("SEC_BREACH", 95)

  # Create specialized logger
  sec_logger <- logger() %>%
    with_receivers(
      # Console: Show all security events
      to_console(lower = SEC_INFO),

      # File: Detailed log of all security events
      to_json() %>%
        on_local("security.jsonl", lower = SEC_INFO),

      # Alert file: Only alerts and breaches
      to_json() %>%
        on_local("security_alerts.jsonl", lower = SEC_ALERT),

      # S3: Archive breaches to secure storage
      to_json() %>%
        on_s3(bucket = "security-logs",
              key = "breaches.jsonl",
              region = "us-east-1",
              lower = SEC_BREACH)
    ) %>%
    with_tags("security")

  # Use it
  sec_logger(SEC_INFO("User login attempt",
                      user_id = 123,
                      ip = "192.168.1.1",
                      success = TRUE))

  sec_logger(SEC_ALERT("Multiple failed login attempts",
                       user_id = 456,
                       ip = "10.0.0.1",
                       attempts = 5))

  sec_logger(SEC_BREACH("Unauthorized access detected",
                        user_id = 789,
                        resource = "admin_panel",
                        ip = "203.0.113.0"))
}

# ============================================================================
# Complete Example: Performance Monitoring
# ============================================================================

if (FALSE) {
  library(logthis)

  # Define performance levels
  PERF_TRACE <- log_event_level("PERF_TRACE", 15)
  PERF_INFO <- log_event_level("PERF_INFO", 35)
  PERF_WARN <- log_event_level("PERF_WARN", 65)

  # Create performance logger
  perf_logger <- logger() %>%
    with_receivers(
      # Console: Only warnings
      to_console(lower = PERF_WARN),

      # File: All performance data
      to_json() %>%
        on_local("performance.jsonl")
    ) %>%
    with_tags("performance")

  # Measure and log
  start <- Sys.time()
  # ... expensive operation ...
  elapsed_ms <- as.numeric(difftime(Sys.time(), start, units = "secs")) * 1000

  # Log with appropriate level
  if (elapsed_ms < 100) {
    perf_logger(PERF_TRACE("Operation completed", duration_ms = elapsed_ms))
  } else if (elapsed_ms < 1000) {
    perf_logger(PERF_INFO("Operation completed", duration_ms = elapsed_ms))
  } else {
    perf_logger(PERF_WARN("Slow operation", duration_ms = elapsed_ms))
  }
}

# ============================================================================
# Complete Example: Business Metrics
# ============================================================================

if (FALSE) {
  library(logthis)

  # Define business event levels
  METRIC <- log_event_level("METRIC", 38)
  BUSINESS_EVENT <- log_event_level("BUSINESS_EVENT", 44)
  BUSINESS_ALERT <- log_event_level("BUSINESS_ALERT", 62)

  # Create business logger
  biz_logger <- logger() %>%
    with_receivers(
      # Metrics to analytics system
      to_json() %>%
        on_s3(bucket = "analytics",
              key = "metrics.jsonl",
              lower = METRIC),

      # Important events to database
      to_json() %>%
        on_database(conn, "business_events",
                    lower = BUSINESS_EVENT)
    ) %>%
    with_tags("business")

  # Log business events
  biz_logger(METRIC("Page view",
                    page = "/pricing",
                    user_id = 123,
                    session_id = "abc"))

  biz_logger(BUSINESS_EVENT("Purchase completed",
                            user_id = 123,
                            order_id = "ORD-456",
                            amount = 99.99))

  biz_logger(BUSINESS_ALERT("Revenue target missed",
                            target = 10000,
                            actual = 8500))
}

# ============================================================================
# Best Practices
# ============================================================================

# 1. Choose meaningful names
#    - Use domain-specific terminology
#    - Make severity clear from name
#    - Consider standard conventions (AUDIT, METRIC, etc.)

# 2. Pick appropriate numbers
#    - Leave gaps between levels for future additions
#    - Group related levels together (e.g., SEC_* in 45-95 range)
#    - Consider existing level semantics

# 3. Document level usage
#    - When should this level be used?
#    - What information should be included?
#    - Who/what consumes these events?

# 4. Consider level hierarchy
#    - Will you filter on this level?
#    - How does it relate to existing levels?
#    - What receivers should see it?

# 5. Add colors thoughtfully
#    - Only if users will see it on console
#    - Choose distinct colors from existing levels
#    - Consider accessibility (colorblind-friendly)

# ============================================================================
# Level Number Guidelines
# ============================================================================

# Range          Use Case
# 1-10          Reserved (near LOWEST boundary)
# 11-19         Extra verbose debugging
# 21-29         Debugging variants
# 31-39         Informational/notable events
# 41-59         General application events
# 61-79         Warnings and alerts
# 81-89         Errors
# 91-99         Critical/fatal events
# 100           Reserved (HIGHEST boundary)

# ============================================================================
# Integration Checklist
# ============================================================================

# □ Level number chosen (1-99)
# □ Level number appropriate for severity
# □ Level created with log_event_level(name, number)
# □ Level exported in NAMESPACE (if in package)
# □ Level documented (roxygen2)
# □ Color added to .LEVEL_COLOR_MAP (optional)
# □ Tests added for level comparison
# □ Tests added for level filtering
# □ Usage examples provided
