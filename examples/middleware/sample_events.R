# Event Sampling Middleware
#
# Demonstrates how to drop events based on sampling rules to reduce log volume
# while maintaining visibility. Critical for high-throughput systems.

library(logthis)

# ==============================================================================
# Example 1: Basic Percentage Sampling
# ==============================================================================

#' Sample events by percentage (keep only X%)
#'
#' Randomly drops events based on sampling rate. Useful for reducing volume
#' of high-frequency DEBUG logs in production.
#'
#' @param sample_rate Proportion of events to keep (0 to 1)
#' @return middleware function
sample_by_percentage <- function(sample_rate = 0.1) {
  if (sample_rate < 0 || sample_rate > 1) {
    stop("`sample_rate` must be between 0 and 1")
  }

  middleware(function(event) {
    if (runif(1) > sample_rate) {
      # Drop event (return NULL short-circuits processing)
      return(NULL)
    }

    # Keep event
    event$sampled <- TRUE
    event$sample_rate <- sample_rate
    event
  })
}

# Usage: Keep only 10% of events
log_this <- logger() %>%
  with_middleware(sample_by_percentage(sample_rate = 0.1)) %>%
  with_receivers(to_console())

for (i in 1:100) {
  log_this(DEBUG(paste("Event", i)))
}
# Output: ~10 events (instead of 100)

# ==============================================================================
# Example 2: Level-Based Sampling
# ==============================================================================

#' Sample events differently based on level
#'
#' Keeps all ERROR/WARNING, samples INFO/DEBUG. Ensures critical events are
#' never dropped while reducing noise.
#'
#' @param debug_rate Sampling rate for DEBUG (default: 0.01 = 1%)
#' @param note_rate Sampling rate for NOTE (default: 0.1 = 10%)
#' @param message_rate Sampling rate for MESSAGE (default: 0.5 = 50%)
#' @return middleware function
sample_by_level <- function(debug_rate = 0.01, note_rate = 0.1, message_rate = 0.5) {
  middleware(function(event) {
    level <- event$level_class

    # Never drop warnings or errors
    if (level %in% c("WARNING", "ERROR", "CRITICAL")) {
      event$sampled <- FALSE  # Mark as not sampled (kept intentionally)
      return(event)
    }

    # Sample DEBUG aggressively
    if (level == "DEBUG" && runif(1) > debug_rate) {
      return(NULL)
    }

    # Sample NOTE moderately
    if (level == "NOTE" && runif(1) > note_rate) {
      return(NULL)
    }

    # Sample MESSAGE lightly
    if (level == "MESSAGE" && runif(1) > message_rate) {
      return(NULL)
    }

    # Keep event
    event$sampled <- TRUE
    event
  })
}

# Usage
log_this <- logger() %>%
  with_middleware(
    sample_by_level(debug_rate = 0.05, note_rate = 0.2, message_rate = 0.8)
  ) %>%
  with_receivers(to_console())

log_this(DEBUG("Verbose debug info"))  # 5% chance of keeping
log_this(NOTE("Regular note"))         # 20% chance
log_this(WARNING("Important warning")) # Always kept
log_this(ERROR("Critical error"))      # Always kept

# ==============================================================================
# Example 3: Time-Based Sampling (Burst Protection)
# ==============================================================================

#' Rate limit events to N per second
#'
#' Prevents log flooding by dropping events that exceed rate limit. Uses
#' token bucket algorithm for smooth rate limiting.
#'
#' @param max_events_per_second Maximum events to allow per second
#' @return middleware function
rate_limit_events <- function(max_events_per_second = 10) {
  # Token bucket state
  tokens <- max_events_per_second
  last_refill <- Sys.time()

  middleware(function(event) {
    current_time <- Sys.time()

    # Refill tokens based on time elapsed
    time_elapsed <- as.numeric(current_time - last_refill)
    tokens_to_add <- time_elapsed * max_events_per_second
    tokens <<- min(tokens + tokens_to_add, max_events_per_second)
    last_refill <<- current_time

    # Check if we have tokens available
    if (tokens < 1) {
      # No tokens, drop event
      return(NULL)
    }

    # Consume token
    tokens <<- tokens - 1

    event$rate_limited <- FALSE
    event
  })
}

# Usage: Prevent log flooding
log_this <- logger() %>%
  with_middleware(rate_limit_events(max_events_per_second = 5)) %>%
  with_receivers(to_console())

# Burst of 100 events
for (i in 1:100) {
  log_this(NOTE(paste("Burst event", i)))
  Sys.sleep(0.01)  # 100 events/second attempted
}
# Output: Only ~5 events per second kept

