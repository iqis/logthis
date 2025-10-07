# logthis Use Cases → Implementation Map

Concrete examples mapping user intent to implementation. Each use case includes the problem, solution, and file references.

---

## UC-001: Log to console

**User says**: "I want to log messages to the console"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(to_console())

log_this(NOTE("Application started"))
log_this(ERROR("Something failed", error_code = 500))
```

**Key functions**:
- `logger()` - R/logger.R:14
- `to_console()` - R/receivers.R:85
- `NOTE()`, `ERROR()` - R/log_event_levels.R:96-113

---

## UC-002: Log to file

**User says**: "I want to log messages to a file"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(to_text_file("app.log"))

log_this(MESSAGE("User logged in", user_id = 123))
```

**Key functions**:
- `to_text_file()` - R/receivers.R:380

**Alternative (more control)**:
```r
log_this <- logger() %>%
  with_receivers(
    to_text("{time} [{level}] {message}") %>%
      on_local("app.log", append = TRUE)
  )
```
- `to_text()` - R/receivers.R:46
- `on_local()` - R/receivers.R:125

---

## UC-003: Rotate log files by size

**User says**: "I want to rotate log files when they get too big"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(
    to_text_file(path = "app.log",
                 max_size = 10485760,  # 10MB
                 max_files = 5)
  )
```

**What happens**:
- Current logs in `app.log`
- When size exceeds max_size:
  - `app.log` → `app.log.1`
  - `app.log.1` → `app.log.2`
  - ... (keep max_files)
  - New content → `app.log`

**Key functions**:
- `to_text_file()` with max_size - R/receivers.R:380
- `.rotate_file()` (internal) - R/receivers.R:540

---

## UC-004: Log to multiple destinations

**User says**: "I want to log to console AND file simultaneously"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(
    to_console(),
    to_text_file("app.log"),
    to_json_file("events.jsonl")
  )

log_this(WARNING("Disk space low", available_gb = 2.5))
# → Appears in console, app.log, and events.jsonl
```

**Key functions**:
- `with_receivers()` - R/logger.R:115
- Takes multiple receivers as `...` arguments

---

## UC-005: Filter by log level (logger-level)

**User says**: "I only want WARNING and above to be logged anywhere"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(
    to_console(),
    to_text_file("app.log")
  ) %>%
  with_limits(lower = WARNING, upper = HIGHEST)

log_this(NOTE("This is filtered out"))       # Ignored
log_this(WARNING("This appears everywhere"))  # Logged
log_this(ERROR("This also appears"))          # Logged
```

**Key functions**:
- `with_limits.logger()` - R/logger.R:193
- Filters before any receiver sees event

---

## UC-006: Different levels for different receivers

**User says**: "I want console to show only errors, but file to show everything"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(
    to_console(lower = ERROR),       # Console: ERROR+ only
    to_text_file("detailed.log")     # File: all levels
  )

log_this(NOTE("Detailed info"))      # Only in file
log_this(WARNING("Heads up"))        # Only in file
log_this(ERROR("Something broke"))   # Console + file
```

**Key functions**:
- `to_console(lower = ...)` - R/receivers.R:85
- `with_limits.log_receiver()` - R/receivers.R:321

---

## UC-007: Custom log format

**User says**: "I want a custom format for my logs"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(
    to_text("{time} | {level}:{level_number} | {message}") %>%
      on_local("custom.log")
  )

log_this(NOTE("Custom formatted"))
# Output: 2025-10-07 10:23:45 | NOTE:30 | Custom formatted
```

**Available template variables**:
- `{time}` - event timestamp
- `{level}` - level name (e.g., "NOTE")
- `{level_number}` - numeric level (e.g., 30)
- `{message}` - event message
- `{tags}` - formatted tags (e.g., "[api, v2]")
- `{field_name}` - any custom field

**Key functions**:
- `to_text(template)` - R/receivers.R:46

---

## UC-008: Add tags to events

**User says**: "I want to categorize events with tags"

**Solution**:
```r
# Per-event tags
log_this(NOTE("User login", tags = c("auth", "success")))

# Global tags (applied to all events)
log_this <- logger() %>%
  with_receivers(to_console()) %>%
  with_tags("api", "production")

log_this(NOTE("Request received", tags = "metrics"))
# Event has tags: ["api", "production", "metrics"]
```

**Template usage**:
```r
log_this <- logger() %>%
  with_receivers(
    to_text("{time} {tags} [{level}] {message}") %>%
      on_local("tagged.log")
  )
