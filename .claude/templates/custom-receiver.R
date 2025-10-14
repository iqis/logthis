# Template: Custom Receiver (Standalone)
# Purpose: Create complete receiver without formatter/handler pattern
# Use when: Simple, self-contained receivers that don't need format/backend separation

# ============================================================================
# Basic Structure
# ============================================================================

# Step 1: Define receiver constructor function
to_MYRECEIVER <- function(option1 = "default",
                          option2 = TRUE,
                          lower = LOWEST,
                          upper = HIGHEST) {

  # Step 2: Create receiver closure
  # The closure receives log_event and performs side effects
  recv <- receiver(function(event) {

    # Step 3: Apply level filtering
    if (event$level_number < as.numeric(lower) ||
        event$level_number > as.numeric(upper)) {
      return(invisible(NULL))
    }

    # Step 4: Extract event fields
    time <- event$time
    level <- event$level_class
    level_number <- event$level_number
    message <- event$message
    tags <- event$tags

    # Custom fields
    custom_fields <- setdiff(names(event),
                             c("time", "level_class", "level_number",
                               "message", "tags"))

    # Step 5: Perform side effect (write, send, etc.)
    # This is where your receiver does its work
    # Examples: write to file, send HTTP request, update database, etc.

    # Placeholder
    cat(sprintf("[%s] %s: %s\n", time, level, message))

    # Step 6: Return NULL invisibly
    invisible(NULL)
  })

  # Step 7: Store limits as attributes
  attr(recv, "lower") <- lower
  attr(recv, "upper") <- upper

  # Optional: Store other config
  attr(recv, "config") <- list(
    option1 = option1,
    option2 = option2
  )

  # Step 8: Return receiver
  # Auto-inherits 'log_receiver' class from receiver()
  recv
}

# ============================================================================
# Example: Email Receiver
# ============================================================================

to_email <- function(to,
                     from = "noreply@example.com",
                     subject_template = "[{level}] Log Alert",
                     smtp_server = "localhost",
                     smtp_port = 25,
                     lower = WARNING,   # Default: only WARNING+ via email
                     upper = HIGHEST) {

  recv <- receiver(function(event) {
    # Level filtering
    if (event$level_number < as.numeric(lower) ||
        event$level_number > as.numeric(upper)) {
      return(invisible(NULL))
    }

    # Build subject
    subject <- glue::glue(subject_template,
                          .envir = list2env(list(
                            level = event$level_class,
                            level_number = event$level_number,
                            message = event$message
                          )))

    # Build body
    body <- sprintf(
      "Time: %s\nLevel: %s (%d)\nMessage: %s\n\n",
      event$time,
      event$level_class,
      event$level_number,
      event$message
    )

    # Add custom fields
    custom_fields <- setdiff(names(event),
                             c("time", "level_class", "level_number",
                               "message", "tags"))
    if (length(custom_fields) > 0) {
      body <- paste0(body, "Additional Fields:\n")
      for (field in custom_fields) {
        body <- paste0(body, sprintf("  %s: %s\n", field, event[[field]]))
      }
    }

    # Send email
    tryCatch({
      # Using mailR or similar package
      # mailR::send.mail(
      #   from = from,
      #   to = to,
      #   subject = subject,
      #   body = body,
      #   smtp = list(host.name = smtp_server, port = smtp_port)
      # )

      # Placeholder
      message(sprintf("EMAIL TO %s: %s", to, subject))

    }, error = function(e) {
      stop("Email send failed: ", e$message)
    })

    invisible(NULL)
  })

  attr(recv, "lower") <- lower
  attr(recv, "upper") <- upper
  attr(recv, "config") <- list(
    to = to,
    from = from,
    smtp_server = smtp_server,
    smtp_port = smtp_port
  )

  recv
}

# ============================================================================
# Example: Slack Receiver
# ============================================================================

