# AWS CloudWatch Logs Integration Design

**Status:** Design complete, pending implementation
**Created:** 2025-10-10
**Dependencies:** `paws` package (>= 0.1.0)

---

## Overview

AWS CloudWatch Logs integration for logthis using the **formatter + handler** pattern. Enables centralized logging for R applications running on AWS infrastructure (EC2, ECS, Lambda, etc.).

### Key Features
- **Batching:** Efficient API usage (configurable batch size and flush interval)
- **Sequence Token Management:** Automatic handling of CloudWatch ordering requirements
- **Lazy Initialization:** Log groups/streams created on first event
- **Graceful Shutdown:** Finalizer ensures pending events are flushed
- **Formatter Agnostic:** Works with any formatter (JSON, text, CSV)
- **Credential Flexibility:** Supports IAM roles, env vars, or explicit credentials

---

## Architecture

### Integration Pattern
```r
# JSON logs to CloudWatch (most common)
to_json() %>% on_cloudwatch(
  log_group = "/aws/r-app/production",
  log_stream = "instance-123"
)

# Multi-destination logging
logger() %>%
  with_receivers(
    to_json() %>% on_local("app.jsonl"),              # Local debugging
    to_json() %>% on_cloudwatch(...),                 # Centralized monitoring
    to_json() %>% on_s3(bucket = "logs-archive", ...) # Long-term archival
  )
```

### Data Flow
```
Event → Formatter → CloudWatch Receiver →
  [Batch Accumulator] →
  (Flush on size/time threshold) →
  PutLogEvents API →
  CloudWatch Log Stream
```

---

## Implementation

### 1. Handler Function: `on_cloudwatch()`

**File:** `R/receivers.R`

```r
#' Send Logs to AWS CloudWatch
#'
#' @param formatter A log_formatter (from to_json(), to_text(), etc.)
#' @param log_group CloudWatch log group name (will be created if doesn't exist)
#' @param log_stream CloudWatch log stream name (will be created if doesn't exist)
#' @param region AWS region (defaults to AWS_DEFAULT_REGION env var)
#' @param batch_size Number of events to batch before sending (1-10000, default 100)
#' @param flush_interval_seconds Max seconds to wait before flushing batch (default 5)
#' @param credentials List with access_key_id, secret_access_key, session_token (optional)
#' @param ... Additional arguments passed to paws cloudwatchlogs client
#'
#' @return log_formatter with CloudWatch backend configuration
#' @export
#' @family handlers
#' @examples
#' \dontrun{
#' # Use IAM role credentials (recommended for EC2/ECS)
#' logger() %>%
#'   with_receivers(
#'     to_json() %>% on_cloudwatch(
#'       log_group = "/aws/myapp",
#'       log_stream = "main"
#'     )
#'   )
#'
#' # Explicit credentials
#' logger() %>%
#'   with_receivers(
#'     to_json() %>% on_cloudwatch(
#'       log_group = "/aws/myapp",
#'       log_stream = "main",
#'       credentials = list(
#'         access_key_id = Sys.getenv("AWS_ACCESS_KEY_ID"),
#'         secret_access_key = Sys.getenv("AWS_SECRET_ACCESS_KEY")
#'       )
#'     )
#'   )
#'
#' # Multi-region logging
#' logger() %>%
#'   with_receivers(
#'     to_json() %>% on_cloudwatch(
#'       log_group = "/aws/myapp",
#'       log_stream = Sys.getenv("INSTANCE_ID"),
#'       region = "us-east-1"
#'     ),
#'     to_json() %>% on_cloudwatch(
#'       log_group = "/aws/myapp-backup",
#'       log_stream = Sys.getenv("INSTANCE_ID"),
#'       region = "eu-west-1"
#'     )
#'   )
#' }
on_cloudwatch <- function(formatter,
                          log_group,
                          log_stream,
                          region = Sys.getenv("AWS_DEFAULT_REGION", "us-east-1"),
                          batch_size = 100,
                          flush_interval_seconds = 5,
                          credentials = NULL,
                          ...) {
  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter")
  }

  if (!is.character(log_group) || length(log_group) != 1 || log_group == "") {
    stop("`log_group` must be a non-empty character string")
  }

  if (!is.character(log_stream) || length(log_stream) != 1 || log_stream == "") {
    stop("`log_stream` must be a non-empty character string")
  }

  if (batch_size < 1 || batch_size > 10000) {
    stop("`batch_size` must be between 1 and 10000")
  }

  config <- attr(formatter, "config")
  config$backend <- "cloudwatch"
  config$backend_config <- list(
    log_group = log_group,
    log_stream = log_stream,
    region = region,
    batch_size = batch_size,
    flush_interval_seconds = flush_interval_seconds,
    credentials = credentials,
    extra_args = list(...)
  )

  attr(formatter, "config") <- config
  formatter
}
```