```

**Key functions**:
- `log_event(..., tags = ...)` - R/log_events.R:6
- `with_tags()` - R/logger.R:241

---

## UC-009: Add custom fields to events

**User says**: "I want to include extra context with log events"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(to_json_file("events.jsonl"))

log_this(ERROR("Payment failed",
               user_id = 12345,
               transaction_id = "txn_abc123",
               amount = 99.99,
               payment_method = "credit_card"))

# JSON output includes all custom fields:
# {
#   "time": "2025-10-07T10:23:45",
#   "level": "ERROR",
#   "level_number": 80,
#   "message": "Payment failed",
#   "user_id": 12345,
#   "transaction_id": "txn_abc123",
#   "amount": 99.99,
#   "payment_method": "credit_card"
# }
```

**Use in templates**:
```r
log_this <- logger() %>%
  with_receivers(
    to_text("{time} [{level}] {message} | User: {user_id}") %>%
      on_local("app.log")
  )

log_this(NOTE("Action performed", user_id = 456))
# Output: 2025-10-07 10:23:45 [NOTE] Action performed | User: 456
```

**Key functions**:
- `log_event(message, ...)` - R/log_events.R:6 (captures `...` as custom fields)

---

## UC-010: Log to AWS S3

**User says**: "I want to send logs to AWS S3"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(
    to_json() %>%
      on_s3(bucket = "my-app-logs",
            key = "production/app.jsonl",
            region = "us-east-1")
  )

log_this(ERROR("Service degradation", latency_ms = 5000))
```

**Requirements**:
- `aws.s3` package installed
- AWS credentials configured (env vars or ~/.aws/credentials)

**Key functions**:
- `to_json()` - R/receivers.R:100
- `on_s3()` - R/receivers.R:181
- `.build_s3_receiver()` (internal) - R/receivers.R:468

---

## UC-011: Log to Azure Blob Storage

**User says**: "I want to send logs to Azure Blob Storage"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(
    to_json() %>%
      on_azure(container = "logs",
               blob = "app.jsonl",
               connection_string = Sys.getenv("AZURE_STORAGE_CONNECTION_STRING"))
  )

log_this(WARNING("Rate limit approaching", requests = 950, limit = 1000))
```

**Requirements**:
- `AzureStor` package installed
- Azure connection string configured

**Key functions**:
- `to_json()` - R/receivers.R:100
- `on_azure()` - R/receivers.R:234
- `.build_azure_receiver()` (internal) - R/receivers.R:503

---

## UC-012: Pipeline-style logging

**User says**: "I want to log in the middle of a data pipeline"

**Solution**:
```r
log_this <- logger() %>% with_receivers(to_console())

result <- my_data %>%
  filter(status == "active") %>%
  log_this(NOTE("Filtered to active records")) %>%
  mutate(score = calculate_score(.)) %>%
  log_this(NOTE("Calculated scores")) %>%
  arrange(desc(score))
```

**Why it works**: Logger returns event unchanged, preserving pipeline data

**Key behavior**:
- Logger function returns the input event unmodified
- Events pass through transparently

**Implementation**: R/logger.R:14 (logger returns `event` at end)

---

## UC-013: Scope-based logger enhancement

**User says**: "I want to add extra logging in a specific function without changing the base logger"

**Solution**:
```r
# Base logger (shared)
.base_logger <- logger() %>%
  with_receivers(to_console())

# Enhanced logger (function-specific)
my_function <- function(data) {
  log_this <- .base_logger %>%
    with_receivers(to_text_file("my_function_detail.log")) %>%
    with_tags("my_function")

  log_this(NOTE("Function started", rows = nrow(data)))
  # ... function logic ...
  log_this(NOTE("Function complete"))
}
```

**Pattern**: Loggers are immutable; `with_receivers()` creates new logger with added receivers

**Key functions**:
- `with_receivers(..., append = TRUE)` - R/logger.R:115 (default appends)

---

## UC-014: Disable logging in production

**User says**: "I want zero-overhead logging for production"

**Solution**:
```r
if (Sys.getenv("ENVIRONMENT") == "production") {
  log_this <- void_logger()
} else {
  log_this <- logger() %>%
    with_receivers(to_console(), to_text_file("debug.log"))
}

# Logging calls have no effect in production
log_this(TRACE("Very verbose debug info"))
log_this(NOTE("This is skipped in production"))
```

**Key functions**:
- `void_logger()` - R/logger.R:87
- Returns no-op function with zero overhead

---