to_slack <- function(webhook_url,
                     channel = NULL,
                     username = "LogBot",
                     icon_emoji = ":robot_face:",
                     lower = WARNING,
                     upper = HIGHEST) {

  recv <- receiver(function(event) {
    # Level filtering
    if (event$level_number < as.numeric(lower) ||
        event$level_number > as.numeric(upper)) {
      return(invisible(NULL))
    }

    # Choose color based on level
    color <- if (event$level_number >= 90) {
      "#FF0000"  # Red for CRITICAL
    } else if (event$level_number >= 80) {
      "#FFA500"  # Orange for ERROR
    } else if (event$level_number >= 60) {
      "#FFFF00"  # Yellow for WARNING
    } else {
      "#0000FF"  # Blue for info
    }

    # Build Slack message
    payload <- list(
      username = username,
      icon_emoji = icon_emoji,
      attachments = list(
        list(
          color = color,
          title = sprintf("[%s] %s", event$level_class, event$message),
          fields = list(
            list(title = "Time", value = as.character(event$time), short = TRUE),
            list(title = "Level", value = sprintf("%s (%d)",
                                                   event$level_class,
                                                   event$level_number),
                 short = TRUE)
          ),
          footer = "logthis",
          ts = as.numeric(event$time)
        )
      )
    )

    # Add channel if specified
    if (!is.null(channel)) {
      payload$channel <- channel
    }

    # Send to Slack
    tryCatch({
      httr::POST(webhook_url,
                 body = jsonlite::toJSON(payload, auto_unbox = TRUE),
                 httr::content_type_json())
    }, error = function(e) {
      stop("Slack webhook failed: ", e$message)
    })

    invisible(NULL)
  })

  attr(recv, "lower") <- lower
  attr(recv, "upper") <- upper
  attr(recv, "config") <- list(
    webhook_url = webhook_url,
    channel = channel,
    username = username
  )

  recv
}

# ============================================================================
# Example: Buffered File Receiver
# ============================================================================

to_buffered_file <- function(path,
                             buffer_size = 100,
                             flush_interval_secs = 60,
                             lower = LOWEST,
                             upper = HIGHEST) {

  # Create buffer in closure environment
  buffer <- character()
  last_flush <- Sys.time()

  # Flush function
  flush_buffer <- function() {
    if (length(buffer) > 0) {
      cat(paste(buffer, collapse = "\n"),
          file = path,
          append = TRUE)
      cat("\n", file = path, append = TRUE)
      buffer <<- character()
      last_flush <<- Sys.time()
    }
  }

  recv <- receiver(function(event) {
    # Level filtering
    if (event$level_number < as.numeric(lower) ||
        event$level_number > as.numeric(upper)) {
      return(invisible(NULL))
    }

    # Format event
    formatted <- sprintf("%s [%s] %s",
                         event$time,
                         event$level_class,
                         event$message)

    # Add to buffer
    buffer <<- c(buffer, formatted)

    # Flush if buffer full or interval exceeded
    if (length(buffer) >= buffer_size ||
        difftime(Sys.time(), last_flush, units = "secs") >= flush_interval_secs) {
      flush_buffer()
    }

    invisible(NULL)
  })

  attr(recv, "lower") <- lower
  attr(recv, "upper") <- upper
  attr(recv, "config") <- list(
    path = path,
    buffer_size = buffer_size,
    flush_interval_secs = flush_interval_secs
  )

  # Add flush method for manual flushing
  attr(recv, "flush") <- flush_buffer

  recv
}

# ============================================================================
# Example: System Command Receiver
# ============================================================================

to_system <- function(command_template,
                      shell = "/bin/sh",
                      lower = LOWEST,
                      upper = HIGHEST) {

  recv <- receiver(function(event) {
    # Level filtering
    if (event$level_number < as.numeric(lower) ||
        event$level_number > as.numeric(upper)) {
      return(invisible(NULL))
    }

    # Build data for template
    data <- list(
      time = as.character(event$time),
      level = event$level_class,
      level_number = event$level_number,
      message = event$message
    )

    # Add custom fields
    custom_fields <- setdiff(names(event),
                             c("time", "level_class", "level_number",
                               "message", "tags"))
    for (field in custom_fields) {
      data[[field]] <- event[[field]]
    }

    # Expand template
    command <- glue::glue(command_template,
                          .envir = list2env(data, parent = emptyenv()))

    # Execute command
    tryCatch({
      system2(shell, args = c("-c", command), stdout = TRUE, stderr = TRUE)
    }, error = function(e) {
      stop("System command failed: ", e$message)
    })

    invisible(NULL)
  })

  attr(recv, "lower") <- lower
  attr(recv, "upper") <- upper
  attr(recv, "config") <- list(
    command_template = command_template,
    shell = shell
  )

  recv
}

