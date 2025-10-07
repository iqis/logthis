#' Create a log receiver function with validation
#'
#' Constructor function that validates receiver functions conform to the required
#' interface: exactly one argument named 'event'. This ensures receivers can
#' properly handle log events passed from the logger.
#'
#' @param func A function that accepts one argument named 'event'
#'
#' @return A validated log receiver function with proper class attributes
#' @export
#'
#' @examples
#' # Create a custom receiver using the constructor
#' my_receiver <- receiver(function(event) {
#'   cat("LOG:", event$message, "\n")
#'   invisible(NULL)
#' })
#' 
#' # This will error - wrong argument name
#' \dontrun{
#' bad_receiver <- receiver(function(log_event) {
#'   cat(log_event$message, "\n")
#' })
#' }
receiver <- function(func) {
  if (!is.function(func)) {
    stop("Receiver must be a function")
  }
  
  args <- formals(func)
  
  if (length(args) != 1) {
    stop("Receiver function must have exactly one argument, got ", length(args))
  }
  
  if (names(args)[1] != "event") {
    stop("Receiver function argument must be named 'event', got '", names(args)[1], "'")
  }
  
  structure(func, class = c("log_receiver", "function"))
}

# ============================================================================
# FORMATTERS - Convert events to formatted strings
# ============================================================================

#' Create a log formatter function
#'
#' Constructor for formatters that convert log events to strings. Formatters
#' must be paired with a backend via on_*() functions before they can be used
#' as receivers.
#'
#' @param func A function that accepts one argument named 'event' and returns a string
#' @return A validated log formatter function with proper class attributes
#' @keywords internal
formatter <- function(func) {
  if (!is.function(func)) {
    stop("Formatter must be a function")
  }

  args <- formals(func)

  if (length(args) != 1) {
    stop("Formatter function must have exactly one argument, got ", length(args))
  }

  if (names(args)[1] != "event") {
    stop("Formatter function argument must be named 'event', got '", names(args)[1], "'")
  }

  structure(func, class = c("log_formatter", "function"))
}

#' Create a text formatter
#'
#' Creates a formatter that converts log events to text using a glue template.
#' Must be paired with a backend via on_*() functions before use in a logger.
#'
#' @section Available Template Variables:
#'
#' **Standard Event Fields** (always available):
#' - `{time}` - Event timestamp
#' - `{level}` - Event level name (e.g., "WARNING")
#' - `{level_number}` - Numeric level value (e.g., 60)
#' - `{message}` - The log message text
#' - `{tags}` - Formatted tag list (e.g., "[auth, security]" or "" if no tags)
#'
#' **Custom Fields**: Any additional fields passed when creating the event
#'
#' @param template glue template string (default: "{time} [{level}:{level_number}] {message}")
#' @return log formatter; <log_formatter>
#' @export
#' @family formatters
#'
#' @section Type Contract:
#' ```
#' to_text(template: string = "{time} [{level}:{level_number}] {message}") -> log_formatter
#'   where log_formatter is enriched by on_*() handlers
#' ```
#'
#' @examples
#' # Basic formatter with local backend
#' to_text() %>% on_local(path = "app.log")
#'
#' # Custom template with tags
#' to_text(template = "{time} [{level}] {tags} {message}") %>%
#'   on_local(path = "app.log")
to_text <- function(template = "{time} [{level}:{level_number}] {message}") {
  fmt_func <- formatter(function(event) {
    # Build data for glue template with ALL standard fields
    data <- list(time = as.character(event$time),
                 level = event$level_class,
                 level_number = event$level_number,
                 message = event$message,
                 tags = if (!is.null(event$tags) && length(event$tags) > 0) {
                   paste0("[", paste(event$tags, collapse = ", "), "]")
                 } else {
                   ""
                 })

    # Add custom event fields
    custom_fields <- setdiff(names(event),
                             c("time", "level_class", "level_number",
                               "message", "tags"))
    for (field in custom_fields) {
      data[[field]] <- event[[field]]
    }

    glue::glue(template, .envir = list2env(data, parent = emptyenv()))
  })

  # Attach config
  attr(fmt_func, "config") <- list(format_type = "text",
                                    template = template,
                                    backend = NULL,
                                    backend_config = list(),
                                    lower = NULL,
                                    upper = NULL)

  fmt_func
}