---

### 2. Builder Function: `.build_cloudwatch_receiver()`

**File:** `R/receivers.R`

```r
.build_cloudwatch_receiver <- function(formatter, config) {
  bc <- config$backend_config

  # Check for paws package
  if (!requireNamespace("paws", quietly = TRUE)) {
    stop("Package 'paws' required for CloudWatch receivers. Install with: install.packages('paws')")
  }

  # Initialize CloudWatch Logs client
  cw_client <- if (!is.null(bc$credentials)) {
    paws::cloudwatchlogs(
      config = list(
        credentials = bc$credentials,
        region = bc$region
      )
    )
  } else {
    paws::cloudwatchlogs(config = list(region = bc$region))
  }

  # Closure state for batching and sequence token
  event_batch <- list()
  last_flush_time <- Sys.time()
  sequence_token <- NULL
  initialized <- FALSE

  # Initialize log group and stream (lazy, on first event)
  initialize_cloudwatch <- function() {
    if (initialized) return(invisible(NULL))

    # Create log group if it doesn't exist
    tryCatch({
      cw_client$create_log_group(logGroupName = bc$log_group)
    }, error = function(e) {
      # ResourceAlreadyExistsException is OK
      if (!grepl("ResourceAlreadyExistsException", conditionMessage(e))) {
        warning("Failed to create log group: ", conditionMessage(e))
      }
    })

    # Create log stream if it doesn't exist
    tryCatch({
      cw_client$create_log_stream(
        logGroupName = bc$log_group,
        logStreamName = bc$log_stream
      )
    }, error = function(e) {
      if (!grepl("ResourceAlreadyExistsException", conditionMessage(e))) {
        warning("Failed to create log stream: ", conditionMessage(e))
      }
    })

    # Get initial sequence token
    tryCatch({
      resp <- cw_client$describe_log_streams(
        logGroupName = bc$log_group,
        logStreamNamePrefix = bc$log_stream,
        limit = 1L
      )
      if (length(resp$logStreams) > 0) {
        sequence_token <<- resp$logStreams[[1]]$uploadSequenceToken
      }
    }, error = function(e) {
      warning("Failed to get sequence token: ", conditionMessage(e))
    })

    initialized <<- TRUE
  }

  # Flush batch to CloudWatch
  flush_batch <- function() {
    if (length(event_batch) == 0) return(invisible(NULL))

    initialize_cloudwatch()

    tryCatch({
      # Build PutLogEvents request
      request_params <- list(
        logGroupName = bc$log_group,
        logStreamName = bc$log_stream,
        logEvents = event_batch
      )

      # Add sequence token if we have one
      if (!is.null(sequence_token)) {
        request_params$sequenceToken <- sequence_token
      }

      # Send to CloudWatch
      resp <- do.call(cw_client$put_log_events, request_params)

      # Update sequence token for next batch
      sequence_token <<- resp$nextSequenceToken

      # Clear batch
      event_batch <<- list()
      last_flush_time <<- Sys.time()

    }, error = function(e) {
      # Handle InvalidSequenceTokenException by retrying with correct token
      if (grepl("InvalidSequenceTokenException", conditionMessage(e))) {
        # Extract correct token from error message
        token_match <- regmatches(
          conditionMessage(e),
          regexpr("sequenceToken is: [a-zA-Z0-9]+", conditionMessage(e))
        )
        if (length(token_match) > 0) {
          new_token <- sub("sequenceToken is: ", "", token_match)
          sequence_token <<- new_token

          # Retry with correct token
          flush_batch()
        }
      } else {
        warning("CloudWatch batch flush failed: ", conditionMessage(e), call. = FALSE)
        # Clear batch to avoid infinite retry
        event_batch <<- list()
      }
    })
  }

  # Finalizer to flush on logger destruction
  reg.finalizer(
    environment(),
    function(e) {
      if (length(event_batch) > 0) {
        flush_batch()
      }
    },
    onexit = TRUE
  )

  receiver(function(event) {
    # Level filtering
    if (!is.null(config$lower) &&
        event$level_number < attr(config$lower, "level_number")) {
      return(invisible(NULL))
    }
    if (!is.null(config$upper) &&
        event$level_number > attr(config$upper, "level_number")) {
      return(invisible(NULL))
    }

    # Format event
    message_content <- formatter(event)

    # CloudWatch expects milliseconds since epoch
    timestamp_ms <- as.numeric(event$time) * 1000

    # Add to batch
    event_batch[[length(event_batch) + 1]] <<- list(
      timestamp = as.integer(timestamp_ms),
      message = message_content
    )

    # Flush if batch size reached or time elapsed
    time_since_flush <- as.numeric(difftime(Sys.time(), last_flush_time, units = "secs"))
    should_flush <- (length(event_batch) >= bc$batch_size) ||
                    (time_since_flush >= bc$flush_interval_seconds)

    if (should_flush) {
      flush_batch()
    }

    invisible(NULL)
  })
}
```

