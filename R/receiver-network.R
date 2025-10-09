# ==============================================================================
# Receiver Network and Protocols
# ==============================================================================
# Network-based receivers using specific protocols (Teams, Syslog, Email).
# These are standalone receivers that don't use the formatter/handler pattern.

#' Microsoft Teams receiver with MessageCard format
#'
#' Sends log events to Microsoft Teams channels via incoming webhook.
#' Formats events as MessageCard JSON with color-coded visual urgency.
#' This is a complete receiver - use directly in with_receivers().
#'
#' **Note**: Requires the `httr2` and `jsonlite` packages.
#'
#' @section MessageCard Format:
#' Each log event becomes a MessageCard with:
#' - **Summary**: Card title (from `title` parameter)
#' - **Theme Color**: Maps to log level (ERROR=crimson, WARNING=orange, etc.)
#' - **Activity Title**: Log level and message preview
#' - **Facts**: Timestamp, Level (with number), Tags (if present)
#' - **Text**: Full log message
#'
#' @section Level Color Mapping:
#' - **CRITICAL/ERROR (80-100)**: Crimson (#DC143C)
#' - **WARNING (60-79)**: Orange (#FFA500)
#' - **MESSAGE/NOTE (30-59)**: Steel Blue (#4682B4)
#' - **DEBUG/TRACE (0-29)**: Gray (#808080)
#'
#' @section Creating Teams Webhook:
#' 1. In Teams channel: ... → Connectors → Incoming Webhook
#' 2. Name your webhook, optionally add image
#' 3. Copy the webhook URL
#' 4. Use URL in `to_teams(webhook_url = "https://...")`
#'
#' @param webhook_url Microsoft Teams incoming webhook URL
#' @param title Card title/summary (default: "Application Log")
#' @param lower Minimum level to send (inclusive, default: WARNING)
#' @param upper Maximum level to send (inclusive, default: HIGHEST)
#' @param timeout_seconds HTTP request timeout (default: 30)
#' @param max_tries Maximum retry attempts (default: 3)
#' @param ... Additional arguments (reserved for future use)
#'
#' @return log receiver function; <log_receiver>
#' @export
#' @family receivers
#'
#' @seealso [to_syslog()], [to_email()] for other network receivers, [on_webhook()] for generic HTTP integration
#'
#' @section Type Contract:
#' ```
#' to_teams(webhook_url: string, title: string = "Application Log",
#'          lower: log_event_level = WARNING, upper: log_event_level = HIGHEST,
#'          timeout_seconds: numeric = 30, max_tries: numeric = 3) -> log_receiver
#' ```
#'
#' @examples
#' \dontrun{
#' # Basic Teams receiver (warnings and errors only)
#' teams_recv <- to_teams(
#'   webhook_url = "https://outlook.office.com/webhook/..."
#' )
#'
#' # Custom title and all levels
#' teams_recv <- to_teams(
#'   webhook_url = "https://outlook.office.com/webhook/...",
#'   title = "Production API Logs",
#'   lower = NOTE,
#'   upper = HIGHEST
#' )
#'
#' # Use in logger
#' log_this <- logger() %>%
#'   with_receivers(
#'     to_console(),
#'     to_teams(webhook_url = Sys.getenv("TEAMS_WEBHOOK_URL"))
#'   )
#'
#' log_this(ERROR("Database connection failed", db_host = "prod-db-01"))
#' }
to_teams <- function(webhook_url,
                     title = "Application Log",
                     lower = WARNING,
                     upper = HIGHEST,
                     timeout_seconds = 30,
                     max_tries = 3,
                     ...) {
  # Check required packages
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("Package 'httr2' required for to_teams() receiver.\n",
         "  Solution: Install with install.packages('httr2')")
  }
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' required for to_teams() receiver.\n",
         "  Solution: Install with install.packages('jsonlite')")
  }

  # Validate webhook URL
  if (!is.character(webhook_url) || length(webhook_url) != 1 || webhook_url == "") {
    stop("`webhook_url` must be a non-empty character string")
  }

  # Extract level numbers for filtering
  lower_num <- attr(lower, "level_number")
  upper_num <- attr(upper, "level_number")

  # Level to color mapping for Teams
  get_teams_color <- function(level_number) {
    if (level_number >= 80) {
      "DC143C"  # Crimson (ERROR, CRITICAL)
    } else if (level_number >= 60) {
      "FFA500"  # Orange (WARNING)
    } else if (level_number >= 30) {
      "4682B4"  # Steel Blue (NOTE, MESSAGE)
    } else {
      "808080"  # Gray (DEBUG, TRACE, LOWEST)
    }
  }

  receiver(function(event) {
    # Level filtering
    if (event$level_number < lower_num || event$level_number > upper_num) {
      return(invisible(NULL))
    }

    # Build MessageCard JSON
    theme_color <- get_teams_color(event$level_number)

    # Build facts list
    facts <- list(
      list(name = "Timestamp", value = as.character(event$time)),
      list(name = "Level", value = paste0(event$level_class, " (", event$level_number, ")"))
    )

    # Add tags fact if present
    if (!is.null(event$tags) && length(event$tags) > 0) {
      facts <- c(facts, list(list(
        name = "Tags",
        value = paste(event$tags, collapse = ", ")
      )))
    }

    # Add custom fields as facts
    custom_fields <- setdiff(names(event),
                             c("time", "level_class", "level_number",
                               "message", "tags"))
    for (field in custom_fields) {
      field_value <- event[[field]]
      # Convert to character for display
      if (is.atomic(field_value) && length(field_value) == 1) {
        facts <- c(facts, list(list(
          name = field,
          value = as.character(field_value)
        )))
      }
    }

    # Build Adaptive Card payload for Power Automate
    # Reference: https://adaptivecards.io/designer/

    # Build facts for Adaptive Card
    facts_list <- list()
    facts_list[[length(facts_list) + 1]] <- list(title = "Level", value = paste0(event$level_class, " (", as.numeric(event$level_number), ")"))
    facts_list[[length(facts_list) + 1]] <- list(title = "Time", value = as.character(event$time))

    if (!is.null(event$tags) && length(event$tags) > 0) {
      facts_list[[length(facts_list) + 1]] <- list(title = "Tags", value = paste(event$tags, collapse = ", "))
    }

    # Add custom fields
    custom_fields <- setdiff(names(event),
                             c("time", "level_class", "level_number",
                               "message", "tags"))
    for (field in custom_fields) {
      field_value <- event[[field]]
      if (is.atomic(field_value) && length(field_value) == 1) {
        facts_list[[length(facts_list) + 1]] <- list(title = field, value = as.character(field_value))
      }
    }

    # Build Adaptive Card
    payload <- list(
      type = "message",
      attachments = list(
        list(
          contentType = "application/vnd.microsoft.card.adaptive",
          contentUrl = NULL,
          content = list(
            `$schema` = "http://adaptivecards.io/schemas/adaptive-card.json",
            type = "AdaptiveCard",
            version = "1.2",
            body = list(
              list(
                type = "TextBlock",
                size = "Large",
                weight = "Bolder",
                text = paste0("[", event$level_class, "]"),
                color = if (as.numeric(event$level_number) >= 80) "Attention" else if (as.numeric(event$level_number) >= 60) "Warning" else "Good"
              ),
              list(
                type = "TextBlock",
                text = event$message,
                wrap = TRUE
              ),
              list(
                type = "FactSet",
                facts = facts_list
              )
            )
          )
        )
      )
    )

    # Convert to JSON
    json_body <- jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = FALSE)

    # Send to Teams via httr2
    tryCatch({
      req <- httr2::request(webhook_url)
      req <- httr2::req_method(req, "POST")
      req <- httr2::req_body_raw(req, charToRaw(json_body))
      req <- httr2::req_headers(req, `Content-Type` = "application/json")
      req <- httr2::req_timeout(req, timeout_seconds)

      # Retry on 5xx errors
      if (max_tries > 1) {
        req <- httr2::req_retry(req,
                                max_tries = max_tries,
                                is_transient = function(resp) {
                                  httr2::resp_status(resp) >= 500
                                })
      }

      resp <- httr2::req_perform(req)

      # Check response
      if (httr2::resp_status(resp) < 200 || httr2::resp_status(resp) >= 300) {
        warning("Teams webhook request failed with status ", httr2::resp_status(resp),
                call. = FALSE)
      }

    }, error = function(e) {
      warning("Teams webhook request failed: ", conditionMessage(e), call. = FALSE)
    })

    invisible(NULL)
  })
}

