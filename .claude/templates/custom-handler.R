# Template: Custom Handler
# Purpose: Add new storage destination (database, webhook, message queue, etc.)
# Pattern: Handler defines WHERE formatted output goes

# Step 1: Define handler function
# Parameters: formatter + backend-specific configuration
on_MYBACKEND <- function(formatter,
                         connection,
                         table,
                         option1 = "default") {

  # Step 2: Validate formatter
  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter created by to_text(), to_json(), etc.")
  }

  # Step 3: Get existing config from formatter
  config <- attr(formatter, "config")

  # Step 4: Enrich config with backend information
  config$backend <- "mybackend"  # Unique identifier for this handler
  config$backend_config <- list(
    connection = connection,
    table = table,
    option1 = option1
  )

  # Step 5: Store enriched config back
  attr(formatter, "config") <- config

  # Step 6: Return enriched formatter
  # with_receivers() will auto-convert to receiver using .formatter_to_receiver()
  formatter
}

# Step 7: Create builder function (internal)
# This function creates the actual receiver that writes to your backend
.build_mybackend_receiver <- function(formatter) {

  # Extract configuration
  config <- attr(formatter, "config")$backend_config
  format_func <- attr(formatter, "format_func")

  # Extract level limits if present
  lower <- attr(formatter, "config")$lower
  upper <- attr(formatter, "config")$upper

  # Create receiver closure
  receiver(function(event) {

    # Apply level filtering
    if (!is.null(lower) && event$level_number < as.numeric(lower)) {
      return(invisible(NULL))
    }
    if (!is.null(upper) && event$level_number > as.numeric(upper)) {
      return(invisible(NULL))
    }

    # Format event using formatter
    formatted <- format_func(event)

    # Write to backend
    # Replace this with your actual backend logic
    tryCatch({
      # Example: Database write
      # DBI::dbAppendTable(config$connection, config$table,
      #                    data.frame(log_entry = formatted,
      #                               timestamp = Sys.time()))

      # Example: HTTP POST
      # httr::POST(config$url, body = formatted)

      # Example: Message queue
      # rmq::publish(config$connection, config$queue, formatted)

      # Placeholder
      message("Would write to mybackend: ", formatted)

    }, error = function(e) {
      # Errors will be caught by logger's error handling
      stop("Failed to write to mybackend: ", e$message)
    })

    invisible(NULL)
  })
}

# Step 8: Register builder in .formatter_to_receiver()
# Add this case to the switch statement in R/receivers.R:.formatter_to_receiver()
#
# .formatter_to_receiver <- function(formatter) {
#   config <- attr(formatter, "config")
#   backend <- config$backend
#
#   switch(backend,
#          "local" = .build_local_receiver(formatter),
#          "s3" = .build_s3_receiver(formatter),
#          "azure" = .build_azure_receiver(formatter),
#          "mybackend" = .build_mybackend_receiver(formatter),  # ADD THIS
#          stop("Unknown backend: ", backend))
# }

# ============================================================================
# Example: Database handler
# ============================================================================

on_database <- function(formatter,
                        conn,
                        table,
                        batch_size = 100) {

  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter")
  }

  config <- attr(formatter, "config")
  config$backend <- "database"
  config$backend_config <- list(
    conn = conn,
    table = table,
    batch_size = batch_size,
    buffer = list()  # For batching
  )
  attr(formatter, "config") <- config

  formatter
}

.build_database_receiver <- function(formatter) {
  config <- attr(formatter, "config")$backend_config
  format_func <- attr(formatter, "format_func")
  lower <- attr(formatter, "config")$lower
  upper <- attr(formatter, "config")$upper

  # Create buffer in closure environment
  buffer <- list()

  receiver(function(event) {
    # Level filtering
    if (!is.null(lower) && event$level_number < as.numeric(lower)) {
      return(invisible(NULL))
    }
    if (!is.null(upper) && event$level_number > as.numeric(upper)) {
      return(invisible(NULL))
    }

    # Format event
    formatted <- format_func(event)

    # Add to buffer
    buffer <<- c(buffer, list(formatted))

    # Flush if batch size reached
    if (length(buffer) >= config$batch_size) {
      tryCatch({
        df <- data.frame(
          log_entry = unlist(buffer),
          timestamp = Sys.time(),
          stringsAsFactors = FALSE
        )
        DBI::dbAppendTable(config$conn, config$table, df)
        buffer <<- list()  # Clear buffer
      }, error = function(e) {
        stop("Database write failed: ", e$message)
      })
    }

    invisible(NULL)
  })
}

# ============================================================================
# Example: Webhook handler
# ============================================================================

on_webhook <- function(formatter,
                       url,
                       method = "POST",
                       headers = list()) {

  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter")
  }

  config <- attr(formatter, "config")
  config$backend <- "webhook"
  config$backend_config <- list(
    url = url,
    method = method,
    headers = headers
  )
  attr(formatter, "config") <- config

  formatter
}