# ============================================================================
# Example: Conditional Receiver (Wrapper)
# ============================================================================

to_conditional <- function(base_receiver,
                          condition_func) {

  if (!inherits(base_receiver, "log_receiver")) {
    stop("base_receiver must be a log_receiver")
  }

  recv <- receiver(function(event) {
    # Check condition
    if (condition_func(event)) {
      # Pass to base receiver
      base_receiver(event)
    }

    invisible(NULL)
  })

  # Copy attributes from base receiver
  attr(recv, "lower") <- attr(base_receiver, "lower")
  attr(recv, "upper") <- attr(base_receiver, "upper")
  attr(recv, "config") <- list(
    base_receiver = "wrapped",
    condition = "custom"
  )

  recv
}

# ============================================================================
# Usage Examples
# ============================================================================

# Example 1: Email alerts for critical errors
if (FALSE) {
  library(logthis)

  log_this <- logger() %>%
    with_receivers(
      to_console(),
      to_email(to = "admin@example.com",
               subject_template = "[{level}] Production Alert",
               lower = ERROR)
    )

  log_this(ERROR("Database connection lost", retries = 3))
  # → Logs to console AND sends email
}

# Example 2: Slack notifications
if (FALSE) {
  library(logthis)

  log_this <- logger() %>%
    with_receivers(
      to_console(),
      to_slack(webhook_url = "https://hooks.slack.com/services/...",
               channel = "#alerts",
               lower = WARNING)
    )

  log_this(WARNING("API rate limit approaching", remaining = 100))
  # → Logs to console AND posts to Slack
}

# Example 3: Buffered file writing (performance optimization)
if (FALSE) {
  library(logthis)

  buffered <- to_buffered_file("high_volume.log",
                               buffer_size = 1000,
                               flush_interval_secs = 30)

  log_this <- logger() %>%
    with_receivers(buffered)

  # High-volume logging
  for (i in 1:10000) {
    log_this(TRACE("Processing item", item_id = i))
  }

  # Manual flush if needed
  attr(buffered, "flush")()
}

# Example 4: Conditional logging
if (FALSE) {
  library(logthis)

  # Only log events with specific tag
  conditional <- to_conditional(
    to_console(),
    condition_func = function(event) {
      "critical_path" %in% event$tags
    }
  )

  log_this <- logger() %>%
    with_receivers(conditional)

  log_this(NOTE("Normal event"))  # Not logged
  log_this(NOTE("Important event", tags = "critical_path"))  # Logged
}

# Example 5: System command execution
if (FALSE) {
  library(logthis)

  # Trigger system command on specific events
  log_this <- logger() %>%
    with_receivers(
      to_console(),
      to_system(command_template = "echo '{time} [{level}] {message}' >> /var/log/app.log",
                lower = WARNING)
    )

  log_this(WARNING("Disk space low", available_gb = 2))
  # → Executes system command
}

# ============================================================================
# Best Practices
# ============================================================================

# 1. Always return invisible(NULL)
#    - Receivers should not interfere with event flow
#    - Allows logger to return event for chaining

# 2. Implement level filtering
#    - Use lower/upper parameters
#    - Check at beginning of closure
#    - Return early if filtered

# 3. Handle errors gracefully
#    - Use tryCatch for external operations
#    - Throw informative errors (logger will catch)
#    - Include context in error messages

# 4. Store configuration as attributes
#    - Makes debugging easier
#    - Enables introspection
#    - Follows logthis conventions

# 5. Consider performance
#    - Avoid expensive operations if filtered
#    - Use buffering for high-volume scenarios
#    - Close resources properly

# 6. Document behavior
#    - When does receiver trigger?
#    - What side effects occur?
#    - What external dependencies?

# ============================================================================
# Integration Checklist
# ============================================================================

# □ Constructor function created (to_xxx)
# □ Takes configuration parameters
# □ Includes lower/upper parameters for filtering
# □ Returns receiver(function(event) {...})
# □ Implements level filtering logic
# □ Returns invisible(NULL)
# □ Handles errors with tryCatch
# □ Stores attributes (lower, upper, config)
# □ Added documentation (roxygen2)
# □ Added tests (testthat)
# □ Tested with logger() %>% with_receivers()
# □ Tested error handling (logger continues despite failures)