#' Syslog receiver with RFC 3164/5424 support
#'
#' Sends log events to syslog daemon via local socket, UDP, or TCP.
#' Supports both RFC 3164 (BSD syslog) and RFC 5424 (modern syslog) protocols.
#' This is a complete receiver - use directly in with_receivers().
#'
#' @section Syslog Protocol:
#' **RFC 3164 (BSD syslog, default):**
#' ```
#' <priority>timestamp hostname app_name[pid]: message
#' ```
#'
#' **RFC 5424 (modern):**
#' ```
#' <priority>version timestamp hostname app_name pid msgid - message
#' ```
#'
#' @section Level→Severity Mapping:
#' logthis levels mapped to syslog severities (0-7):
#' - **0-19 (LOWEST, TRACE)**: debug (7)
#' - **20-39 (DEBUG)**: debug (7)
#' - **40-49 (NOTE)**: info (6)
#' - **50-59 (MESSAGE)**: notice (5)
#' - **60-79 (WARNING)**: warning (4)
#' - **80-89 (ERROR)**: error (3)
#' - **90-99 (CRITICAL)**: critical (2)
#' - **100 (HIGHEST)**: emergency (0)
#'
#' @section Priority Calculation:
#' Priority = (facility × 8) + severity
#' - Example: facility="user" (1), severity=error (3) → priority=11
#'
#' @param host Syslog server hostname (default: "localhost")
#' @param port Syslog server port (default: 514 for UDP, ignored for unix socket)
#' @param protocol Syslog message format: "rfc3164" or "rfc5424" (default: "rfc3164")
#' @param transport Transport protocol: "udp", "tcp", or "unix" (default: "udp")
#' @param facility Syslog facility: "user", "local0"-"local7", "daemon", etc. (default: "user")
#' @param app_name Application name in syslog messages (default: "R")
#' @param socket_path Path to UNIX domain socket (default: "/dev/log" on Linux)
#' @param lower Minimum level to send (inclusive, default: LOWEST)
#' @param upper Maximum level to send (inclusive, default: HIGHEST)
#' @return log receiver function; <log_receiver>
#' @export
#' @family receivers
#'
#' @seealso [to_teams()], [to_email()] for other network receivers
#'
#' @section Type Contract:
#' ```
#' to_syslog(host: string = "localhost", port: numeric = 514,
#'           protocol: string = "rfc3164", transport: string = "udp",
#'           facility: string = "user", app_name: string = "R",
#'           lower: log_event_level = LOWEST, upper: log_event_level = HIGHEST) -> log_receiver
#' ```
#'
#' @examples
#' \dontrun{
#' # Basic local syslog (UDP to localhost)
#' syslog_recv <- to_syslog()
#'
#' # Remote syslog server with custom facility
#' syslog_recv <- to_syslog(
#'   host = "syslog.example.com",
#'   port = 514,
#'   facility = "local0",
#'   app_name = "myapp"
#' )
#'
#' # Modern RFC 5424 format over TCP
#' syslog_recv <- to_syslog(
#'   protocol = "rfc5424",
#'   transport = "tcp"
#' )
#'
#' # Local UNIX socket (Linux/Mac)
#' syslog_recv <- to_syslog(
#'   transport = "unix",
#'   socket_path = "/dev/log"
#' )
#'
#' # Use in logger (errors and warnings only)
#' log_this <- logger() %>%
#'   with_receivers(
#'     to_console(),
#'     to_syslog(facility = "local1", lower = WARNING)
#'   )
#' }
to_syslog <- function(host = "localhost",
                      port = 514,
                      protocol = c("rfc3164", "rfc5424"),
                      transport = c("udp", "tcp", "unix"),
                      facility = "user",
                      app_name = "R",
                      socket_path = "/dev/log",
                      lower = LOWEST,
                      upper = HIGHEST) {
  # Validate and match arguments
  protocol <- match.arg(protocol)
  transport <- match.arg(transport)

  # Extract level numbers for filtering
  lower_num <- attr(lower, "level_number")
  upper_num <- attr(upper, "level_number")

  # Syslog facility codes
  facility_map <- c(
    "kern" = 0, "user" = 1, "mail" = 2, "daemon" = 3,
    "auth" = 4, "syslog" = 5, "lpr" = 6, "news" = 7,
    "uucp" = 8, "cron" = 9, "authpriv" = 10, "ftp" = 11,
    "local0" = 16, "local1" = 17, "local2" = 18, "local3" = 19,
    "local4" = 20, "local5" = 21, "local6" = 22, "local7" = 23
  )

  if (!facility %in% names(facility_map)) {
    stop("`facility` must be one of: ", paste(names(facility_map), collapse = ", "))
  }
  facility_code <- facility_map[[facility]]

  # Log level → syslog severity mapping
  get_syslog_severity <- function(level_number) {
    if (level_number >= 100) {
      0  # emergency
    } else if (level_number >= 90) {
      2  # critical
    } else if (level_number >= 80) {
      3  # error
    } else if (level_number >= 60) {
      4  # warning
    } else if (level_number >= 50) {
      5  # notice
    } else if (level_number >= 40) {
      6  # info
    } else {
      7  # debug
    }
  }

  # Open connection based on transport (closure variable)
  conn <- NULL
  get_connection <- function() {
    if (!is.null(conn)) {
      return(conn)
    }

    conn <<- tryCatch({
      if (transport == "unix") {
        # UNIX domain socket
        socketConnection(
          host = socket_path,
          open = "w+b",
          blocking = FALSE
        )
      } else if (transport == "tcp") {
        # TCP connection
        socketConnection(
          host = host,
          port = port,
          open = "w+b",
          blocking = TRUE
        )
      } else {
        # UDP connection
        socketConnection(
          host = host,
          port = port,
          open = "w+b",
          blocking = FALSE,
          server = FALSE
        )
      }
    }, error = function(e) {
      # Fail silently - connection unavailable in this environment
      # Logger's error handling will catch receiver failures if needed
      NULL
    })

    conn
  }

  # Format message based on protocol
  format_syslog_message <- function(event, priority) {
    if (protocol == "rfc3164") {
      # RFC 3164: <priority>timestamp hostname app_name[pid]: message
      timestamp <- format(event$time, "%b %d %H:%M:%S")
      hostname <- Sys.info()["nodename"]
      pid <- Sys.getpid()

      paste0("<", priority, ">",
             timestamp, " ",
             hostname, " ",
             app_name, "[", pid, "]: ",
             event$message)

    } else {
      # RFC 5424: <priority>version timestamp hostname app_name pid msgid - message
      timestamp <- format(event$time, "%Y-%m-%dT%H:%M:%S%z")
      hostname <- Sys.info()["nodename"]
      pid <- Sys.getpid()

      paste0("<", priority, ">",
             "1 ",  # version
             timestamp, " ",
             hostname, " ",
             app_name, " ",
             pid, " ",
             "- ",  # msgid (none)
             "- ",  # structured data (none)
             event$message)
    }
  }

  receiver(function(event) {
    # Level filtering
    if (event$level_number < lower_num || event$level_number > upper_num) {
      return(invisible(NULL))
    }

    # Calculate priority
    severity <- get_syslog_severity(event$level_number)
    priority <- (facility_code * 8) + severity

    # Format message
    msg <- format_syslog_message(event, priority)

    # Send to syslog
    tryCatch({
      connection <- get_connection()
      if (!is.null(connection)) {
        writeLines(msg, connection)
        flush(connection)
      }
    }, error = function(e) {
      # Fail silently and try to reconnect on next event
      # Logger's error handling will catch receiver failures if needed
      if (!is.null(conn)) {
        try(close(conn), silent = TRUE)
        conn <<- NULL
      }
    })

    invisible(NULL)
  })
}


