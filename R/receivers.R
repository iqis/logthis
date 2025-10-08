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
#' - `{tags}` - Formatted tag list (e.g., "\[auth, security\]" or "" if no tags)
#'
#' **Custom Fields**: Any additional fields passed when creating the event
#'
#' @param template glue template string
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
#' **Note**: Requires the `jsonlite` package. Install with `install.packages('jsonlite')`.
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
  # Check if jsonlite is available
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("jsonlite package is required for to_json() but is not installed.\n",
         "  Solution: Install with install.packages('jsonlite')\n",
         "  Or: Use to_text() for plain text logging instead")
  }

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
#' Configures buffered writes to AWS S3. Since S3 doesn't support append operations,
#' logs are written to time-partitioned keys when the buffer flushes.
#'
#' **Note**: Requires the `aws.s3` package. Install with `install.packages('aws.s3')`.
#'
#' @section S3 Key Pattern:
#' Each flush creates a new object with timestamp:
#' - `key_prefix = "logs/app"` produces: `logs/app-20251007-143022.log`
#' - Format: `{key_prefix}-{YYYYMMDD-HHMMSS}.log`
#'
#' @section Buffering:
#' Events are buffered in memory and flushed when:
#' - Buffer reaches `flush_threshold` events (default: 100)
#' - Manual flush via `attr(receiver, "flush")()`
#' - Process termination (register flush with on.exit() in your code)
#'
#' @param formatter A log formatter from to_text(), to_json(), etc.
#' @param bucket S3 bucket name
#' @param key_prefix S3 object key prefix (timestamp will be appended)
#' @param region AWS region (default: "us-east-1")
#' @param flush_threshold Number of events to buffer before auto-flush (default: 100)
#' @param ... Additional arguments passed to aws.s3::put_object()
#' @return Enriched log formatter; <log_formatter>
#' @export
#' @family handlers
#'
#' @section Type Contract:
#' ```
#' on_s3(formatter: log_formatter, bucket: string, key_prefix: string,
#'       region: string = "us-east-1", flush_threshold: numeric = 100) -> log_formatter
#' ```
#'
#' @examples
#' \dontrun{
#' # Text logs to S3 with default buffering (100 events)
#' recv <- to_text() %>% on_s3(bucket = "my-logs",
#'                              key_prefix = "app/production")
#'
#' # JSON logs with custom buffer size
#' recv <- to_json() %>% on_s3(bucket = "my-logs",
#'                              key_prefix = "app/events",
#'                              flush_threshold = 50)
#'
#' # Manual flush
#' log_this <- logger() %>% with_receivers(recv)
#' log_this(INFO("Event 1"))
#' # ... more events ...
#' attr(recv, "flush")()  # Force flush remaining buffer
#' }
on_s3 <- function(formatter,
                  bucket,
                  key_prefix,
                  region = "us-east-1",
                  flush_threshold = 100,
                  ...) {
  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter.\n",
         "  Got: ", class(formatter)[1], "\n",
         "  Solution: Use to_text() or to_json() to create formatter first\n",
         "  Example: to_json() %>% on_s3(bucket = \"logs\", key_prefix = \"app\")\n",
         "  See: UC-010 in .claude/use-cases.md")
  }

  if (!is.numeric(flush_threshold) || flush_threshold < 1) {
    stop("`flush_threshold` must be a positive number")
  }

  config <- attr(formatter, "config")

  config$backend <- "s3"
  config$backend_config <- list(bucket = bucket,
                                 key_prefix = key_prefix,
                                 region = region,
                                 flush_threshold = as.integer(flush_threshold),
                                 extra_args = list(...))

  attr(formatter, "config") <- config
  formatter
}