#' Create a JSON formatter
#'
#' Creates a formatter that converts log events to JSON (JSONL format).
#' Must be paired with a backend via on_*() functions before use in a logger.
#'
#' @section JSON Output Structure:
#'
#' **Standard Fields** (always included):
#' - `time` - Event timestamp as string
#' - `level` - Event level name
#' - `level_number` - Numeric level value
#' - `message` - The log message text
#' - `tags` - Array of tags (only if present)
#'
#' **Custom Fields**: Automatically included with types preserved
#'
#' @param pretty Pretty-print JSON (default: FALSE for compact JSONL)
#' @return log formatter; <log_formatter>
#' @export
#' @family formatters
#'
#' @section Type Contract:
#' ```
#' to_json(pretty: logical = FALSE) -> log_formatter
#'   where log_formatter is enriched by on_*() handlers
#' ```
#'
#' @examples
#' # Compact JSON to local file
#' to_json() %>% on_local(path = "app.jsonl")
#'
#' # Pretty JSON for debugging
#' to_json(pretty = TRUE) %>% on_local(path = "debug.json")
to_json <- function(pretty = FALSE) {
  fmt_func <- formatter(function(event) {
    # Extract all event data
    event_data <- list(time = as.character(event$time),
                       level = event$level_class,
                       level_number = as.numeric(event$level_number),
                       message = event$message)

    # Add tags if present
    if (!is.null(event$tags) && length(event$tags) > 0) {
      event_data$tags <- event$tags
    }

    # Add custom fields
    custom_fields <- setdiff(names(event),
                             c("time", "level_class", "level_number",
                               "message", "tags"))
    for (field in custom_fields) {
      event_data[[field]] <- event[[field]]
    }

    jsonlite::toJSON(event_data,
                     auto_unbox = TRUE,
                     pretty = attr(sys.function(), "config")$pretty)
  })

  # Attach config
  attr(fmt_func, "config") <- list(format_type = "json",
                                    pretty = pretty,
                                    backend = NULL,
                                    backend_config = list(),
                                    lower = NULL,
                                    upper = NULL)

  fmt_func
}

# Dummy receivers, mainly for testing
#' Identity receiver for testing
#'
#' A receiver that returns the event unchanged. Primarily used for testing
#' purposes to verify that events are being processed correctly.
#'
#' @return A log receiver that returns the log event as-is
#' @family receivers
#' @export
to_identity <- function(){
  receiver(function(event){
    event  # This one returns the event for testing purposes
  })
}

#' Void receiver that discards events
#'
#' A receiver that discards all log events by returning NULL invisibly.
#' Used for testing or when you want to disable logging temporarily.
#'
#' @return A log receiver that discards all events
#' @family receivers
#' @export
to_void <- function(){
  receiver(function(event){
    invisible(NULL)
  })
}

# ============================================================================
# HANDLERS - Attach storage handlers to formatters
# ============================================================================

#' Attach local filesystem handler to formatter
#'
#' Configures a formatter to write to local files. Returns an enriched formatter
#' that will be auto-converted to a receiver when passed to with_receivers().
#'
#' @param formatter A log formatter from to_text(), to_json(), etc.
#' @param path File path for output
#' @param append Append to existing file
#' @param max_size Max file size in bytes before rotation (NULL = no rotation)
#' @param max_files Number of rotated files to keep
#' @return Enriched log formatter; <log_formatter>
#' @export
#' @family handlers
#'
#' @section Type Contract:
#' ```
#' on_local(formatter: log_formatter, path: string, append: logical = TRUE,
#'          max_size: numeric | NULL = NULL, max_files: numeric = 5) -> log_formatter
#' ```
#'
#' @examples
#' # Basic local file
#' to_text() %>% on_local(path = "app.log")
#'
#' # With rotation
#' to_text() %>% on_local(path = "app.log",
#'                        max_size = 1e6,
#'                        max_files = 10)
on_local <- function(formatter,
                     path,
                     append = TRUE,
                     max_size = NULL,
                     max_files = 5) {
  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter created by to_text(), to_json(), etc.\n",
         "  Got: ", class(formatter)[1], "\n",
         "  Solution: Use to_text() or to_json() to create formatter first\n",
         "  Example: to_text() %>% on_local(path = \"app.log\")\n",
         "  See: .claude/decision-tree.md section 4 for formatting options")
  }

  config <- attr(formatter, "config")

  # Validate rotation config
  if (!is.null(max_size)) {
    stopifnot(is.numeric(max_size), max_size > 0)
  }
  if (!is.null(max_files)) {
    stopifnot(is.numeric(max_files), max_files > 0)
    max_files <- as.integer(max_files)
  }

  # Clear file if not appending
  if (!append && file.exists(path)) {
    unlink(path)
  }

  # Enrich config with handler info
  config$backend <- "local"
  config$backend_config <- list(path = path,
                                 append = append,
                                 max_size = max_size,
                                 max_files = max_files)

  # Return enriched formatter
  attr(formatter, "config") <- config
  formatter
}