# ==============================================================================
# Example 4: Content-Based Sampling
# ==============================================================================

#' Sample events based on message content
#'
#' Uses hash of message to deterministically sample. Same message always has
#' same sampling decision (useful for aggregating identical events).
#'
#' @param sample_rate Sampling rate (0 to 1)
#' @return middleware function
sample_by_hash <- function(sample_rate = 0.1) {
  threshold <- as.integer(sample_rate * 2^31)

  middleware(function(event) {
    # Hash message (deterministic)
    msg_hash <- digest::digest(event$message, algo = "crc32")
    hash_int <- strtoi(paste0("0x", msg_hash))

    # Sample based on hash
    if (hash_int %% 2^31 > threshold) {
      return(NULL)
    }

    event$sampled_by_hash <- TRUE
    event
  })
}

# ==============================================================================
# Example 5: Adaptive Sampling (Volume-Based)
# ==============================================================================

#' Adaptively sample based on event volume
#'
#' Automatically adjusts sampling rate based on event frequency. When volume
#' is low, keeps all events. When volume is high, samples aggressively.
#'
#' @param target_events_per_minute Target event rate
#' @param window_seconds Window for measuring rate
#' @return middleware function
adaptive_sampling <- function(target_events_per_minute = 60, window_seconds = 60) {
  # State tracking
  event_times <- c()
  current_sample_rate <- 1.0

  middleware(function(event) {
    current_time <- Sys.time()

    # Track event times
    event_times <<- c(event_times, current_time)

    # Clean old events outside window
    cutoff <- current_time - window_seconds
    event_times <<- event_times[event_times > cutoff]

    # Calculate current rate
    events_per_minute <- (length(event_times) / window_seconds) * 60

    # Adjust sampling rate
    if (events_per_minute > target_events_per_minute) {
      current_sample_rate <<- target_events_per_minute / events_per_minute
    } else {
      current_sample_rate <<- 1.0
    }

    # Apply sampling
    if (runif(1) > current_sample_rate) {
      return(NULL)
    }

    event$adaptive_sample_rate <- current_sample_rate
    event$current_rate_per_minute <- events_per_minute
    event
  })
}

# ==============================================================================
# Example 6: Tag-Based Sampling
# ==============================================================================

#' Sample events based on tags
#'
#' Different sampling rates for different tagged categories. Useful for
#' multi-component systems.
#'
#' @param tag_rates Named list of tag:rate pairs
#' @param default_rate Default rate for untagged events
#' @return middleware function
sample_by_tags <- function(tag_rates = list(), default_rate = 1.0) {
  middleware(function(event) {
    sample_rate <- default_rate

    # Check if event has tags that match our rules
    if (!is.null(event$tags)) {
      for (tag in event$tags) {
        if (tag %in% names(tag_rates)) {
          # Use most restrictive (lowest) rate
          sample_rate <- min(sample_rate, tag_rates[[tag]])
        }
      }
    }

    # Apply sampling
    if (runif(1) > sample_rate) {
      return(NULL)
    }

    event$tag_sample_rate <- sample_rate
    event
  })
}

# Usage: Different rates for different components
log_this <- logger() %>%
  with_middleware(
    sample_by_tags(
      tag_rates = list(
        "database" = 0.1,    # Sample DB logs at 10%
        "ui" = 0.01,         # Sample UI logs at 1%
        "api" = 0.5,         # Sample API logs at 50%
        "security" = 1.0     # Keep all security logs
      ),
      default_rate = 0.1
    )
  ) %>%
  with_receivers(to_console())

log_this(DEBUG("UI click event") %>% with_tags("ui"))
# 1% kept

log_this(WARNING("Failed login") %>% with_tags("security"))
# Always kept

# ==============================================================================
# Example 7: First-N-Per-Key Sampling
# ==============================================================================

#' Keep only first N events per key
#'
#' For debugging repetitive events. Keeps first N occurrences of each unique
#' message/key, then drops the rest.
#'
#' @param n Number of events to keep per key
#' @param key_field Field to use as key (default: "message")
#' @return middleware function
first_n_per_key <- function(n = 3, key_field = "message") {
  # Track counts per key
  key_counts <- new.env(hash = TRUE)

  middleware(function(event) {
    key_value <- as.character(event[[key_field]] %||% "unknown")

    # Get current count for this key
    count <- key_counts[[key_value]] %||% 0

    if (count >= n) {
      # Already logged N times, drop
      return(NULL)
    }

    # Increment count
    key_counts[[key_value]] <- count + 1

    event$occurrence_number <- count + 1
    event
  })
}