#' Attach Azure Blob Storage handler to formatter
#'
#' Configures buffered writes to Azure Blob Storage using Append Blobs.
#' Append Blobs are optimized for append operations, making them ideal for logging.
#'
#' **Note**: Requires the `AzureStor` package. Install with `install.packages('AzureStor')`.
#'
#' @section Azure Append Blobs:
#' - Blob is created as an AppendBlob on first write
#' - Each flush appends a block to the same blob
#' - Maximum blob size: 195 GB
#' - Maximum block size: 4 MB
#'
#' @section Buffering:
#' Events are buffered in memory and flushed when:
#' - Buffer reaches `flush_threshold` events (default: 100)
#' - Manual flush via `attr(receiver, "flush")()`
#' - Process termination (register flush with on.exit() in your code)
#'
#' @param formatter A log formatter from to_text(), to_json(), etc.
#' @param container Azure container name
#' @param blob Blob name (path within container)
#' @param endpoint Azure storage endpoint (from AzureStor::storage_endpoint())
#' @param flush_threshold Number of events to buffer before auto-flush (default: 100)
#' @param ... Additional arguments passed to AzureStor functions
#' @return Enriched log formatter; <log_formatter>
#' @export
#' @family handlers
#'
#' @section Type Contract:
#' ```
#' on_azure(formatter: log_formatter, container: string, blob: string,
#'          endpoint: storage_endpoint, flush_threshold: numeric = 100) -> log_formatter
#' ```
#'
#' @examples
#' \dontrun{
#' # Create endpoint
#' endpoint <- AzureStor::storage_endpoint(
#'   "https://myaccount.blob.core.windows.net",
#'   key = "your-access-key"
#' )
#'
#' # Text logs to Azure with default buffering
#' recv <- to_text() %>% on_azure(container = "logs",
#'                                 blob = "app.log",
#'                                 endpoint = endpoint)
#'
#' # JSON logs with custom buffer size
#' recv <- to_json() %>% on_azure(container = "logs",
#'                                 blob = "events.jsonl",
#'                                 endpoint = endpoint,
#'                                 flush_threshold = 50)
#'
#' # Manual flush
#' log_this <- logger() %>% with_receivers(recv)
#' log_this(INFO("Event 1"))
#' # ... more events ...
#' attr(recv, "flush")()  # Force flush remaining buffer
#' }
on_azure <- function(formatter,
                     container,
                     blob,
                     endpoint,
                     flush_threshold = 100,
                     ...) {
  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter.\n",
         "  Got: ", class(formatter)[1], "\n",
         "  Solution: Use to_text() or to_json() to create formatter first\n",
         "  Example: to_json() %>% on_azure(container = \"logs\", blob = \"app.jsonl\")\n",
         "  See: UC-011 in .claude/use-cases.md")
  }

  if (!is.numeric(flush_threshold) || flush_threshold < 1) {
    stop("`flush_threshold` must be a positive number")
  }

  config <- attr(formatter, "config")

  config$backend <- "azure"
  config$backend_config <- list(container = container,
                                 blob = blob,
                                 endpoint = endpoint,
                                 flush_threshold = as.integer(flush_threshold),
                                 extra_args = list(...))

  attr(formatter, "config") <- config
  formatter
}

# ============================================================================
# INTERNAL: Formatter → Receiver Conversion
# ============================================================================

# Backend registry for extensibility
# Stores builder functions that convert formatter+config to receiver
.backend_registry <- new.env(parent = emptyenv())

# Register a backend builder function
# @param name Backend name (e.g., "local", "s3", "webhook")
# @param builder_func Function with signature: function(formatter, config) -> log_receiver
.register_backend <- function(name, builder_func) {
  if (!is.character(name) || length(name) != 1) {
    stop("Backend name must be a single character string")
  }
  if (!is.function(builder_func)) {
    stop("Builder must be a function")
  }
  .backend_registry[[name]] <- builder_func
  invisible(NULL)
}


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