#' Attach S3 handler to formatter
#'
#' @param formatter A log formatter
#' @param bucket S3 bucket name
#' @param key S3 object key (path within bucket)
#' @param region AWS region
#' @param ... Additional arguments passed to aws.s3::put_object()
#' @return Enriched log formatter; <log_formatter>
#' @export
#' @family handlers
#'
#' @examples
#' \dontrun{
#' # Text logs to S3
#' to_text() %>% on_s3(bucket = "my-logs",
#'                     key = "app/production.log")
#'
#' # JSON logs to S3
#' to_json() %>% on_s3(bucket = "my-logs",
#'                     key = "app/events.jsonl")
#' }
on_s3 <- function(formatter,
                  bucket,
                  key,
                  region = "us-east-1",
                  ...) {
  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter.\n",
         "  Got: ", class(formatter)[1], "\n",
         "  Solution: Use to_text() or to_json() to create formatter first\n",
         "  Example: to_json() %>% on_s3(bucket = \"logs\", key = \"app.jsonl\")\n",
         "  See: UC-010 in .claude/use-cases.md")
  }

  config <- attr(formatter, "config")

  config$backend <- "s3"
  config$backend_config <- list(bucket = bucket,
                                 key = key,
                                 region = region,
                                 extra_args = list(...))

  attr(formatter, "config") <- config
  formatter
}

#' Attach Azure Blob Storage handler to formatter
#'
#' @param formatter A log formatter
#' @param container Azure container name
#' @param blob Blob name (path within container)
#' @param endpoint Azure storage endpoint (from AzureStor::storage_endpoint())
#' @param ... Additional arguments
#' @return Enriched log formatter; <log_formatter>
#' @export
#' @family handlers
#'
#' @examples
#' \dontrun{
#' endpoint <- AzureStor::storage_endpoint("https://myaccount.blob.core.windows.net",
#'                                         key = "...")
#' to_text() %>% on_azure(container = "logs",
#'                        blob = "app.log",
#'                        endpoint = endpoint)
#' }
on_azure <- function(formatter,
                     container,
                     blob,
                     endpoint,
                     ...) {
  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter.\n",
         "  Got: ", class(formatter)[1], "\n",
         "  Solution: Use to_text() or to_json() to create formatter first\n",
         "  Example: to_json() %>% on_azure(container = \"logs\", blob = \"app.jsonl\")\n",
         "  See: UC-011 in .claude/use-cases.md")
  }

  config <- attr(formatter, "config")

  config$backend <- "azure"
  config$backend_config <- list(container = container,
                                 blob = blob,
                                 endpoint = endpoint,
                                 extra_args = list(...))

  attr(formatter, "config") <- config
  formatter
}

# ============================================================================
# INTERNAL: Formatter → Receiver Conversion
# ============================================================================

# Helper to rotate log files
.rotate_file <- function(path, max_files) {
  for (i in seq(max_files - 1, 1, -1)) {
    old_path <- paste0(path, ".", i)
    new_path <- paste0(path, ".", i + 1)
    if (file.exists(old_path)) {
      file.rename(old_path, new_path)
    }
  }
  if (file.exists(path)) {
    file.rename(path, paste0(path, ".1"))
  }
}

# Convert formatter to receiver
.formatter_to_receiver <- function(formatter) {
  if (!inherits(formatter, "log_formatter")) {
    stop("Must be a log_formatter")
  }

  config <- attr(formatter, "config")

  if (is.null(config$backend)) {
    stop("Formatter must have a handler configured via on_local(), on_s3(), etc.")
  }

  # Dispatch to handler-specific builder
  if (config$backend == "local") {
    .build_local_receiver(formatter, config)
  } else if (config$backend == "s3") {
    .build_s3_receiver(formatter, config)
  } else if (config$backend == "azure") {
    .build_azure_receiver(formatter, config)
  } else {
    stop("Unknown backend type: ", config$backend)
  }
}