## UC-015: Create custom log level

**User says**: "I need an AUDIT level for compliance logging"

**Solution**:
```r
# Define custom level (between NOTE and MESSAGE)
AUDIT <- log_event_level("AUDIT", 35)

# Use it
log_this <- logger() %>% with_receivers(to_text_file("audit.log"))

log_this(AUDIT("User accessed sensitive data",
               user_id = 789,
               resource = "customer_pii",
               action = "read"))
```

**Choosing level number**:
- TRACE=10, DEBUG=20, NOTE=30, MESSAGE=40, WARNING=60, ERROR=80, CRITICAL=90
- Pick number between existing levels based on severity
- AUDIT=35 is between NOTE(30) and MESSAGE(40)

**Key functions**:
- `log_event_level(name, number)` - R/log_event_levels.R:6

---

## UC-016: Handle receiver failures gracefully

**User says**: "I don't want one failing receiver to break all logging"

**Solution**: Built-in! Loggers catch and report receiver errors

```r
failing_receiver <- receiver(function(event) {
  stop("Simulated failure")
})

log_this <- logger() %>%
  with_receivers(
    to_console(),
    failing_receiver(),
    to_text_file("app.log")
  )

log_this(NOTE("Test message"))
# → Appears in console and app.log
# → Error message logged: "[ERROR] Receiver #2 failed: Simulated failure"
# → Includes receiver provenance for debugging
```

**Implementation**: R/logger.R:39-83 (execute_receivers with tryCatch)

---

## UC-017: Format JSON logs

**User says**: "I want structured JSON logs for parsing"

**Solution**:
```r
# Compact JSONL (one line per event)
log_this <- logger() %>%
  with_receivers(to_json_file("events.jsonl"))

# Pretty-printed JSON (human-readable)
log_this <- logger() %>%
  with_receivers(to_json_file("events.json", pretty = TRUE))

log_this(ERROR("Request failed",
               endpoint = "/api/users",
               status_code = 500,
               duration_ms = 234))
```

**Output (compact)**:
```json
{"time":"2025-10-07T10:23:45","level":"ERROR","level_number":80,"message":"Request failed","endpoint":"/api/users","status_code":500,"duration_ms":234}
```

**Key functions**:
- `to_json(pretty = FALSE)` - R/receivers.R:100
- `to_json_file(path, pretty = FALSE)` - R/receivers.R:423

---

## UC-018: Debug logger configuration

**User says**: "I want to see what my logger is configured to do"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(
    to_console(lower = WARNING),
    to_text_file("app.log")
  ) %>%
  with_limits(lower = NOTE, upper = HIGHEST) %>%
  with_tags("api", "v2")

# Pretty-print configuration
print(log_this)

# Access config programmatically
config <- attr(log_this, "config")
config$limits           # list(lower = NOTE, upper = HIGHEST)
config$receivers        # List of 2 receiver functions
config$receiver_labels  # c("to_console(lower = WARNING)", "to_text_file(\"app.log\")")
config$tags             # c("api", "v2")
```

**Key functions**:
- `print.logger()` - R/logger.R:259

---

## UC-019: Conditional logging based on level

**User says**: "I want to check if a level is enabled before expensive operations"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(to_console()) %>%
  with_limits(lower = WARNING, upper = HIGHEST)

# Check if level would be logged
if (NOTE >= attr(log_this, "config")$limits$lower) {
  expensive_debug_info <- compute_debug_info()  # Skip this!
  log_this(NOTE("Debug info", data = expensive_debug_info))
}

# Better: Just don't compute if filtered
if (as.numeric(attr(log_this, "config")$limits$lower) <= 30) {
  log_this(NOTE("Debug info", data = compute_debug_info()))
}
```

**Pattern**: Check logger limits before expensive computations

---

## UC-020: Replace all receivers

**User says**: "I want to completely replace receivers, not append"

**Solution**:
```r
log_this <- logger() %>%
  with_receivers(to_console(), to_text_file("old.log"))

# Replace all receivers
log_this <- log_this %>%
  with_receivers(to_json_file("new.jsonl"), append = FALSE)

# Now only has json_file receiver
config <- attr(log_this, "config")
length(config$receivers)  # 1
```

**Key parameter**:
- `with_receivers(..., append = FALSE)` - R/logger.R:115

---

## UC-021: Create custom formatter

**User says**: "I want to format logs as CSV"

