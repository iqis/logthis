# Timing and Performance Middleware
#
# Demonstrates how to automatically calculate durations, track performance
# metrics, and add timing information to log events.

library(logthis)

# ==============================================================================
# Example 1: Basic Duration Calculation
# ==============================================================================

#' Calculate duration from start_time field
#'
#' If an event has a start_time field, calculates the elapsed time and adds
#' duration_ms field. Removes start_time from output to avoid clutter.
#'
#' @return middleware function
add_duration <- middleware(function(event) {
  if (!is.null(event$start_time)) {
    # Calculate duration in milliseconds
    event$duration_ms <- as.numeric(Sys.time() - event$start_time) * 1000

    # Remove start_time from output (no longer needed)
    event$start_time <- NULL
  }

  event
})

# Usage
log_this <- logger() %>%
  with_middleware(add_duration) %>%
  with_receivers(to_console())

# Time an operation
start_time <- Sys.time()
Sys.sleep(0.5)  # Simulate work
log_this(NOTE("Operation completed", start_time = start_time))
# Output: "duration_ms: 500"

# ==============================================================================
# Example 2: Multiple Timing Fields
# ==============================================================================

#' Calculate multiple durations with custom field names
#'
#' Supports multiple timing pairs: start_time/duration_ms, db_start/db_duration_ms, etc.
#'
#' @param timing_pairs List of pairs: list(c("start_time", "duration_ms"), ...)
#' @return middleware function
add_multiple_durations <- function(timing_pairs = list(c("start_time", "duration_ms"))) {
  middleware(function(event) {
    for (pair in timing_pairs) {
      start_field <- pair[1]
      duration_field <- pair[2]

      if (!is.null(event[[start_field]])) {
        # Calculate duration
        event[[duration_field]] <- as.numeric(Sys.time() - event[[start_field]]) * 1000

        # Remove start time
        event[[start_field]] <- NULL
      }
    }

    event
  })
}

# Usage: Time multiple operations
log_this <- logger() %>%
  with_middleware(
    add_multiple_durations(
      timing_pairs = list(
        c("query_start", "query_duration_ms"),
        c("render_start", "render_duration_ms"),
        c("total_start", "total_duration_ms")
      )
    )
  ) %>%
  with_receivers(to_console())

total_start <- Sys.time()
query_start <- Sys.time()
# ... database query ...
Sys.sleep(0.2)

render_start <- Sys.time()
# ... render results ...
Sys.sleep(0.1)

log_this(NOTE(
  "Request completed",
  query_start = query_start,
  render_start = render_start,
  total_start = total_start
))
# Output: query_duration_ms: 200, render_duration_ms: 100, total_duration_ms: 300

# ==============================================================================
# Example 3: Performance Classification
# ==============================================================================

#' Classify performance as fast/acceptable/slow based on thresholds
#'
#' Adds performance_class field based on duration. Useful for filtering or
#' alerting on slow operations.
#'
#' @param fast_threshold_ms Duration below this is "fast" (default: 100ms)
#' @param slow_threshold_ms Duration above this is "slow" (default: 1000ms)
#' @return middleware function
classify_performance <- function(fast_threshold_ms = 100, slow_threshold_ms = 1000) {
  middleware(function(event) {
    if (!is.null(event$duration_ms)) {
      duration <- event$duration_ms

      if (duration < fast_threshold_ms) {
        event$performance_class <- "fast"
      } else if (duration < slow_threshold_ms) {
        event$performance_class <- "acceptable"
      } else {
        event$performance_class <- "slow"
      }

      # Add threshold context for analysis
      event$performance_thresholds <- paste0(
        "fast<", fast_threshold_ms, "ms, slow>", slow_threshold_ms, "ms"
      )
    }

    event
  })
}

# Usage with duration calculation
log_this <- logger() %>%
  with_middleware(
    add_duration,
    classify_performance(fast_threshold_ms = 50, slow_threshold_ms = 500)
  ) %>%
  with_receivers(to_console())

start_time <- Sys.time()
Sys.sleep(0.7)  # Simulate slow operation
log_this(WARNING("Database query completed", start_time = start_time))
# Output: "duration_ms: 700, performance_class: slow"