# Build local filesystem receiver
.build_local_receiver <- function(formatter, config) {
  bc <- config$backend_config

  receiver(function(event) {
    # Level filtering (if configured on formatter)
    if (!is.null(config$lower) &&
        event$level_number < attr(config$lower, "level_number")) {
      return(invisible(NULL))
    }
    if (!is.null(config$upper) &&
        event$level_number > attr(config$upper, "level_number")) {
      return(invisible(NULL))
    }

    # Check rotation
    if (!is.null(bc$max_size) && file.exists(bc$path)) {
      file_size <- file.info(bc$path)$size
      if (!is.na(file_size) && file_size >= bc$max_size) {
        .rotate_file(bc$path, bc$max_files)
      }
    }

    # Format and write
    content <- formatter(event)
    cat(content, "\n", file = bc$path, append = TRUE)

    invisible(NULL)
  })
}

# Build S3 receiver
.build_s3_receiver <- function(formatter, config) {
  bc <- config$backend_config

  # Check package availability at receiver creation time
  if (!requireNamespace("aws.s3", quietly = TRUE)) {
    stop("Package 'aws.s3' required for S3 backend. Install with: install.packages('aws.s3')")
  }

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

    # Format
    content <- formatter(event)

    # Write to S3 (append by reading, appending, writing back)
    tryCatch({
      # Try to read existing content
      existing <- tryCatch(aws.s3::get_object(object = bc$key,
                                              bucket = bc$bucket,
                                              region = bc$region,
                                              as = "text"),
                           error = function(e) "")

      # Append new content
      new_content <- paste0(existing, content, "\n")

      # Write back
      do.call(aws.s3::put_object,
              c(list(file = charToRaw(new_content),
                     object = bc$key,
                     bucket = bc$bucket,
                     region = bc$region),
                bc$extra_args))
    }, error = function(e) {
      warning("S3 write failed: ", conditionMessage(e), call. = FALSE)
    })

    invisible(NULL)
  })
}

# Build Azure receiver
.build_azure_receiver <- function(formatter, config) {
  bc <- config$backend_config

  if (!requireNamespace("AzureStor", quietly = TRUE)) {
    stop("Package 'AzureStor' required for Azure backend")
  }

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

    # Format
    content <- formatter(event)

    # Write to Azure Blob
    tryCatch({
      cont <- AzureStor::blob_container(bc$endpoint, bc$container)

      # Read existing, append, write back (simplified)
      existing <- tryCatch(AzureStor::storage_download(cont,
                                                        bc$blob,
                                                        overwrite = TRUE),
                           error = function(e) "")

      new_content <- paste0(existing, content, "\n")

      do.call(AzureStor::storage_upload,
              c(list(cont, charToRaw(new_content), bc$blob),
                bc$extra_args))
    }, error = function(e) {
      warning("Azure write failed: ", conditionMessage(e), call. = FALSE)
    })

    invisible(NULL)
  })
}

#' Console receiver with color-coded output
#'
#' Outputs log events to the console with color coding based on event level.
#' This is receiver-level filtering - events are filtered after passing through
#' logger-level filtering set by with_limits().
#'
#' Level limits are inclusive: events with level_number >= lower AND <= upper
#' will be processed by this receiver.
#'
#' @param lower minimum level to display (inclusive, optional); <log_event_level>
#' @param upper maximum level to display (inclusive, optional); <log_event_level>
#'
#' @return log receiver function; <log_receiver>
#' @export
#'
#' @section Type Contract:
#' ```
#' to_console(lower: log_event_level = LOWEST, upper: log_event_level = HIGHEST) -> log_receiver
#'   where log_receiver = function(log_event) -> NULL (invisible)
#' ```
#'
#' @examples
#' # Basic console output (no filtering)
#' console_recv <- to_console()
#' 
#' # Receiver-level filtering: only show warnings and errors (inclusive)
#' console_recv <- to_console(lower = WARNING, upper = ERROR)
#' 
#' # Combined with logger-level filtering
#' log_this <- logger() %>%
#'     with_receivers(to_console(lower = NOTE)) %>%  # Receiver: NOTE+ (inclusive)
#'     with_limits(lower = CHATTER, upper = HIGHEST)     # Logger: CHATTER+ (inclusive)
#' # Result: Shows CHATTER+ events, console receiver shows NOTE+ subset
#' 
#' # Custom receiver example using the receiver() constructor
#' my_receiver <- receiver(function(event) {
#'   cat("CUSTOM:", event$message, "\n")
#'   invisible(NULL)
#' })
#' 
#' # Use custom receiver
#' log_this <- logger() %>% with_receivers(my_receiver)
#'
#' @export
to_console <- function(lower = LOWEST,
                       upper = HIGHEST){
  receiver(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number <= attr(upper, "level_number")) {

        color_fn <- get_log_color(event$level_number)

        with(event,
             cat(color_fn(paste0(time, " ",
                                 "[", level_class, "]", " ",
                                 message,
                                 "\n"))))
      }
      invisible(NULL)
      })
}