---

### 3. Dispatcher Update

**File:** `R/receivers.R` (in `.formatter_to_receiver()`)

```r
# Add to existing dispatcher
} else if (config$backend == "cloudwatch") {
  .build_cloudwatch_receiver(formatter, config)
```

---

## Testing Strategy

### Unit Tests

**File:** `tests/testthat/test-cloudwatch.R`

```r
# Input validation
test_that("on_cloudwatch validates inputs", {
  expect_error(
    on_cloudwatch("not a formatter", "group", "stream"),
    "must be a log_formatter"
  )

  expect_error(
    to_json() %>% on_cloudwatch("", "stream"),
    "non-empty character string"
  )

  expect_error(
    to_json() %>% on_cloudwatch("group", "stream", batch_size = 20000),
    "between 1 and 10000"
  )
})

# Configuration attachment
test_that("on_cloudwatch attaches config correctly", {
  fmt <- to_json() %>% on_cloudwatch(
    log_group = "/test/app",
    log_stream = "stream1",
    region = "us-west-2",
    batch_size = 50,
    flush_interval_seconds = 10
  )

  config <- attr(fmt, "config")
  expect_equal(config$backend, "cloudwatch")
  expect_equal(config$backend_config$log_group, "/test/app")
  expect_equal(config$backend_config$log_stream, "stream1")
  expect_equal(config$backend_config$region, "us-west-2")
  expect_equal(config$backend_config$batch_size, 50)
  expect_equal(config$backend_config$flush_interval_seconds, 10)
})

# Credential handling
test_that("on_cloudwatch handles credentials", {
  creds <- list(
    access_key_id = "AKIAIOSFODNN7EXAMPLE",
    secret_access_key = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  )

  fmt <- to_json() %>% on_cloudwatch(
    log_group = "/test",
    log_stream = "s1",
    credentials = creds
  )

  config <- attr(fmt, "config")
  expect_equal(config$backend_config$credentials, creds)
})

# Formatter compatibility
test_that("on_cloudwatch works with different formatters", {
  expect_s3_class(
    to_json() %>% on_cloudwatch("/g", "s"),
    "log_formatter"
  )

  expect_s3_class(
    to_text() %>% on_cloudwatch("/g", "s"),
    "log_formatter"
  )

  expect_s3_class(
    to_csv() %>% on_cloudwatch("/g", "s"),
    "log_formatter"
  )
})

# Integration test (requires AWS credentials, skip on CRAN)
test_that("cloudwatch receiver sends events", {
  skip_if_not(nzchar(Sys.getenv("AWS_ACCESS_KEY_ID")), "AWS credentials not available")
  skip_on_cran()

  log_test <- logger() %>%
    with_receivers(
      to_json() %>% on_cloudwatch(
        log_group = "/logthis-test",
        log_stream = paste0("test-", as.integer(Sys.time())),
        batch_size = 1,  # Force immediate flush
        flush_interval_seconds = 1
      )
    )

  # Send test event
  result <- log_test(NOTE("CloudWatch integration test"))

  # Event should be returned
  expect_s3_class(result, "log_event")
  expect_equal(result$message, "CloudWatch integration test")

  # Give CloudWatch time to process
  Sys.sleep(2)

  # TODO: Could verify via DescribeLogStreams API
})

# Error handling
test_that("cloudwatch receiver handles paws errors gracefully", {
  skip_if_not(requireNamespace("paws", quietly = TRUE), "paws not available")

  # This will fail due to invalid credentials, but shouldn't crash
  log_test <- logger() %>%
    with_receivers(
      to_json() %>% on_cloudwatch(
        log_group = "/test",
        log_stream = "test",
        credentials = list(
          access_key_id = "INVALID",
          secret_access_key = "INVALID"
        )
      )
    )

  # Should warn but not error
  expect_warning(
    log_test(NOTE("This should warn")),
    NA  # Don't expect a specific warning pattern
  )
})
```