#' Email notification receiver with batching
#'
#' Sends log events via email using SMTP. Events are batched to avoid sending
#' an email for every single log event. Uses plain text formatting.
#' Requires the blastula package for email delivery.
#'
#' **Batching behavior:**
#' - Events accumulate in memory until `batch_size` is reached
#' - When the batch is full, all accumulated events are sent in a single email
#' - A finalizer ensures remaining events are sent when the receiver is garbage collected
#' - For time-based batching, consider using async receivers with scheduled flushing
#'
#' **SMTP Configuration:**
#' Use `blastula::creds_*()` functions to create SMTP credentials:
#' - `creds_envvar()` - Read from environment variables (recommended for production)
#' - `creds_file()` - Read from encrypted file
#' - `creds_key()` - Read from system keyring
#' - `creds()` - Direct specification (not recommended for security)
#'
#' @param to Character vector of recipient email addresses
#' @param from Sender email address (must match SMTP credentials)
#' @param subject_template glue template for email subject (default: `"[{level}] Log Events"`)
#' @param smtp_settings SMTP credentials from blastula::creds_*() functions
#' @param batch_size Number of events to accumulate before sending email (default: 10)
#' @param cc Character vector of CC recipients (optional)
#' @param bcc Character vector of BCC recipients (optional)
#' @param lower Minimum level to include in emails (default: ERROR)
#' @param upper Maximum level to include in emails (default: HIGHEST)
#'
#' @return log receiver function; <log_receiver>
#' @export
#' @family receivers
#'
#' @seealso [to_teams()], [to_syslog()] for other network receivers
#'
#' @section Type Contract:
#' ```
#' to_email(to: character,
#'          from: character,
#'          subject_template: string = "[{level}] Log Events",
#'          smtp_settings: blastula::creds,
#'          batch_size: integer = 10,
#'          cc: character = NULL,
#'          bcc: character = NULL,
#'          lower: log_event_level = ERROR,
#'          upper: log_event_level = HIGHEST) -> log_receiver
#' ```
#'
#' @examples
#' \dontrun{
#' # Setup SMTP credentials (do this once, store securely)
#' smtp <- blastula::creds_envvar(
#'   user = "SMTP_USER",
#'   pass = "SMTP_PASS",
#'   host = "smtp.gmail.com",
#'   port = 587
#' )
#'
#' # Create email receiver (sends batch of 5 events at a time)
#' email_recv <- to_email(
#'   to = "alerts@example.com",
#'   from = "app@example.com",
#'   subject_template = "[{level}] Application Alerts - {Sys.Date()}",
#'   smtp_settings = smtp,
#'   batch_size = 5,
#'   lower = WARNING  # Only email warnings and above
#' )
#'
#' # Use in logger
#' log_this <- logger() %>%
#'   with_receivers(
#'     to_console(),  # All events to console
#'     email_recv     # Warnings+ batched to email
#'   )
#'
#' # These accumulate but don't send yet
#' log_this(WARNING("Database connection slow"))
#' log_this(WARNING("Memory usage high"))
#' log_this(ERROR("API request failed"))
#' log_this(WARNING("Disk space low"))
#' log_this(CRITICAL("Service crashed"))  # This triggers batch send (5 events)
#'
#' # Multiple recipients with CC
#' team_email <- to_email(
#'   to = c("dev1@example.com", "dev2@example.com"),
#'   from = "app@example.com",
#'   cc = "manager@example.com",
#'   smtp_settings = smtp,
#'   batch_size = 10,
#'   lower = ERROR  # Only errors and critical
#' )
#' }
to_email <- function(to,
                     from,
                     subject_template = "[{level}] Log Events",
                     smtp_settings,
                     batch_size = 10,
                     cc = NULL,
                     bcc = NULL,
                     lower = ERROR,
                     upper = HIGHEST) {
  # Check required package
  if (!requireNamespace("blastula", quietly = TRUE)) {
    stop("Package 'blastula' required for to_email() receiver.\n",
         "  Solution: Install with install.packages('blastula')")
  }

  # Validate inputs
  if (!is.character(to) || length(to) == 0) {
    stop("`to` must be a non-empty character vector of email addresses")
  }
  if (!is.character(from) || length(from) != 1) {
    stop("`from` must be a single email address")
  }
  if (!inherits(smtp_settings, "creds")) {
    stop("`smtp_settings` must be blastula SMTP credentials from creds_*() functions")
  }
  if (!is.numeric(batch_size) || batch_size < 1) {
    stop("`batch_size` must be a positive integer")
  }

  # Extract level numbers for filtering
  lower_num <- attr(lower, "level_number")
  upper_num <- attr(upper, "level_number")

  # Closure state for batching
  event_batch <- list()
  batch_count <- 0

  # Flush function - sends accumulated events
  flush_batch <- function() {
    if (batch_count == 0) {
      return(invisible(NULL))
    }

    # Determine highest severity level in batch for subject
    max_level_num <- max(sapply(event_batch, function(e) as.numeric(e$level_number)))
    max_level <- if (max_level_num >= 90) "CRITICAL"
                 else if (max_level_num >= 80) "ERROR"
                 else if (max_level_num >= 60) "WARNING"
                 else if (max_level_num >= 40) "MESSAGE"
                 else "INFO"

    # Build subject using template
    subject <- glue::glue(subject_template, level = max_level, .envir = parent.frame())

    # Build plain text email body
    body_text <- build_text_body(event_batch)
    email <- blastula::compose_email(body = blastula::md(body_text))

    # Send email
    tryCatch({
      blastula::smtp_send(
        email = email,
        to = to,
        from = from,
        cc = cc,
        bcc = bcc,
        subject = subject,
        credentials = smtp_settings
      )
    }, error = function(e) {
      warning("Email send failed: ", conditionMessage(e), call. = FALSE)
    })

    # Reset batch
    event_batch <<- list()
    batch_count <<- 0

    invisible(NULL)
  }

  # Plain text body builder
  build_text_body <- function(events) {
    header <- paste0("Log Event Batch (", length(events), " events)\n",
                     paste(rep("=", 80), collapse = ""), "\n\n")

    event_lines <- sapply(events, function(e) {
      tags_str <- if (!is.null(e$tags) && length(e$tags) > 0) {
        paste0(" [", paste(e$tags, collapse = ", "), "]")
      } else {
        ""
      }

      paste0(
        as.character(e$time), " [", e$level_class, ":", as.numeric(e$level_number), "] ",
        e$message, tags_str
      )
    })

    paste0(header, paste(event_lines, collapse = "\n"))
  }

  # Create receiver
  recv <- receiver(function(event) {
    # Level filtering
    if (event$level_number < lower_num || event$level_number > upper_num) {
      return(invisible(NULL))
    }

    # Add to batch
    event_batch <<- c(event_batch, list(event))
    batch_count <<- batch_count + 1

    # Flush if batch is full
    if (batch_count >= batch_size) {
      flush_batch()
    }

    invisible(NULL)
  })

  # Add finalizer to flush remaining events on cleanup
  reg.finalizer(environment(recv), function(env) {
    if (exists("flush_batch", envir = env, inherits = FALSE)) {
      env$flush_batch()
    }
  }, onexit = TRUE)

  recv
}