#' Shiny alert receiver
#'
#' Displays log events as Shiny alert popups using the shinyalert package.
#' Requires the 'shinyalert' package and an active Shiny session.
#'
#' @param lower minimum level to display (inclusive, optional); <log_event_level>
#' @param upper maximum level to display (inclusive, optional); <log_event_level>
#' @param ... additional arguments passed to shinyalert::shinyalert
#'
#' @return log receiver function; <log_receiver>
#' @export
#'
#' @examples
#' \dontrun{
#' # Requires shinyalert package and active Shiny session
#' alert_recv <- to_shinyalert()
#' }
to_shinyalert <- function(lower = WARNING, upper = HIGHEST, ...){
  receiver(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number <= attr(upper, "level_number")) {

        # Check if shinyalert is available
        if (!requireNamespace("shinyalert", quietly = TRUE)) {
          warning("shinyalert package is required for to_shinyalert() receiver but is not installed. ",
                  "Install with: install.packages('shinyalert')")
          return(invisible(NULL))
        }

        # TODO: add level lookup table
        shinyalert::shinyalert(text = event$message,
                               type = "error",
                               ...)
      }
      invisible(NULL)
    })
}

#' Shiny notification receiver
#'
#' Displays log events as Shiny notifications. Requires the 'shiny' package
#' to be installed and a Shiny session to be active.
#'
#' @param lower minimum level to display (inclusive, optional); <log_event_level>
#' @param upper maximum level to display (inclusive, optional); <log_event_level>  
#' @param ... additional arguments passed to shiny::showNotification
#'
#' @return log receiver function; <log_receiver>
#' @export
#'
#' @examples
#' \dontrun{
#' # Requires shiny package and active Shiny session
#' if (requireNamespace("shiny", quietly = TRUE)) {
#'   notif_recv <- to_notif()
#' }
#' }
to_notif <- function(lower = NOTE, upper = WARNING, ...){
  receiver(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number <= attr(upper, "level_number")) {

        # Check if shiny is available
        if (!requireNamespace("shiny", quietly = TRUE)) {
          warning("shiny package is required for to_notif() receiver but is not installed. ",
                  "Install with: install.packages('shiny')")
          return(invisible(NULL))
        }

        # TODO: build event level mapping
        shiny::showNotification(event$message,
                                ...)
      }
      invisible(NULL)
    })
}