# Usage: Log each unique error only 3 times
log_this <- logger() %>%
  with_middleware(first_n_per_key(n = 3, key_field = "error_type")) %>%
  with_receivers(to_console())

for (i in 1:10) {
  log_this(ERROR("Database connection failed", error_type = "connection_error"))
}
# Output: Only first 3 occurrences logged

# ==============================================================================
# Example 8: Composite Sampling Strategy
# ==============================================================================

#' Production-ready sampling strategy
#'
#' Combines level-based, rate limiting, and adaptive sampling for robust
#' log volume control.
#'
#' @return List of middleware functions
create_production_sampling <- function() {
  list(
    # 1. Never drop errors/warnings
    # 2. Sample DEBUG aggressively (1%)
    sample_by_level(debug_rate = 0.01, note_rate = 0.1, message_rate = 1.0),

    # 3. Rate limit to prevent bursts (max 100/sec)
    rate_limit_events(max_events_per_second = 100),

    # 4. Adaptive sampling to target 1000 events/min
    adaptive_sampling(target_events_per_minute = 1000)
  )
}

# Usage
log_this <- logger() %>%
  with_middleware(create_production_sampling()) %>%
  with_receivers(
    to_console(lower = WARNING),
    to_json() %>% on_local("app.jsonl")
  )

# ==============================================================================
# Example 9: Sampling with Dropped Event Tracking
# ==============================================================================

#' Sample events but track drop statistics
#'
#' Samples events while maintaining counters of dropped events. Periodically
#' logs summary of dropped events.
#'
#' @param sample_rate Sampling rate
#' @param report_interval_seconds How often to report drop stats
#' @return middleware function
sample_with_tracking <- function(sample_rate = 0.1, report_interval_seconds = 60) {
  # State tracking
  total_events <- 0
  dropped_events <- 0
  last_report <- Sys.time()

  middleware(function(event) {
    total_events <<- total_events + 1

    # Check if we should report
    current_time <- Sys.time()
    if (as.numeric(current_time - last_report) >= report_interval_seconds) {
      # Create summary event (always kept)
      summary_event <- NOTE(
        "Sampling summary",
        total_events = total_events,
        dropped_events = dropped_events,
        kept_events = total_events - dropped_events,
        sample_rate = sample_rate,
        drop_percentage = round((dropped_events / total_events) * 100, 2)
      )

      # Reset counters
      total_events <<- 0
      dropped_events <<- 0
      last_report <<- current_time

      # Return summary instead of original event
      return(summary_event)
    }

    # Apply sampling
    if (runif(1) > sample_rate) {
      dropped_events <<- dropped_events + 1
      return(NULL)
    }

    event$sampled <- TRUE
    event
  })
}

# ==============================================================================
# Example 10: Pharmaceutical/Clinical Sampling (Audit-Safe)
# ==============================================================================

#' GxP-compliant event sampling
#'
#' For pharmaceutical and clinical systems. NEVER drops audit-critical events
#' (GxP, security, regulatory tags). Samples only non-critical debugging events.
#'
#' @param debug_sample_rate Sampling rate for debug events (default: 0.05)
#' @return middleware function
sample_gxp_safe <- function(debug_sample_rate = 0.05) {
  middleware(function(event) {
    # NEVER drop audit-critical tags
    critical_tags <- c("GxP", "audit_trail", "21CFR11", "security", "regulatory")

    if (!is.null(event$tags)) {
      for (tag in event$tags) {
        if (tag %in% critical_tags) {
          # Mark as audit-critical, never drop
          event$audit_critical <- TRUE
          return(event)
        }
      }
    }

    # NEVER drop warnings or errors
    if (event$level_number >= attr(WARNING, "level_number")) {
      return(event)
    }

    # Sample DEBUG/NOTE events only
    if (event$level_class %in% c("DEBUG", "TRACE")) {
      if (runif(1) > debug_sample_rate) {
        return(NULL)
      }
    }

    event$sampled <- TRUE
    event
  })
}

# Usage: Clinical trial logging
log_clinical <- logger() %>%
  with_middleware(sample_gxp_safe(debug_sample_rate = 0.1)) %>%
  with_receivers(
    to_json() %>% on_local("clinical_audit.jsonl")
  )

log_clinical(DEBUG("Cache hit") %>% with_tags("performance"))
# 10% sampled

log_clinical(NOTE("Data export") %>% with_tags("GxP", "audit_trail"))
# ALWAYS kept (audit-critical)

log_clinical(ERROR("Validation failed") %>% with_tags("quality_control"))
# ALWAYS kept (error level)