# ==============================================================================
# Example 4: Automatic Level Escalation for Slow Operations
# ==============================================================================

#' Escalate log level if operation is slow
#'
#' Automatically upgrades DEBUG/NOTE events to WARNING if duration exceeds
#' threshold. Useful for catching performance regressions.
#'
#' @param threshold_ms Duration threshold in milliseconds
#' @return middleware function
escalate_slow_operations <- function(threshold_ms = 1000) {
  middleware(function(event) {
    if (!is.null(event$duration_ms) && event$duration_ms > threshold_ms) {
      # Escalate low-level events to WARNING
      if (event$level_number < attr(WARNING, "level_number")) {
        original_level <- event$level_class

        event$level_class <- "WARNING"
        event$level_number <- attr(WARNING, "level_number")

        # Add metadata about escalation
        event$escalated_from <- original_level
        event$escalation_reason <- paste0("Slow operation (>", threshold_ms, "ms)")
      }
    }

    event
  })
}

# Usage
log_this <- logger() %>%
  with_middleware(
    add_duration,
    escalate_slow_operations(threshold_ms = 500)
  ) %>%
  with_receivers(to_console())

start_time <- Sys.time()
Sys.sleep(0.8)  # Slow!
log_this(NOTE("Query completed", start_time = start_time))
# Output: Level escalated from NOTE to WARNING due to duration

# ==============================================================================
# Example 5: Rate Limiting and Throttling
# ==============================================================================

#' Add rate limiting metadata
#'
#' Tracks event rate and adds throttling metadata. Useful for detecting
#' runaway loops or excessive logging.
#'
#' @param window_seconds Time window for rate calculation (default: 60)
#' @return middleware function
add_rate_limiting <- function(window_seconds = 60) {
  # Closure state for rate tracking
  event_times <- c()

  middleware(function(event) {
    current_time <- Sys.time()

    # Add current event time
    event_times <<- c(event_times, current_time)

    # Remove events outside window
    cutoff <- current_time - window_seconds
    event_times <<- event_times[event_times > cutoff]

    # Calculate rate
    event$event_rate_per_minute <- (length(event_times) / window_seconds) * 60

    # Flag high rate
    if (event$event_rate_per_minute > 100) {
      event$high_rate_warning <- TRUE
    }

    event
  })
}

# ==============================================================================
# Example 6: Performance Percentiles (Requires History)
# ==============================================================================

#' Add performance percentile information
#'
#' Compares current duration to historical percentiles. Requires maintaining
#' a rolling window of durations.
#'
#' @param window_size Number of events to keep for percentile calculation
#' @return middleware function
add_performance_percentile <- function(window_size = 100) {
  # Closure state for historical durations
  duration_history <- numeric(0)

  middleware(function(event) {
    if (!is.null(event$duration_ms)) {
      # Add current duration to history
      duration_history <<- c(duration_history, event$duration_ms)

      # Keep only most recent window_size events
      if (length(duration_history) > window_size) {
        duration_history <<- tail(duration_history, window_size)
      }

      # Calculate percentiles (if we have enough data)
      if (length(duration_history) >= 10) {
        percentiles <- quantile(
          duration_history,
          probs = c(0.5, 0.95, 0.99),
          na.rm = TRUE
        )

        event$p50_ms <- percentiles[["50%"]]
        event$p95_ms <- percentiles[["95%"]]
        event$p99_ms <- percentiles[["99%"]]

        # Flag if current duration is above p95
        if (event$duration_ms > percentiles[["95%"]]) {
          event$above_p95 <- TRUE
        }
      }
    }

    event
  })
}

# Usage: Track query performance over time
log_this <- logger() %>%
  with_middleware(
    add_duration,
    add_performance_percentile(window_size = 50)
  ) %>%
  with_receivers(to_json() %>% on_local("query_performance.jsonl"))

# ==============================================================================
# Example 7: Database Query Timing Helper
# ==============================================================================

