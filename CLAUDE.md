# logthis - AI Assistant Context

**Last Updated:** 2025-10-08
**Package Version:** 0.1.0.9000
**Status:** Production-ready, CRAN submission pending

## Development Environment

### Current Environment Detection

To determine which environment you're in, check these indicators:

**1. Docker Container Detection:**
```bash
test -f /.dockerenv && echo "In Docker" || echo "On host"
```

**2. code-server Detection:**
```bash
ps aux | grep -i code-server | grep -v grep
# If processes found: Running in code-server container
```

**3. Devcontainer Detection:**
```bash
# Check if running in GitHub Codespaces or devcontainer
test -n "$CODESPACES" && echo "GitHub Codespaces" || \
test -n "$REMOTE_CONTAINERS" && echo "VS Code devcontainer" || \
echo "Not in devcontainer"
```

### Environment Types

**Environment 1: GitHub Codespaces (Direct Devcontainer)**
- Running directly in `.devcontainer/` environment
- Full R development environment available
- Docker not available inside container (Codespaces limitation)
- Best for: R package development, testing, documentation

**Environment 2: code-server with Docker-in-Docker (Local Development)**
- Running in code-server container (`/app/code-server`)
- Docker CLI available via socket mount (`/var/run/docker.sock`)
- Can build and run devcontainers using `devcontainer` CLI
- Working directory: `/home/siqi/projects/logthis`
- Best for: When GitHub Codespaces unavailable, local control needed

**Environment 3: Host Machine**
- Direct access to system
- Full Docker control
- Can manage code-server container from outside
- Best for: Container orchestration, infrastructure changes

### Current Session Environment

Based on detection, this session is running in: **code-server with Docker-in-Docker**

Evidence:
- `/.dockerenv` exists (Docker container)
- code-server processes running on port 8443
- Can access `/var/run/docker.sock` for Docker commands
- User: `siqi`, working directory: `/home/siqi/projects/logthis`

### Using Devcontainers from code-server

When in code-server environment, you can build and run the logthis devcontainer:

```bash
# Build devcontainer image
cd /home/siqi/projects/logthis
devcontainer build --workspace-folder .

# Run devcontainer interactively
devcontainer up --workspace-folder .

# Execute commands in devcontainer
devcontainer exec --workspace-folder . R CMD check .
```

**Note:** See `REBUILD_CODE_SERVER.md` for rebuilding code-server with Docker support.

## Project Overview

`logthis` is a structured logging framework for R that provides enterprise-level logging capabilities similar to log4j or Python's logging module. It uses functional composition patterns and is designed for R packages, Shiny applications, data analysis pipelines, and **pharmaceutical/clinical compliance systems**.

**Key Use Cases:**
- R package development logging
- Shiny application debugging and monitoring
- Data pipeline audit trails
- **Pharmaceutical audit trails** (21 CFR Part 11, ALCOA+, GxP compliance)
- Clinical trial data access logging
- Manufacturing batch records (GMP)
- Pharmacovigilance adverse event reporting