#' Text file logging receiver
#'
#' Writes log events to a text file with timestamp and level information.
#' Level limits are inclusive: events with level_number >= lower AND <= upper
#' will be written to the file. Supports automatic file rotation based on size.
#'
#' @param lower minimum level to log (inclusive, optional); <log_event_level>
#' @param upper maximum level to log (inclusive, optional); <log_event_level>
#' @param path file path for log output; <character>
#' @param append whether to append to existing file; <logical>
#' @param max_size maximum file size in bytes before rotation (default: NULL, no rotation); <numeric>
#' @param max_files maximum number of rotated files to keep (default: 5); <integer>
#' @param ... additional arguments (unused)
#'
#' @return log receiver function; <log_receiver>
#' @export
#'
#' @examples
#' # Basic file logging
#' file_recv <- to_text_file(path = "app.log")
#'
#' # Log only errors and above (inclusive)
#' error_file <- to_text_file(lower = ERROR, path = "errors.log")
#'
#' # File logging with rotation (rotate when file exceeds 1MB, keep 10 rotated files)
#' rotating_file <- to_text_file(path = "app.log", max_size = 1e6, max_files = 10)
#'
#' # Custom file receiver using the receiver() constructor
#' simple_file_logger <- receiver(function(event) {
#'   cat(paste(event$time, event$level_class, event$message),
#'       file = "simple.log", append = TRUE, sep = "\n")
#'   invisible(NULL)
#' })
#'
to_text_file <- function(lower = LOWEST,
                         upper = HIGHEST,
                         path = "log.txt",
                         append = FALSE,
                         max_size = NULL,
                         max_files = 5, ...){
  stopifnot(is.character(path),
            is.logical(append))

  if (!is.null(max_size)) {
    stopifnot(is.numeric(max_size), max_size > 0)
  }

  if (!is.null(max_files)) {
    stopifnot(is.numeric(max_files), max_files > 0)
    max_files <- as.integer(max_files)
  }

  if (!append) {
    unlink(path)
  }

  # Helper function to rotate log files
  rotate_file <- function(path, max_files) {
    # Shift existing rotated files (log.txt.2 -> log.txt.3, etc.)
    for (i in seq(max_files - 1, 1, -1)) {
      old_path <- paste0(path, ".", i)
      new_path <- paste0(path, ".", i + 1)
      if (file.exists(old_path)) {
        file.rename(old_path, new_path)
      }
    }

    # Move current log file to .1
    if (file.exists(path)) {
      file.rename(path, paste0(path, ".1"))
    }
  }

  receiver(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number <= attr(upper, "level_number")) {

        # Check if rotation is needed
        if (!is.null(max_size) && file.exists(path)) {
          file_size <- file.info(path)$size
          if (!is.na(file_size) && file_size >= max_size) {
            rotate_file(path, max_files)
          }
        }

        with(event,
             cat(paste0(time, " ",
                        "[", level_class, "]", " ",
                        message,
                        "\n"),
                 file = path,
                 append = TRUE))
      }
      invisible(NULL)
    })
}

#' JSON file logging receiver
#'
#' Writes log events to a file as JSON objects, one per line (JSONL format).
#' This format is ideal for log aggregation systems, cloud logging services,
#' and structured log analysis tools.
#'
#' Each log entry is written as a single-line JSON object containing all event
#' metadata: timestamp, level, message, and tags.
#'
#' Level limits are inclusive: events with level_number >= lower AND <= upper
#' will be written to the file.
#'
#' @param lower minimum level to log (inclusive, optional); <log_event_level>
#' @param upper maximum level to log (inclusive, optional); <log_event_level>
#' @param path file path for JSON log output; <character>
#' @param append whether to append to existing file; <logical>
#' @param pretty whether to pretty-print JSON (default: FALSE for compact output); <logical>
#' @param ... additional arguments (unused)
#'
#' @return log receiver function; <log_receiver>
#' @export
#'
#' @examples
#' \dontrun{
#' # Basic JSON logging
#' json_recv <- to_json_file(path = "app.jsonl")
#'
#' # JSON logging with pretty printing (for debugging)
#' pretty_json <- to_json_file(path = "debug.json", pretty = TRUE)
#'
#' # Use with logger
#' log_this <- logger() %>%
#'     with_receivers(
#'         to_console(),  # Human-readable console output
#'         to_json_file(path = "logs/app.jsonl")  # Machine-readable structured logs
#'     )
#'
#' log_this(NOTE("User login", tags = c("auth", "user:123")))
#' # Outputs (one JSON object per line):
#' # {"time":"2025-10-07 18:30:00","level":"NOTE","level_number":40,
#' #  "message":"User login","tags":["auth","user:123"]}
#' }
#'
to_json_file <- function(lower = LOWEST,
                         upper = HIGHEST,
                         path = "log.jsonl",
                         append = FALSE,
                         pretty = FALSE, ...){
  stopifnot(is.character(path),
            is.logical(append),
            is.logical(pretty))

  if (!append) {
    unlink(path)
  }

  receiver(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number <= attr(upper, "level_number")) {

        # Convert event to list for JSON serialization
        event_data <- list(
          time = as.character(event$time),
          level = event$level_class,
          level_number = as.numeric(event$level_number),
          message = event$message
        )

        # Add tags if present
        if (!is.null(event$tags) && length(event$tags) > 0) {
          event_data$tags <- event$tags
        }

        # Serialize to JSON
        json_line <- jsonlite::toJSON(event_data, auto_unbox = TRUE, pretty = pretty)

        # Write to file (one JSON object per line for JSONL format)
        cat(json_line, "\n", file = path, append = TRUE, sep = "")
      }
      invisible(NULL)
    })
}