.build_webhook_receiver <- function(formatter) {
  config <- attr(formatter, "config")$backend_config
  format_func <- attr(formatter, "format_func")
  lower <- attr(formatter, "config")$lower
  upper <- attr(formatter, "config")$upper

  receiver(function(event) {
    # Level filtering
    if (!is.null(lower) && event$level_number < as.numeric(lower)) {
      return(invisible(NULL))
    }
    if (!is.null(upper) && event$level_number > as.numeric(upper)) {
      return(invisible(NULL))
    }

    # Format event
    formatted <- format_func(event)

    # Send to webhook
    tryCatch({
      httr::VERB(config$method,
                 url = config$url,
                 body = formatted,
                 httr::add_headers(.headers = config$headers),
                 httr::content_type_json())
    }, error = function(e) {
      stop("Webhook request failed: ", e$message)
    })

    invisible(NULL)
  })
}

# ============================================================================
# Example: Syslog handler
# ============================================================================

on_syslog <- function(formatter,
                      host = "localhost",
                      port = 514,
                      facility = "user") {

  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter")
  }

  config <- attr(formatter, "config")
  config$backend <- "syslog"
  config$backend_config <- list(
    host = host,
    port = port,
    facility = facility
  )
  attr(formatter, "config") <- config

  formatter
}

.build_syslog_receiver <- function(formatter) {
  config <- attr(formatter, "config")$backend_config
  format_func <- attr(formatter, "format_func")
  lower <- attr(formatter, "config")$lower
  upper <- attr(formatter, "config")$upper

  # Map logthis levels to syslog severity
  severity_map <- c(
    "0" = 7,    # LOWEST -> DEBUG
    "10" = 7,   # TRACE -> DEBUG
    "20" = 7,   # DEBUG -> DEBUG
    "30" = 6,   # NOTE -> INFO
    "40" = 6,   # MESSAGE -> INFO
    "60" = 4,   # WARNING -> WARNING
    "80" = 3,   # ERROR -> ERROR
    "90" = 2,   # CRITICAL -> CRITICAL
    "100" = 2   # HIGHEST -> CRITICAL
  )

  receiver(function(event) {
    # Level filtering
    if (!is.null(lower) && event$level_number < as.numeric(lower)) {
      return(invisible(NULL))
    }
    if (!is.null(upper) && event$level_number > as.numeric(upper)) {
      return(invisible(NULL))
    }

    # Format event
    formatted <- format_func(event)

    # Get syslog severity
    severity <- severity_map[as.character(event$level_number)]
    if (is.na(severity)) severity <- 6  # Default to INFO

    # Send to syslog (requires rsyslog package or similar)
    tryCatch({
      # Placeholder - implement actual syslog protocol
      message(sprintf("SYSLOG[%s:%s] severity=%d: %s",
                      config$host, config$port, severity, formatted))
    }, error = function(e) {
      stop("Syslog send failed: ", e$message)
    })

    invisible(NULL)
  })
}

# ============================================================================
# Usage Examples
# ============================================================================

# Example 1: Database logging
if (FALSE) {
  library(logthis)
  library(DBI)

  conn <- dbConnect(RSQLite::SQLite(), "logs.db")
  dbExecute(conn, "CREATE TABLE IF NOT EXISTS logs (log_entry TEXT, timestamp TEXT)")

  log_this <- logger() %>%
    with_receivers(
      to_json() %>%
        on_database(conn, "logs", batch_size = 10)
    )

  log_this(NOTE("Application started"))
  log_this(ERROR("Something failed", error_code = 500))
}

# Example 2: Webhook logging
if (FALSE) {
  library(logthis)

  log_this <- logger() %>%
    with_receivers(
      to_json() %>%
        on_webhook(url = "https://example.com/api/logs",
                   headers = list(Authorization = "Bearer token123"))
    )

  log_this(WARNING("Rate limit approaching", requests = 950))
}

# Example 3: Syslog logging
if (FALSE) {
  library(logthis)

  log_this <- logger() %>%
    with_receivers(
      to_text("{time} [{level}] {message}") %>%
        on_syslog(host = "syslog.example.com", port = 514)
    )

  log_this(ERROR("Service degraded"))
}

# ============================================================================
# Integration Checklist
# ============================================================================

# □ Handler function created (on_xxx)
# □ Validates formatter with inherits(formatter, "log_formatter")
# □ Enriches formatter config with backend and backend_config
# □ Returns enriched formatter
# □ Builder function created (.build_xxx_receiver)
# □ Builder extracts config and creates receiver closure
# □ Builder implements level filtering
# □ Builder handles errors with informative messages
# □ Builder returns invisible(NULL)
# □ Added case to .formatter_to_receiver() switch in R/receivers.R
# □ Added documentation (roxygen2)
# □ Added tests (testthat)
# □ Handles resource cleanup if needed (connections, file handles, etc.)