#' Time database queries with automatic metadata
#'
#' Helper function that times a query and logs with all timing metadata.
#'
#' @param log_fn Logger function
#' @param query SQL query string
#' @param query_fn Function that executes the query
#' @return Query result
time_query <- function(log_fn, query, query_fn) {
  start_time <- Sys.time()

  # Execute query
  result <- tryCatch({
    query_fn()
  }, error = function(e) {
    # Log error with timing
    log_fn(ERROR(
      "Query failed",
      query = query,
      error = conditionMessage(e),
      start_time = start_time
    ))
    stop(e)
  })

  # Log success with timing
  log_fn(DEBUG(
    "Query completed",
    query = query,
    rows_returned = nrow(result),
    start_time = start_time
  ))

  result
}

# Usage
log_this <- logger() %>%
  with_middleware(
    add_duration,
    classify_performance(slow_threshold_ms = 500)
  ) %>%
  with_receivers(to_console())

result <- time_query(
  log_fn = log_this,
  query = "SELECT * FROM patients WHERE study_id = 'TRIAL-001'",
  query_fn = function() {
    # Simulate database query
    Sys.sleep(0.3)
    data.frame(patient_id = 1:10)
  }
)
# Output: Includes duration_ms and performance_class

# ==============================================================================
# Example 8: Comprehensive Performance Monitoring
# ==============================================================================

#' Production-ready performance monitoring middleware stack
#'
#' Combines timing, classification, escalation, and percentile tracking.
#'
#' @param fast_threshold_ms Fast operation threshold
#' @param slow_threshold_ms Slow operation threshold
#' @param escalate_threshold_ms Auto-escalate to WARNING above this
#' @param percentile_window Number of events for percentile calculation
#' @return Middleware function
create_performance_middleware <- function(fast_threshold_ms = 100,
                                         slow_threshold_ms = 1000,
                                         escalate_threshold_ms = 2000,
                                         percentile_window = 100) {
  # Bundle all timing middleware
  list(
    add_duration,
    classify_performance(fast_threshold_ms, slow_threshold_ms),
    escalate_slow_operations(escalate_threshold_ms),
    add_performance_percentile(percentile_window)
  )
}

# Usage: API endpoint timing
log_this <- logger() %>%
  with_middleware(
    create_performance_middleware(
      fast_threshold_ms = 50,
      slow_threshold_ms = 500,
      escalate_threshold_ms = 1000,
      percentile_window = 200
    )
  ) %>%
  with_receivers(
    to_console(lower = WARNING),  # Only slow operations to console
    to_json() %>% on_local("api_performance.jsonl")  # All to file
  )

# ==============================================================================
# Example 9: Pharmaceutical/Clinical Timing
# ==============================================================================

#' GxP-compliant operation timing
#'
#' For pharmaceutical and clinical systems requiring audit of operation
#' durations (e.g., sample processing time, analysis duration).
#'
#' @return middleware function
add_gxp_timing <- middleware(function(event) {
  if (!is.null(event$start_time)) {
    # Calculate duration
    duration_sec <- as.numeric(Sys.time() - event$start_time)
    event$duration_seconds <- round(duration_sec, 3)  # 3 decimal places for audit

    # ISO 8601 timestamps for regulatory compliance
    event$start_timestamp_iso <- format(event$start_time, "%Y-%m-%dT%H:%M:%S%z")
    event$end_timestamp_iso <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")

    # Remove internal start_time
    event$start_time <- NULL

    # Flag long operations (e.g., > 1 hour may need investigation)
    if (duration_sec > 3600) {
      event$long_operation_flag <- TRUE
      event$duration_hours <- round(duration_sec / 3600, 2)
    }
  }

  event
})

# Usage: Clinical sample processing
log_clinical <- logger() %>%
  with_middleware(add_gxp_timing) %>%
  with_tags("GxP", "timing_audit") %>%
  with_receivers(
    to_json() %>% on_local("gxp_timing.jsonl")
  )

start_time <- Sys.time()
# ... sample analysis ...
Sys.sleep(2)
log_clinical(NOTE(
  "Sample analysis completed",
  sample_id = "SMP-001",
  assay_type = "HPLC",
  start_time = start_time
))
# Output: duration_seconds, start_timestamp_iso, end_timestamp_iso for audit