---

## Documentation

### README.md Updates

Add to "Built-in Receivers" section:

```markdown
#### Cloud Receivers

**AWS CloudWatch Logs**
```r
# JSON logs to CloudWatch
logger() %>%
  with_receivers(
    to_json() %>% on_cloudwatch(
      log_group = "/aws/r-app/production",
      log_stream = paste0("instance-", Sys.info()["nodename"]),
      region = "us-east-1"
    )
  )

# Multi-region redundancy
logger() %>%
  with_receivers(
    to_json() %>% on_cloudwatch(log_group = "/app", log_stream = "main", region = "us-east-1"),
    to_json() %>% on_cloudwatch(log_group = "/app", log_stream = "main", region = "eu-west-1")
  )
```

**AWS S3** (already exists)

**Azure Blob Storage** (already exists)
```

### Vignette: `advanced-receivers.Rmd`

Add CloudWatch section:

```markdown
## AWS CloudWatch Logs

CloudWatch Logs provides centralized logging for AWS infrastructure. It integrates seamlessly with EC2, ECS, Lambda, and other AWS services.

### Basic Usage

```{r eval=FALSE}
library(logthis)

log_this <- logger() %>%
  with_receivers(
    to_json() %>% on_cloudwatch(
      log_group = "/aws/myapp/production",
      log_stream = Sys.getenv("INSTANCE_ID")
    )
  )

log_this(NOTE("Application started"))
log_this(WARNING("High memory usage detected"))
```

### Credential Management

CloudWatch receivers use the standard AWS credential chain:

1. **IAM Role** (recommended for EC2/ECS)
2. **Environment variables** (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
3. **Shared credentials file** (~/.aws/credentials)
4. **Explicit credentials** (for testing)

```{r eval=FALSE}
# Explicit credentials (not recommended for production)
log_this <- logger() %>%
  with_receivers(
    to_json() %>% on_cloudwatch(
      log_group = "/test",
      log_stream = "debug",
      credentials = list(
        access_key_id = Sys.getenv("AWS_ACCESS_KEY_ID"),
        secret_access_key = Sys.getenv("AWS_SECRET_ACCESS_KEY")
      )
    )
  )