**Core Philosophy:**
- Functional, composable design with pipe-friendly syntax
- No side effects in loggers (they return events invisibly for chaining)
- Two-level filtering (logger-level + receiver-level)
- Resilient error handling (one receiver failure doesn't stop others)

## Architecture & Key Concepts

### Event Flow
```
Event → Logger Middleware → Logger Filter (with_limits) → Apply Logger Tags →
  Receiver 1 Middleware → Receiver 1 Filter → Receiver 1 Output
  Receiver 2 Middleware → Receiver 2 Filter → Receiver 2 Output
```

### Core Components

1. **Log Events** - Structured data with metadata (message, time, level, tags, custom fields)
2. **Event Levels** - Hierarchical 0-100 scale (LOWEST=0, TRACE=10, DEBUG=20, NOTE=30, MESSAGE=40, WARNING=60, ERROR=80, CRITICAL=90, HIGHEST=100)
3. **Loggers** - Functions that process events through configured receivers
4. **Middleware** - Functions that transform events (logger-level or receiver-level)
5. **Receivers** - Functions that output events (console, files, Shiny alerts, etc.)

### Design Patterns

**Closure-based Configuration:**
```r
logger <- function() {
  structure(function(event, ...) { ... },  # The logger function
            config = list(...))             # Configuration in attributes
}
```

**Receiver Pattern:**
- Receivers are functions: `function(event) { ... }`
- Must return `invisible(NULL)` (called for side effects)
- Wrapped with `receiver()` constructor for validation
- Can have optional level filtering via `lower`/`upper` parameters

**Formatter/Handler Composition:**
```r
# Formatters define HOW events are formatted
to_text(template = "{time} [{level}] {message}")  # Returns log_formatter
to_json(pretty = FALSE)                            # Returns log_formatter

# Handlers define WHERE formatted output goes
on_local(path = "app.log", max_size = 1e6)         # Attaches local filesystem handler
on_s3(bucket = "logs", key = "app.jsonl")          # Attaches S3 handler
on_azure(container = "logs", blob = "app.log")     # Attaches Azure handler

# Compose: formatter + handler = receiver (auto-converted by with_receivers)
logger() %>%
  with_receivers(to_text() %>% on_local(path = "app.log"),
                 to_json() %>% on_s3(bucket = "logs", key = "events.jsonl"))
```
**Key insight:** Easy to add new formats (write `to_xyz()`) or new handlers (write `on_xyz()`) independently

**Logger Chaining:**
```r
WARNING("msg") %>% log_console() %>% log_file()  # Event flows through both
```

**Scope-based Masking:**
```r
# Parent logger
log_this <- logger() %>% with_receivers(to_console())

my_function <- function() {
  # Child logger adds receivers, doesn't affect parent
  log_this <- log_this %>% with_receivers(to_text_file("scope.log"))
  log_this(NOTE("Only in this scope"))
}
```

**Middleware Pattern:**
```r
# Logger-level middleware (transforms ALL events before filtering)
log_this <- logger() %>%
  with_middleware(
    redact_pii,           # Stage 1: Security
    add_context,          # Stage 2: Enrichment
    sample_by_level()     # Stage 3: Volume control
  ) %>%
  with_receivers(to_console(), to_json() %>% on_local("app.jsonl"))

# Receiver-level middleware (transforms events per-receiver)
logger() %>%
  with_receivers(
    # Full redaction for console
    to_console() %>% with_middleware(redact_full),

    # Partial redaction for internal logs
    to_json() %>% on_local("internal.jsonl") %>% with_middleware(redact_partial),

    # No redaction for secure vault
    to_json() %>% on_s3(bucket = "vault", key = "full.jsonl")
  )
```
**Key insight:** Same `with_middleware()` function works on loggers AND receivers via S3 dispatch. Logger middleware runs before filtering (can modify levels), receiver middleware runs per-receiver (differential transforms).

### Error Handling

**Resilient Receiver Execution (R/logger.R:56-84):**
- All receivers wrapped with `purrr::safely()`
- Failures logged as ERROR events with `receiver_error` tag
- Fallback to `to_console()`, then `warning()` as last resort
- Error messages include receiver #, error message, and receiver call

## File Structure

### Core Files (R/)
- **aaa.R** - Package-level utilities, color map, level guards (loaded first)
- **logger.R** - Core logger implementation, `with_*()` functions
- **log_event_levels.R** - Event level constructors (NOTE, WARNING, ERROR, etc.)
- **receivers.R** - All built-in receivers (console, file, JSON, Shiny, testing)
- **print-logger.R** - Print methods for logger inspection
- **zzz.R** - Package hooks (`.onLoad` exports `log_this` void logger)
- **utils-pipe.R** - Pipe operator re-exports

### Testing Structure (tests/testthat/)
- **test-logger.R** - Logger creation, filtering, chaining, tagging
- **test-receivers.R** - Receiver configuration, filtering, error handling
- **test-log-event-levels.R** - Event level creation and validation
- **test-tags.R** - Tagging at event/level/logger levels (24 tests)
- **test-with_limits.R** - Limit setting and validation

**Coverage:** 84.30% (Shiny receivers untestable without active session)
**Test Count:** 130 passing tests

### Vignettes (vignettes/)
- **getting-started.Rmd** - Quick introduction to logthis for new users
- **tagging-and-provenance.Rmd** - Using tags for context and audit trails
- **patterns.Rmd** - Common logging patterns and best practices
- **advanced-receivers.Rmd** - Cloud storage, webhooks, and custom receivers
- **python-comparison.Rmd** - Comprehensive comparison with Python logging ecosystem
  - Architecture comparison (logging, loguru, structlog)
  - General audit logging patterns (Django, structlog)
  - **Pharmaceutical and clinical audit trails** (21 CFR Part 11, ALCOA+, GxP)
    - Clinical trial data access logging
    - Manufacturing batch records (GMP compliance)
    - Pharmacovigilance adverse event reporting
    - Computer System Validation (CSV) documentation
    - Electronic signatures and regulatory compliance
- **migration-guide.Rmd** - Migrating from other R logging packages

## Code Conventions

### Naming
- **Functions:** `snake_case` (e.g., `with_receivers`, `to_console`)
- **Classes:** Prefix with `log_` (e.g., `log_event`, `log_receiver`, `log_event_level`)
- **Internal:** Prefix with `.` for package-level constants (e.g., `.LEVEL_COLOR_MAP`)
- **Exported constants:** ALL_CAPS for event levels (NOTE, WARNING, ERROR)

### Roxygen2 Patterns
- Use `@export` for all public functions
- Return type format: `@return <class>; description`
- Always include `@examples` for exported functions
- Use `@family` tags: `logger_configuration`, `receivers`, `event_levels`
- Cross-reference with `@seealso`

### Level Filtering Logic
**IMPORTANT:** All level limits are **inclusive**. An event passes if:
```r
event$level_number >= lower AND event$level_number <= upper
```

### Receiver Implementation Pattern
```r
to_my_receiver <- function(config_param = "default", lower = LOWEST(), upper = HIGHEST()) {
  receiver(function(event) {
    # Check receiver-level filtering
    if (event$level_number < attr(lower, "level_number") ||
        event$level_number > attr(upper, "level_number")) {
      return(invisible(NULL))
    }

    # Do the actual work (side effects)
    cat("Output:", event$message, "\n")

    # Always return NULL for receivers
    invisible(NULL)
  })
}
```

## Testing Approach

### Unit Test Strategy
1. **Isolation:** Test each component independently
2. **Testing Receivers:** Use `to_itself()` (or `to_identity()`) to capture events for inspection
3. **Shiny Receivers:** Document as untestable without session (acceptable coverage gap)
4. **Error Handling:** Test receiver failures using custom failing receivers

### Running Tests
```r
# All tests
devtools::test()

# Specific file
testthat::test_file("tests/testthat/test-logger.R")

# Coverage report
covr::package_coverage()
```

### Test File Template
```r
test_that("descriptive test name", {
  # Setup
  log_capture <- logger() %>% with_receivers(to_itself())

  # Execute
  result <- log_capture(WARNING("test message"))

  # Assert
  expect_equal(result$level_class, "WARNING")
  expect_equal(result$message, "test message")
})
```

## Common Tasks

### Adding a Line-Based Formatter (CSV, Text, JSON)

1. **Create formatter function in R/receivers.R:**
```r
#' @export
#' @family formatters
to_csv <- function(separator = ",", quote = "\"", headers = TRUE) {
  # Closure state for headers
  headers_written <- FALSE

  fmt_func <- formatter(function(event) {
    # CSV escaping logic
    escape_csv_field <- function(value, sep, quo) {
      # ... escaping implementation
    }

    # Build header row on first call
    if (!headers_written && headers) {
      headers_written <<- TRUE
      header_line <- paste0("time,level,level_number,message,tags\n")
      # ... header logic
    }

    # Build data row
    fields <- c(
      as.character(event$time),
      event$level_class,
      as.character(as.numeric(event$level_number)),  # Convert S3 class to numeric!
      event$message
    )
    paste(sapply(fields, escape_csv_field, sep = separator, quo = quote), collapse = separator)
  })

  # Attach config
  attr(fmt_func, "config") <- list(
    format_type = "csv",
    separator = separator,
    backend = NULL,
    backend_config = list(),
    lower = NULL,
    upper = NULL
  )
  fmt_func
}
```

**Key points:**
- Use closure state (`headers_written`) for stateful formatting
- Always convert `event$level_number` to numeric (it's an S3 class that breaks JSON serialization!)
- Return string (not data frame) for line-based formats

2. **Usage:** `to_csv() %>% on_local(path = "app.csv")`

---

### Adding a Buffered Formatter (Parquet, Feather)

**Use Case:** Columnar formats that benefit from batching events before writing

1. **Create formatter that returns data frames:**
```r
#' @export
#' @family formatters
to_parquet <- function(compression = "snappy") {
  fmt_func <- formatter(function(event) {
    # Return single-row data frame (not string!)
    row_data <- data.frame(
      time = event$time,
      level = event$level_class,
      level_number = as.integer(as.numeric(event$level_number)),  # Convert to integer!
      message = event$message,
      stringsAsFactors = FALSE
    )

    # Tags as list column (Arrow supports this!)
    row_data$tags <- I(list(event$tags))

    # Add custom fields
    custom_fields <- setdiff(names(event), c("time", "level_class", "level_number", "message", "tags"))
    for (field in custom_fields) {
      row_data[[field]] <- I(list(event[[field]]))  # Store as list column
    }

    row_data
  })

  # CRITICAL: Set requires_buffering flag
  attr(fmt_func, "config") <- list(
    format_type = "parquet",
    compression = compression,
    backend = NULL,
    backend_config = list(),
    lower = NULL,
    upper = NULL,
    requires_buffering = TRUE  # This tells handlers to use buffered receiver!
  )
  fmt_func
}
```

**Key points:**
- Return data frame (not string!) for buffered formats
- Set `requires_buffering = TRUE` in config
- Use list columns (`I(list(...))`) for complex fields
- Handlers will automatically detect this flag and use `.build_buffered_local_receiver()`

2. **Handler support:** Already implemented in `on_local()` via `.build_buffered_local_receiver()`

3. **Usage:** `to_parquet() %>% on_local(path = "app.parquet", flush_threshold = 1000)`

---

### Adding a New Handler

1. **Create handler function in R/receivers.R:**
```r
#' @export
#' @family handlers
on_gcs <- function(formatter, bucket, object, project, ...) {
  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter")
  }

  config <- attr(formatter, "config")
  config$backend <- "gcs"
  config$backend_config <- list(bucket = bucket,
                                 object = object,
                                 project = project,
                                 extra_args = list(...))

  attr(formatter, "config") <- config
  formatter
}
```

2. **Create builder in R/receivers.R (internal):**
```r
.build_gcs_receiver <- function(formatter, config) {
  bc <- config$backend_config

  receiver(function(event) {
    # Level filtering
    if (!is.null(config$lower) &&
        event$level_number < attr(config$lower, "level_number")) {
      return(invisible(NULL))
    }

    # Format and write to GCS
    content <- formatter(event)
    # googleCloudStorageR::gcs_upload(content, ...)

    invisible(NULL)
  })
}
```

3. **Add to dispatcher in .formatter_to_receiver():**
```r
} else if (config$backend == "gcs") {
  .build_gcs_receiver(formatter, config)
```

---

### Adding a Webhook Handler (HTTP Integration)

**Use Case:** Send formatted logs to HTTP endpoints (generic pattern for any webhook)

**Example:** `on_webhook()` for sending JSON/text to any HTTP endpoint

```r
#' @export
#' @family handlers
on_webhook <- function(formatter, url, method = "POST",
                       headers = NULL, content_type = NULL,
                       timeout_seconds = 30, max_tries = 3, ...) {
  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter")
  }

  # Auto-detect content type from formatter if not specified
  if (is.null(content_type)) {
    format_type <- attr(formatter, "config")$format_type
    content_type <- switch(format_type,
                           "text" = "text/plain",
                           "json" = "application/json",
                           "text/plain")  # Default fallback
  }

  config <- attr(formatter, "config")
  config$backend <- "webhook"
  config$backend_config <- list(
    url = url,
    method = method,
    headers = headers,
    content_type = content_type,
    timeout_seconds = timeout_seconds,
    max_tries = max_tries,
    extra_args = list(...)
  )

  attr(formatter, "config") <- config
  formatter
}
```

**Builder implementation:**
```r
.build_webhook_receiver <- function(formatter, config) {
  bc <- config$backend_config

  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("Package 'httr2' required for webhook receivers")
  }

  receiver(function(event) {
    # Level filtering
    if (!is.null(config$lower) &&
        event$level_number < attr(config$lower, "level_number")) {
      return(invisible(NULL))
    }

    # Format event
    content <- formatter(event)

    # Send HTTP request
    tryCatch({
      req <- httr2::request(bc$url)
      req <- httr2::req_method(req, bc$method)
      req <- httr2::req_body_raw(req, charToRaw(content))
      req <- httr2::req_headers(req, `Content-Type` = bc$content_type)
      req <- httr2::req_timeout(req, bc$timeout_seconds)

      if (bc$max_tries > 1) {
        req <- httr2::req_retry(req, max_tries = bc$max_tries)
      }

      resp <- httr2::req_perform(req)
    }, error = function(e) {
      warning("Webhook request failed: ", conditionMessage(e), call. = FALSE)
    })

    invisible(NULL)
  })
}
```

**Usage:**
```r
# Send JSON logs to webhook
to_json() %>% on_webhook(url = "https://webhook.site/xyz")

# Send text logs with custom headers
to_text() %>% on_webhook(
  url = "https://api.example.com/logs",
  headers = list(Authorization = "Bearer TOKEN")
)
```

---

### Adding a Standalone Receiver (Protocol-Specific)

**Use Case:** Receivers that implement specific protocols (Teams, Slack, Syslog) don't use formatter/handler composition

**Example 1: Microsoft Teams with Adaptive Cards**

```r
#' @export
#' @family receivers
to_teams <- function(webhook_url, title = "Application Log",
                     lower = WARNING, upper = HIGHEST,
                     timeout_seconds = 30, max_tries = 3, ...) {
  # Validate inputs
  if (!is.character(webhook_url) || length(webhook_url) != 1) {
    stop("`webhook_url` must be a non-empty character string")
  }

  # Extract level numbers for filtering
  lower_num <- attr(lower, "level_number")
  upper_num <- attr(upper, "level_number")

  receiver(function(event) {
    # Level filtering
    if (event$level_number < lower_num || event$level_number > upper_num) {
      return(invisible(NULL))
    }

    # Build Adaptive Card JSON (protocol-specific!)
    # Power Automate expects this exact structure
    facts_list <- list()
    facts_list[[length(facts_list) + 1]] <- list(
      title = "Level",
      value = paste0(event$level_class, " (", as.numeric(event$level_number), ")")
    )
    # ... build complete Adaptive Card structure

    payload <- list(
      type = "message",
      attachments = list(
        list(
          contentType = "application/vnd.microsoft.card.adaptive",
          content = list(
            `$schema` = "http://adaptivecards.io/schemas/adaptive-card.json",
            type = "AdaptiveCard",
            version = "1.2",
            body = list(/* ... card elements ... */)
          )
        )
      )
    )

    # Send to Teams
    json_body <- jsonlite::toJSON(payload, auto_unbox = TRUE)
    # ... httr2 request logic

    invisible(NULL)
  })
}
```

**Key differences from formatter+handler pattern:**
- **No formatter composition**: Builds payload directly in receiver
- **Protocol-specific**: Adaptive Card format is specific to Teams
- **Standalone**: Can't be split into to_adaptive_card() %>% on_teams()
- **Complete receiver**: Returns `log_receiver`, not `log_formatter`

**Example 2: Syslog with RFC Support**

```r
#' @export
#' @family receivers
to_syslog <- function(host = "localhost", port = 514,
                      protocol = c("rfc3164", "rfc5424"),
                      transport = c("udp", "tcp", "unix"),
                      facility = "user", app_name = "R",
                      lower = LOWEST, upper = HIGHEST) {
  protocol <- match.arg(protocol)
  transport <- match.arg(transport)

  # Validate facility
  facility_map <- c("user" = 1, "local0" = 16, ..., "local7" = 23)
  if (!facility %in% names(facility_map)) {
    stop("Invalid facility: ", facility)
  }
  facility_code <- facility_map[[facility]]

  # Level to severity mapping (0-7 syslog scale)
  get_syslog_severity <- function(level_number) {
    if (level_number >= 100) 0      # emergency
    else if (level_number >= 90) 2  # critical
    else if (level_number >= 80) 3  # error
    # ... complete mapping
  }

  # Connection pooling with closure
  conn <- NULL
  get_connection <- function() {
    if (is.null(conn) || !isOpen(conn)) {
      conn <<- socketConnection(host, port, blocking = FALSE)
    }
    conn
  }

  receiver(function(event) {
    # Level filtering
    if (event$level_number < attr(lower, "level_number") ||
        event$level_number > attr(upper, "level_number")) {
      return(invisible(NULL))
    }

    # Calculate priority
    severity <- get_syslog_severity(event$level_number)
    priority <- (facility_code * 8) + severity

    # Format message (protocol-specific!)
    if (protocol == "rfc5424") {
      # RFC 5424: <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID SD MSG
      msg <- sprintf("<%d>1 %s %s %s - - - %s",
                     priority, format(event$time, "%Y-%m-%dT%H:%M:%S%z"),
                     Sys.info()["nodename"], app_name, event$message)
    } else {
      # RFC 3164: <PRI>TIMESTAMP HOSTNAME TAG: MSG
      msg <- sprintf("<%d>%s %s %s: %s",
                     priority, format(event$time, "%b %d %H:%M:%S"),
                     Sys.info()["nodename"], app_name, event$message)
    }

    # Send via appropriate transport
    tryCatch({
      conn <- get_connection()
      writeLines(msg, conn)
    }, error = function(e) {
      conn <<- NULL  # Reset connection on error
      warning("Syslog send failed: ", conditionMessage(e), call. = FALSE)
    })

    invisible(NULL)
  })
}
```

**When to use standalone receivers:**
- Protocol has specific message format (Adaptive Cards, Syslog RFC)
- Formatting and transport are tightly coupled
- No value in splitting into formatter + handler

**When to use formatter + handler:**
- Format is reusable (JSON, CSV, Text can go to files, S3, webhooks)
- Transport is generic (HTTP POST, file write, cloud upload)

---

### Adding a New Receiver

1. **Create receiver function in R/receivers.R:**
```r
#' @export
#' @family receivers
to_my_output <- function(param = "default", lower = LOWEST(), upper = HIGHEST()) {
  receiver(function(event) {
    # Filtering
    if (event$level_number < attr(lower, "level_number") ||
        event$level_number > attr(upper, "level_number")) {
      return(invisible(NULL))
    }

    # Implementation
    # ... your output logic ...

    invisible(NULL)
  })
}
```

2. **Add tests in tests/testthat/test-receivers.R**
3. **Document in README.md** (Built-in Receivers section)
4. **Update roxygen2:** `devtools::document()`

### Adding a New Event Level

```r
# In R/log_event_levels.R or user code
MY_LEVEL <- log_event_level("MY_LEVEL", 35)  # Between NOTE(30) and MESSAGE(40)
```

### Adding Logger Configuration

1. Add to `config` list in `logger()` (R/logger.R:92-96)
2. Create `with_*()` function following pattern at R/logger.R:244+
3. Add tests in tests/testthat/test-logger.R
4. Document with `@family logger_configuration`

## Important Gotchas

### 1. Receiver Attributes
- **receiver_labels** stores plain text (not pairlists!)
- Used for error messages and `print.logger()`
- Must sync with `receivers` list length

### 2. Shiny Dependencies
- `to_shinyalert()` and `to_notif()` require active Shiny session
- Will fail outside Shiny context
- Test coverage gap is expected and acceptable

### 3. Level Filtering Edge Cases
- Limits are **inclusive** on both ends
- Valid ranges: `lower  [0, 99]`, `upper  [1, 100]`
- Early return in logger if event outside limits (R/logger.R:44-47)

### 4. Logger Returns
- Loggers return events **invisibly** for chaining
- Receivers return `invisible(NULL)` (side effects only)
- Don't confuse the two return patterns

### 5. Tag Combination
Tags from all three sources are combined (order matters):
1. Event-level tags (innermost)
2. Event level constructor tags (via `with_tags.log_event_level()`)
3. Logger-level tags (R/logger.R:50-53)

### 6. File Rotation (to_text_file)
- `max_size` in bytes (not MB/GB)
- Rotation: log.txt � log.1.txt � log.2.txt
- `max_files` excludes current file (total = max_files + 1)

### 7. JSON Logging (to_json_file)
- Outputs JSONL format (one JSON object per line)
- Compact by default, use `pretty = TRUE` for debugging
- Always append mode (no rotation yet)

### 8. **CRITICAL: level_number Serialization** ⚠️
**Problem:** `event$level_number` is an S3 class, not a plain numeric!

**Symptom:** `jsonlite::toJSON()` fails with "No method asJSON S3 class: level_number"

**Solution:** Always convert to numeric before serialization:
```r
# WRONG - breaks JSON/CSV/any serialization
payload <- list(level_number = event$level_number)

# CORRECT - convert S3 class to numeric
payload <- list(level_number = as.numeric(event$level_number))
```

**Affected areas:**
- JSON formatters (`to_json()`)
- CSV formatters (`to_csv()`)
- HTTP payloads (`to_teams()`, webhook receivers)
- Any data frame construction (`to_parquet()`, `to_feather()`)

**Why it exists:** `level_number` has class `c("log_event_level_number", "numeric")` to enable S3 method dispatch for printing/comparison.

---

### 9. Buffered Receiver Pattern
**Flag:** `requires_buffering = TRUE` in formatter config

**Purpose:** Signals handlers to accumulate data frames instead of writing line-by-line

**Implementation:**
```r
# Formatter sets flag
attr(fmt_func, "config")$requires_buffering <- TRUE

# Handler checks flag and dispatches
if (isTRUE(config$requires_buffering)) {
  return(.build_buffered_local_receiver(formatter, config))
} else {
  return(.build_local_receiver(formatter, config))  # Line-based
}
```

**Used by:** `to_parquet()`, `to_feather()` (any columnar format)

**Buffering logic:**
- Accumulate events in `buffer_df` (data frame)
- Flush when `nrow(buffer_df) >= flush_threshold`
- Use `rbind()` or `dplyr::bind_rows()` for row accumulation
- Flush on finalizer for graceful shutdown

---

### 10. Closure State in Formatters
**Pattern:** Use closure variables for stateful formatting

**Example:** CSV headers written only once
```r
to_csv <- function() {
  headers_written <- FALSE  # Closure variable

  formatter(function(event) {
    if (!headers_written) {
      headers_written <<- TRUE  # Modify closure state
      # ... write headers
    }
    # ... write data row
  })
}
```

**Use cases:**
- First-run initialization (CSV headers)
- Cumulative state (event counters)
- Configuration caching

**Note:** Closure state persists across receiver calls but resets if receiver is recreated

---

### 11. Connection Pooling in Network Receivers
**Pattern:** Reuse connections across events, reconnect on failure

```r
to_syslog <- function(host, port) {
  conn <- NULL  # Closure variable for connection

  get_connection <- function() {
    if (is.null(conn) || !isOpen(conn)) {
      conn <<- socketConnection(host, port, blocking = FALSE)
    }
    conn
  }

  receiver(function(event) {
    tryCatch({
      c <- get_connection()
      writeLines(msg, c)
    }, error = function(e) {
      conn <<- NULL  # Reset on error, will reconnect next time
    })
  })
}
```

**Benefits:**
- Avoid connection overhead per event
- Automatic reconnection on network failures
- Minimal latency for high-frequency logging

---

### 12. Power Automate Adaptive Card Structure
**Critical:** Power Automate expects a very specific JSON structure for Teams

**Wrong approach** (won't render):
```r
# MessageCard schema - doesn't work with Power Automate
payload <- list(
  `@type` = "MessageCard",
  `@context` = "https://schema.org/extensions",
  summary = "Log message"
)
```

**Correct approach** (Adaptive Card):
```r
# Adaptive Card schema - works with Power Automate
payload <- list(
  type = "message",
  attachments = list(
    list(
      contentType = "application/vnd.microsoft.card.adaptive",
      content = list(
        `$schema` = "http://adaptivecards.io/schemas/adaptive-card.json",
        type = "AdaptiveCard",
        version = "1.2",
        body = list(
          list(type = "TextBlock", text = "Log message")
        )
      )
    )
  )
)
```

**Why:** Power Automate's "send webhook to channel" workflow expects Adaptive Cards, not MessageCards

**Design tool:** https://adaptivecards.io/designer/ for testing payloads

---

### 13. Buffered Receiver Data Frame Accumulation
**Pattern:** Use `I(list(...))` for complex fields in data frames

```r
# Store tags as list column (not character vector!)
row_data$tags <- I(list(event$tags))

# Store custom fields as list columns
row_data$custom_field <- I(list(event$custom_field))
```

**Why:** Arrow supports list columns, preserves nested structure

**Pitfall:** Without `I()`, R tries to expand vectors into multiple rows

**Usage:** Essential for Parquet/Feather formatters where fields vary per event

---

## Development Workflow

### Package Checks
```r
# Full check (run before commits)
devtools::check()

# Quick load during development
devtools::load_all()

# Update documentation
devtools::document()

# Run tests
devtools::test()
```

### Pre-commit Checklist
- [ ] All tests passing (`devtools::test()`)
- [ ] No R CMD check errors/warnings (`devtools::check()`)
- [ ] Documentation updated (`devtools::document()`)
- [ ] NEWS.md updated if user-facing changes
- [ ] Code coverage maintained or improved

### Git Workflow
- Main branch: `main`
- Feature branches: `feature/description`
- Clean commits, no force-push to main
- Squash minor commits before merging

## Current State & Next Steps

###  Complete (Production-Ready)
- Core logging functionality (loggers, events, receivers)
- Two-level filtering system
- Resilient error handling for receivers
- File rotation (to_text_file)
- JSON logging (to_json_file)
- Tag system (event/logger level)
- 130 passing tests, 84.30% coverage
- R CMD check: 0 errors, 0 warnings, 1 harmless note

### =� Partially Complete
- Event level tagging (`with_tags.log_event_level()` - TODO at R/logger.R:244-303)

### =� Future Enhancements (Post-CRAN)
- Async/buffered logging for high-volume scenarios
- Additional receivers (syslog, webhook, CSV)
- Performance benchmarks and optimization guide
- Migration guide from other logging packages
- Tag filtering/search utilities

### <� CRAN Submission Readiness
**Status:** Package is CRAN-ready. All success criteria met.

**Remaining tasks before submission:**
- [ ] Final review of cran-comments.md
- [ ] Verify all examples run cleanly
- [ ] Double-check DESCRIPTION completeness
- [ ] Test installation on fresh R environment

## References

- **Main Documentation:** README.md
- **Development Plan:** IMPROVEMENT_PLAN.md
- **Contributing:** CONTRIBUTING.md
- **Package Site:** https://iqis.github.io/logthis/
- **Issue Tracker:** https://github.com/iqis/logthis/issues

---

## Maintenance Notes for AI Assistants

**When making changes:**
1. Always read relevant test files before modifying code
2. Preserve functional composition patterns (no imperative refactors)
3. Maintain backward compatibility
4. Update tests, documentation, and this file when adding features
5. Follow roxygen2 conventions strictly
6. Never break the two-level filtering semantics
7. Keep receiver error handling resilient

**Common pitfall to avoid:**
- Don't add side effects to logger functions (they must be pure except for receiver calls)
- Don't skip receiver-level filtering in custom receivers
- Don't modify logger config in-place (always return new logger with updated attributes)

**When in doubt:**
- Check existing patterns in R/logger.R and R/receivers.R
- Consult test files for expected behavior
- Verify changes don't break the 130 existing tests
- when formatting, as much as possible, have the first argument to a function call on the same line as the (, and each argument on a new line) is this Lisp style? I like it very much.
- use function.method(): by which I mean that use appropriate general/method patterns wherever possible.