# Convert formatter to receiver using registry dispatch
.formatter_to_receiver <- function(formatter) {
  if (!inherits(formatter, "log_formatter")) {
    stop("Must be a log_formatter")
  }

  config <- attr(formatter, "config")

  if (is.null(config$backend)) {
    stop("Formatter must have a handler configured via on_local(), on_s3(), etc.")
  }

  # Look up builder in registry
  backend <- config$backend
  builder <- .backend_registry[[backend]]

  if (is.null(builder)) {
    available <- names(.backend_registry)
    stop("Unknown backend type: '", backend, "'\n",
         "  Available backends: ", paste(available, collapse = ", "), "\n",
         "  Solution: Use a supported on_*() handler function")
  }

  # Call the builder
  builder(formatter, config)
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

# Build S3 receiver with buffering
.build_s3_receiver <- function(formatter, config) {
  bc <- config$backend_config

  # Check package availability at receiver creation time
  if (!requireNamespace("aws.s3", quietly = TRUE)) {
    stop("Package 'aws.s3' required for S3 backend.\n",
         "  Solution: Install with install.packages('aws.s3')\n",
         "  Or: Use on_local() for local file logging instead")
  }

  # Initialize buffer (closure variable)
  buffer <- character(0)
  flush_threshold <- bc$flush_threshold

  # Flush function - writes buffer to time-partitioned S3 key
  flush <- function(force = FALSE) {
    if (length(buffer) == 0) {
      return(invisible(NULL))
    }

    # Create time-partitioned key
    timestamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
    key <- paste0(bc$key_prefix, "-", timestamp, ".log")

    # Combine buffer contents
    content <- paste(buffer, collapse = "\n")

    # Upload to S3
    tryCatch({
      do.call(aws.s3::put_object,
              c(list(file = charToRaw(paste0(content, "\n")),
                     object = key,
                     bucket = bc$bucket,
                     region = bc$region),
                bc$extra_args))

      # Clear buffer on success
      buffer <<- character(0)
    }, error = function(e) {
      warning("S3 flush failed for key '", key, "': ",
              conditionMessage(e), call. = FALSE)
    })

    invisible(NULL)
  }

  # Create receiver with buffer
  recv <- receiver(function(event) {
    # Level filtering
    if (!is.null(config$lower) &&
        event$level_number < attr(config$lower, "level_number")) {
      return(invisible(NULL))
    }
    if (!is.null(config$upper) &&
        event$level_number > attr(config$upper, "level_number")) {
      return(invisible(NULL))
    }

    # Format and add to buffer
    content <- formatter(event)
    buffer <<- c(buffer, content)

    # Auto-flush if threshold reached
    if (length(buffer) >= flush_threshold) {
      flush()
    }

    invisible(NULL)
  })

  # Attach flush function and buffer info as attributes
  attr(recv, "flush") <- flush
  attr(recv, "get_buffer_size") <- function() length(buffer)

  recv
}

# Build Azure receiver with buffering and Append Blobs
.build_azure_receiver <- function(formatter, config) {
  bc <- config$backend_config

  # Check package availability
  if (!requireNamespace("AzureStor", quietly = TRUE)) {
    stop("Package 'AzureStor' required for Azure backend.\n",
         "  Solution: Install with install.packages('AzureStor')\n",
         "  Or: Use on_local() for local file logging instead")
  }

  # Initialize buffer and state
  buffer <- character(0)
  flush_threshold <- bc$flush_threshold
  blob_initialized <- FALSE

  # Get container reference (cached)
  cont <- NULL
  get_container <- function() {
    if (is.null(cont)) {
      cont <<- AzureStor::blob_container(bc$endpoint, bc$container)
    }
    cont
  }

  # Initialize append blob if needed
  initialize_blob <- function() {
    if (blob_initialized) return(invisible(NULL))

    tryCatch({
      container <- get_container()

      # Check if blob exists
      blob_exists <- tryCatch({
        AzureStor::list_blobs(container, info = "name")
        blob_list <- AzureStor::list_blobs(container, info = "name")
        bc$blob %in% blob_list$name
      }, error = function(e) FALSE)

      # Create append blob if it doesn't exist
      if (!blob_exists) {
        AzureStor::create_blob(container,
                               bc$blob,
                               type = "AppendBlob")
      }

      blob_initialized <<- TRUE
    }, error = function(e) {
      warning("Failed to initialize Azure append blob: ",
              conditionMessage(e), call. = FALSE)
    })

    invisible(NULL)
  }

  # Flush function - appends buffer to Azure Append Blob
  flush <- function(force = FALSE) {
    if (length(buffer) == 0) {
      return(invisible(NULL))
    }

    # Ensure blob is initialized
    initialize_blob()

    # Combine buffer contents
    content <- paste(buffer, collapse = "\n")
    content_with_newline <- paste0(content, "\n")

    # Append to blob
    tryCatch({
      container <- get_container()

      # Write to temporary file (AzureStor requires file or raw connection)
      tmp <- tempfile()
      on.exit(unlink(tmp), add = TRUE)

      writeLines(content, tmp, sep = "\n")

      # Append block to blob
      AzureStor::upload_to_url(
        paste0(AzureStor::blob_url(container, bc$blob), "?comp=appendblock"),
        tmp,
        headers = c(
          "x-ms-blob-type" = "AppendBlob"
        ),
        put_md5 = FALSE
      )

      # Clear buffer on success
      buffer <<- character(0)
    }, error = function(e) {
      warning("Azure flush failed for blob '", bc$blob, "': ",
              conditionMessage(e), call. = FALSE)
    })

    invisible(NULL)
  }

  # Create receiver with buffer
  recv <- receiver(function(event) {
    # Level filtering
    if (!is.null(config$lower) &&
        event$level_number < attr(config$lower, "level_number")) {
      return(invisible(NULL))
    }
    if (!is.null(config$upper) &&
        event$level_number > attr(config$upper, "level_number")) {
      return(invisible(NULL))
    }

    # Format and add to buffer
    content <- formatter(event)
    buffer <<- c(buffer, content)

    # Auto-flush if threshold reached
    if (length(buffer) >= flush_threshold) {
      flush()
    }

    invisible(NULL)
  })

  # Attach flush function and buffer info as attributes
  attr(recv, "flush") <- flush
  attr(recv, "get_buffer_size") <- function() length(buffer)

  recv
}

# Register built-in backends
.register_backend("local", .build_local_receiver)
.register_backend("s3", .build_s3_receiver)
.register_backend("azure", .build_azure_receiver)

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
#'     with_limits(lower = TRACE, upper = HIGHEST)     # Logger: TRACE+ (inclusive)
#' # Result: Shows TRACE+ events, console receiver shows NOTE+ subset
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