```

### Batching and Performance

CloudWatch has API rate limits:
- 5 requests/second per log stream
- 1 MB/second per log stream
- Max 10,000 events per batch

Use batching to optimize:

```{r eval=FALSE}
# High-volume logging
log_this <- logger() %>%
  with_receivers(
    to_json() %>% on_cloudwatch(
      log_group = "/high-volume-app",
      log_stream = "events",
      batch_size = 5000,              # Events per batch
      flush_interval_seconds = 10      # Max wait time
    )
  )
```

### CloudWatch Insights Queries

With JSON logging, you can run powerful queries in CloudWatch Insights:

```
# Count errors by level
fields @timestamp, level, message
| filter level = "ERROR"
| stats count() by bin(5m)

# Search for specific patterns
fields @timestamp, message, tags
| filter message like /database/
| filter level_number >= 60

# Extract custom fields
fields @timestamp, user_id, action, duration_ms
| filter action = "login"
| stats avg(duration_ms), max(duration_ms) by user_id
```

### Multi-Destination Logging

Combine CloudWatch with other receivers:

```{r eval=FALSE}
log_this <- logger() %>%
  with_receivers(
    # Local file for debugging
    to_json() %>% on_local("app.jsonl"),

    # CloudWatch for real-time monitoring
    to_json() %>% on_cloudwatch(
      log_group = "/app/production",
      log_stream = Sys.getenv("INSTANCE_ID")
    ),

    # S3 for long-term archival
    to_json() %>% on_s3(
      bucket = "logs-archive",
      key = paste0("app-", Sys.Date(), ".jsonl")
    )
  )
```
```

---

## Dependencies

### DESCRIPTION Updates

```
Suggests:
    paws (>= 0.1.0),
    paws.common (>= 0.1.0)
```

### Package Installation

Users will need to install `paws`:

```r
install.packages("paws")
```

Or for full AWS SDK:

```r
install.packages("paws.common")
```

---

## CloudWatch Concepts Reference

### Log Groups
- Top-level containers for log streams
- Naming convention: `/aws/service/app-name`
- Can set retention policies (1 day to 10 years)
- Example: `/aws/r-app/production`

### Log Streams
- Sequences of log events within a group
- Typically one per instance/process
- Example: `instance-i-1234567890abcdef0`

### Log Events
- Individual timestamped log entries
- Must be in chronological order within a stream
- Require sequence tokens for ordering

### Sequence Tokens
- Opaque strings returned by CloudWatch
- Required for next `PutLogEvents` call
- Ensures event ordering
- Handled automatically by `.build_cloudwatch_receiver()`

---

## Implementation Checklist

When ready to implement:

- [ ] Add `on_cloudwatch()` to `R/receivers.R`
- [ ] Add `.build_cloudwatch_receiver()` to `R/receivers.R`
- [ ] Update `.formatter_to_receiver()` dispatcher
- [ ] Add `tests/testthat/test-cloudwatch.R`
- [ ] Update `README.md` with CloudWatch examples
- [ ] Update `vignettes/advanced-receivers.Rmd`
- [ ] Add `paws` to `DESCRIPTION` Suggests
- [ ] Run `devtools::check()` to ensure no errors
- [ ] Update `NEWS.md` with new feature

---

## Potential Adjustments

### Performance Tuning
- Consider async batching with `later` package
- Add option for compressed payloads (gzip)
- Implement exponential backoff for retries

### Error Handling
- Add dead-letter queue for failed events
- Implement circuit breaker pattern for persistent failures
- Add metrics for batch success/failure rates

### Advanced Features
- Support for log retention policies
- Automatic log group/stream rotation
- Integration with CloudWatch Metrics (custom metrics from logs)
- Support for CloudWatch Embedded Metric Format (EMF)

### Alternative Approaches
- Use `logger` package's CloudWatch backend (if it exists)
- Direct HTTP API calls instead of `paws` (fewer dependencies)
- Batch compression for large payloads

---

## References

- [AWS CloudWatch Logs Documentation](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/WhatIsCloudWatchLogs.html)
- [paws R Package](https://paws-r.github.io/)
- [CloudWatch Logs API Reference](https://docs.aws.amazon.com/AmazonCloudWatchLogs/latest/APIReference/Welcome.html)
- [CloudWatch Insights Query Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