**Solution**:
```r
to_csv <- function() {
  fmt_func <- formatter(function(event) {
    paste(
      event$time,
      event$level_class,
      event$level_number,
      event$message,
      sep = ","
    )
  })

  attr(fmt_func, "config") <- list(
    format_type = "csv",
    backend = NULL,
    backend_config = list()
  )

  fmt_func
}

# Use it
log_this <- logger() %>%
  with_receivers(
    to_csv() %>% on_local("events.csv")
  )
```

**Template**: .claude/templates/custom-formatter.R
**Key functions**:
- `formatter()` - R/receivers.R:16

---

## UC-022: Create custom handler (storage destination)

**User says**: "I want to send logs to a database"

**Solution**:
```r
on_database <- function(formatter, conn, table) {
  if (!inherits(formatter, "log_formatter")) {
    stop("formatter must be a log_formatter")
  }

  config <- attr(formatter, "config")
  config$backend <- "database"
  config$backend_config <- list(conn = conn, table = table)
  attr(formatter, "config") <- config

  formatter
}

# Add builder to .formatter_to_receiver() in R/receivers.R
.build_database_receiver <- function(formatter) {
  config <- attr(formatter, "config")$backend_config

  receiver(function(event) {
    formatted <- attr(formatter, "format_func")(event)
    DBI::dbAppendTable(config$conn, config$table,
                       data.frame(log_entry = formatted,
                                  timestamp = Sys.time()))
  })
}

# Use it
conn <- DBI::dbConnect(RSQLite::SQLite(), "logs.db")
log_this <- logger() %>%
  with_receivers(
    to_json() %>% on_database(conn, "log_events")
  )
```

**Template**: .claude/templates/custom-handler.R
**Key functions**:
- `on_xxx()` pattern - R/receivers.R:125,181,234
- `.formatter_to_receiver()` - R/receivers.R:278

---

## UC-023: Integrate with config package

**User says**: "I want to configure logging via config.yml"

**Solution**:
```yaml
# config.yml
default:
  logging:
    min_level: TRACE
    receivers:
      - console: true
      - file:
          path: "logs/app.log"
          max_size: 1048576
          max_files: 5

production:
  logging:
    min_level: WARNING
    receivers:
      - file:
          path: "/var/log/myapp/app.log"
          max_size: 10485760
          max_files: 50
      - s3:
          bucket: "prod-logs"
          key: "myapp/app.jsonl"
          region: "us-east-1"
```

```r
# R code
setup_logger_from_config <- function(env = Sys.getenv("R_CONFIG_ACTIVE", "default")) {
  cfg <- config::get(config = env)

  log <- logger()
  receivers <- list()

  for (recv_cfg in cfg$logging$receivers) {
    if (!is.null(recv_cfg$console) && recv_cfg$console) {
      receivers <- c(receivers, list(to_console()))
    }

    if (!is.null(recv_cfg$file)) {
      receivers <- c(receivers,
                     list(to_text_file(path = recv_cfg$file$path,
                                       max_size = recv_cfg$file$max_size,
                                       max_files = recv_cfg$file$max_files)))
    }

    if (!is.null(recv_cfg$s3)) {
      receivers <- c(receivers,
                     list(to_json() %>%
                            on_s3(bucket = recv_cfg$s3$bucket,
                                  key = recv_cfg$s3$key,
                                  region = recv_cfg$s3$region)))
    }
  }

  log %>%
    with_receivers(!!!receivers) %>%
    with_limits(lower = get(cfg$logging$min_level), upper = HIGHEST)
}

# Use it
log_this <- setup_logger_from_config()
```

**Reference**: scratch.md "Config Management Integration" section

---

## Quick Index by User Intent

| I want to... | Use Case |
|--------------|----------|
| Log to console | UC-001 |
| Log to file | UC-002 |
| Rotate log files | UC-003 |
| Log to multiple places | UC-004 |
| Filter by level (global) | UC-005 |
| Filter by level (per-receiver) | UC-006 |
| Custom format | UC-007 |
| Add tags | UC-008 |
| Add custom fields | UC-009 |
| Log to S3 | UC-010 |
| Log to Azure | UC-011 |
| Log in pipeline | UC-012 |
| Enhance logger in scope | UC-013 |
| Disable in production | UC-014 |
| Create custom level | UC-015 |
| Handle failures gracefully | UC-016 |
| Format as JSON | UC-017 |
| Debug configuration | UC-018 |
| Conditional logging | UC-019 |
| Replace receivers | UC-020 |
| Create custom formatter | UC-021 |
| Create custom handler | UC-022 |
| Use config.yml | UC-023 |
