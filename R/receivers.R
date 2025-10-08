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

#' Create a CSV formatter
#'
#' Creates a formatter that converts log events to CSV (Comma-Separated Values) format.
#' Each event becomes one CSV row. Must be paired with a backend via on_*() functions.
#'
#' @section CSV Schema:
#' Standard column order (always present):
#' 1. **time** - Event timestamp (ISO 8601 string)
#' 2. **level** - Event level name (e.g., "WARNING")
#' 3. **level_number** - Numeric level value (e.g., 60)
#' 4. **message** - The log message text
#' 5. **tags** - Pipe-delimited tags (e.g., "api|database" or empty string)
#' 6. **Custom fields** - Dynamically added columns for custom event fields
#'
#' @section CSV Formatting:
#' - **Separator**: Configurable (default: comma)
#' - **Quoting**: Automatic for strings containing separator, quotes, or newlines
#' - **Header row**: Optional, written once at start (default: TRUE)
#' - **Tags**: Collapsed with pipe separator to avoid nested quoting
#' - **NA handling**: Configurable NA string (default: "NA")
#'
#' @param separator Field separator (default: ",")
#' @param quote Quote character (default: "\"")
#' @param headers Write header row (default: TRUE)
#' @param na_string String representation of NA values (default: "NA")
#'
#' @return log formatter; <log_formatter>
#' @export
#' @family formatters
#'
#' @section Type Contract:
#' ```
#' to_csv(separator: string = ",", quote: string = "\"",
#'        headers: logical = TRUE, na_string: string = "NA") -> log_formatter
#'   where log_formatter is enriched by on_*() handlers
#' ```
#'
#' @examples
#' # Basic CSV to local file
#' to_csv() %>% on_local(path = "app.csv")
#'
#' # Tab-separated values
#' to_csv(separator = "\t") %>% on_local(path = "app.tsv")
#'
#' # CSV to S3 (no headers for append to existing file)
#' to_csv(headers = FALSE) %>% on_s3(bucket = "logs", key_prefix = "app")
#'
#' # Custom separator and NA handling
#' to_csv(separator = ";", na_string = "") %>% on_local(path = "app.csv")
to_csv <- function(separator = ",",
                   quote = "\"",
                   headers = TRUE,
                   na_string = "NA") {
  # Validate parameters
  if (!is.character(separator) || length(separator) != 1) {
    stop("`separator` must be a single character string")
  }
  if (!is.character(quote) || length(quote) != 1) {
    stop("`quote` must be a single character string")
  }
  if (!is.logical(headers) || length(headers) != 1) {
    stop("`headers` must be TRUE or FALSE")
  }

  # Track whether we've written headers yet (closure state)
  headers_written <- FALSE

  # Helper function to escape CSV fields
  escape_csv_field <- function(value, sep, quo) {
    if (is.na(value)) {
      return(na_string)
    }

    value_str <- as.character(value)

    # Quote if contains separator, quote, or newline
    needs_quoting <- grepl(paste0("[", sep, quo, "\n\r]"), value_str, fixed = FALSE)

    if (needs_quoting) {
      # Escape quotes by doubling them
      value_str <- gsub(quo, paste0(quo, quo), value_str, fixed = TRUE)
      value_str <- paste0(quo, value_str, quo)
    }

    value_str
  }

  fmt_func <- formatter(function(event) {
    # Standard fields in fixed order
    time_str <- escape_csv_field(as.character(event$time), separator, quote)
    level_str <- escape_csv_field(event$level_class, separator, quote)
    level_num_str <- escape_csv_field(event$level_number, separator, quote)
    message_str <- escape_csv_field(event$message, separator, quote)

    # Tags: pipe-delimited string
    if (!is.null(event$tags) && length(event$tags) > 0) {
      tags_str <- escape_csv_field(paste(event$tags, collapse = "|"), separator, quote)
    } else {
      tags_str <- escape_csv_field("", separator, quote)
    }

    # Custom fields (order by field name for consistency)
    custom_fields <- setdiff(names(event),
                             c("time", "level_class", "level_number",
                               "message", "tags"))
    custom_fields <- sort(custom_fields)  # Alphabetical order

    custom_values <- character(0)
    if (length(custom_fields) > 0) {
      custom_values <- sapply(custom_fields, function(field) {
        field_value <- event[[field]]
        # Only handle atomic single values
        if (is.atomic(field_value) && length(field_value) == 1) {
          escape_csv_field(field_value, separator, quote)
        } else {
          escape_csv_field(NA, separator, quote)  # NA for complex types
        }
      })
    }

    # Build CSV row
    row_values <- c(time_str, level_str, level_num_str, message_str, tags_str, custom_values)
    csv_row <- paste(row_values, collapse = separator)

    # Build header row if needed
    output <- character(0)
    if (headers && !headers_written) {
      header_names <- c("time", "level", "level_number", "message", "tags", custom_fields)
      header_row <- paste(sapply(header_names, function(n) {
        escape_csv_field(n, separator, quote)
      }), collapse = separator)
      output <- c(header_row, csv_row)
      headers_written <<- TRUE  # Update closure state
    } else {
      output <- csv_row
    }

    # Return as single string with newlines
    paste(output, collapse = "\n")
  })

  # Attach config
  attr(fmt_func, "config") <- list(format_type = "csv",
                                    separator = separator,
                                    quote = quote,
                                    headers = headers,
                                    na_string = na_string,
                                    backend = NULL,
                                    backend_config = list(),
                                    lower = NULL,
                                    upper = NULL)

  fmt_func
}

#' Create a Parquet formatter (buffered)
#'
#' Creates a formatter that converts log events to Apache Parquet columnar format.
#' **Requires buffering** - events are accumulated into a data frame and written in
#' batches. Must be paired with a backend via on_*() functions.
#'
#' **Note**: Requires the `arrow` package. Install with `install.packages('arrow')`.
#'
#' @section Parquet Schema:
#' - **time**: timestamp[ms, UTC]
#' - **level**: string
#' - **level_number**: int32
#' - **message**: string
#' - **tags**: list<string> (Arrow list column)
#' - **Custom fields**: Dynamically typed based on first occurrence
#'
#' @section Buffering Behavior:
#' - Events accumulated in memory until `flush_threshold` reached
#' - Handlers (on_local, on_s3, on_azure) detect buffering requirement
#' - Arrow dataset API used for appending to existing files
#' - Compression applied at write time (not during buffering)
#'
#' @param compression Compression codec ("snappy", "gzip", "zstd", "lz4", "none")
#' @return log formatter; <log_formatter>
#' @export
#' @family formatters
#'
#' @section Type Contract:
#' ```
#' to_parquet(compression: string = "snappy") -> log_formatter
#'   where log_formatter is enriched by on_*() handlers
#'   NOTE: This formatter requires buffering (requires_buffering = TRUE)
#' ```
#'
#' @examples
#' \dontrun{
#' # Basic Parquet to local file (with buffering)
#' to_parquet() %>% on_local(path = "app.parquet", flush_threshold = 1000)
#'
#' # Custom compression
#' to_parquet(compression = "zstd") %>%
#'   on_local(path = "app.parquet", flush_threshold = 500)
#'
#' # Parquet to S3 (efficient for analytics)
#' to_parquet(compression = "snappy") %>%
#'   on_s3(bucket = "logs", key_prefix = "events", flush_threshold = 1000)
#' }
to_parquet <- function(compression = "snappy") {
  # Check if arrow is available
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("arrow package is required for to_parquet() but is not installed.\n",
         "  Solution: Install with install.packages('arrow')\n",
         "  Or: Use to_csv() for tabular logging instead")
  }

  # Validate compression
  valid_compression <- c("snappy", "gzip", "zstd", "lz4", "none")
  if (!compression %in% valid_compression) {
    stop("`compression` must be one of: ", paste(valid_compression, collapse = ", "),
         "\n  Got: ", compression)
  }

  fmt_func <- formatter(function(event) {
    # Convert event to single-row data frame
    # Arrow will handle type conversion and list columns

    row_data <- data.frame(
      time = event$time,
      level = event$level_class,
      level_number = as.integer(event$level_number),
      message = event$message,
      stringsAsFactors = FALSE
    )

    # Add tags as list column (Arrow native format)
    if (!is.null(event$tags) && length(event$tags) > 0) {
      row_data$tags <- I(list(event$tags))  # Use I() to preserve list structure
    } else {
      row_data$tags <- I(list(character(0)))
    }

    # Add custom fields
    custom_fields <- setdiff(names(event),
                             c("time", "level_class", "level_number",
                               "message", "tags"))
    for (field in custom_fields) {
      field_value <- event[[field]]
      # Only add atomic values (skip complex types)
      if (is.atomic(field_value) && length(field_value) == 1) {
        row_data[[field]] <- field_value
      }
    }

    row_data
  })

  # Attach config with buffering flag
  attr(fmt_func, "config") <- list(
    format_type = "parquet",
    compression = compression,
    requires_buffering = TRUE,  # IMPORTANT: Handlers must buffer
    backend = NULL,
    backend_config = list(),
    lower = NULL,
    upper = NULL
  )

  fmt_func
}

#' Create a Feather formatter (buffered)
#'
#' Creates a formatter that converts log events to Apache Arrow IPC (Feather) format.
#' **Requires buffering** - events are accumulated into a data frame and written in
#' batches. Optimized for R ↔ Python data exchange.
#'
#' **Note**: Requires the `arrow` package. Install with `install.packages('arrow')`.
#'
#' @section Feather Schema:
#' - **time**: timestamp[ms, UTC]
#' - **level**: string
#' - **level_number**: int32
#' - **message**: string
#' - **tags**: list<string> (Arrow list column)
#' - **Custom fields**: Dynamically typed based on first occurrence
#'
#' @section Buffering Behavior:
#' - Events accumulated in memory until `flush_threshold` reached
#' - Handlers (on_local, on_s3, on_azure) detect buffering requirement
#' - Arrow IPC format preserves exact R types for Python interop
#' - Compression applied at write time (not during buffering)
#'
#' @param compression Compression codec ("lz4", "zstd", "none")
#' @return log formatter; <log_formatter>
#' @export
#' @family formatters
#'
#' @section Type Contract:
#' ```
#' to_feather(compression: string = "lz4") -> log_formatter
#'   where log_formatter is enriched by on_*() handlers
#'   NOTE: This formatter requires buffering (requires_buffering = TRUE)
#' ```
#'
#' @examples
#' \dontrun{
#' # Basic Feather to local file (with buffering)
#' to_feather() %>% on_local(path = "app.feather", flush_threshold = 1000)
#'
#' # Custom compression
#' to_feather(compression = "zstd") %>%
#'   on_local(path = "app.feather", flush_threshold = 500)
#'
#' # Feather for Python interop
#' to_feather(compression = "lz4") %>%
#'   on_s3(bucket = "logs", key_prefix = "events", flush_threshold = 1000)
#' }
to_feather <- function(compression = "lz4") {
  # Check if arrow is available
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("arrow package is required for to_feather() but is not installed.\n",
         "  Solution: Install with install.packages('arrow')\n",
         "  Or: Use to_csv() for tabular logging instead")
  }

  # Validate compression (Feather supports fewer options than Parquet)
  valid_compression <- c("lz4", "zstd", "none")
  if (!compression %in% valid_compression) {
    stop("`compression` must be one of: ", paste(valid_compression, collapse = ", "),
         "\n  Got: ", compression)
  }

  fmt_func <- formatter(function(event) {
    # Convert event to single-row data frame (same as Parquet)
    row_data <- data.frame(
      time = event$time,
      level = event$level_class,
      level_number = as.integer(event$level_number),
      message = event$message,
      stringsAsFactors = FALSE
    )

    # Add tags as list column
    if (!is.null(event$tags) && length(event$tags) > 0) {
      row_data$tags <- I(list(event$tags))
    } else {
      row_data$tags <- I(list(character(0)))
    }

    # Add custom fields
    custom_fields <- setdiff(names(event),
                             c("time", "level_class", "level_number",
                               "message", "tags"))
    for (field in custom_fields) {
      field_value <- event[[field]]
      if (is.atomic(field_value) && length(field_value) == 1) {
        row_data[[field]] <- field_value
      }
    }

    row_data
  })

  # Attach config with buffering flag
  attr(fmt_func, "config") <- list(
    format_type = "feather",
    compression = compression,
    requires_buffering = TRUE,  # IMPORTANT: Handlers must buffer
    backend = NULL,
    backend_config = list(),
    lower = NULL,
    upper = NULL
  )

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
                     max_files = 5,
                     flush_threshold = 1000) {
  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter created by to_text(), to_json(), etc.\n",
         "  Got: ", class(formatter)[1], "\n",
         "  Solution: Use to_text() or to_json() to create formatter first\n",
         "  Example: to_text() %>% on_local(path = \"app.log\")\n",
         "  See: .claude/decision-tree.md section 4 for formatting options")
  }

  config <- attr(formatter, "config")

  # Validate rotation config (for line-based formats)
  if (!is.null(max_size)) {
    stopifnot(is.numeric(max_size), max_size > 0)
  }
  if (!is.null(max_files)) {
    stopifnot(is.numeric(max_files), max_files > 0)
    max_files <- as.integer(max_files)
  }

  # Validate flush_threshold (for buffered formats like Parquet/Feather)
  if (!is.null(flush_threshold)) {
    stopifnot(is.numeric(flush_threshold), flush_threshold > 0)
    flush_threshold <- as.integer(flush_threshold)
  }

  # Clear file if not appending
  if (!append && file.exists(path)) {
    unlink(path)
  }

  # Enrich config with handler info
  config$backend <- "local"
  config$backend_config <- list(
    path = path,
    append = append,
    max_size = max_size,
    max_files = max_files,
    flush_threshold = flush_threshold
  )

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

#' Attach webhook (HTTP) handler to formatter
#'
#' Configures a formatter to POST formatted log events to an HTTP endpoint.
#' Supports custom headers, authentication, and retry logic. Works with any
#' formatter (text, JSON, CSV, etc.).
#'
#' **Note**: Requires the `httr2` package. Install with `install.packages('httr2')`.
#'
#' @section HTTP Behavior:
#' - Each event is formatted and sent immediately (no buffering by default)
#' - Uses POST method by default (configurable via `method`)
#' - Automatic retry with exponential backoff (configurable via `max_tries`)
#' - Timeout: 30 seconds default (configurable via `timeout_seconds`)
#' - Failed requests logged as warnings (does not crash receiver)
#'
#' @section Authentication:
#' Pass auth via custom headers:
#' - Bearer token: `headers = list(Authorization = "Bearer YOUR_TOKEN")`
#' - API key: `headers = list("X-API-Key" = "YOUR_KEY")`
#' - Basic auth: Use httr2::req_auth_basic() in future (not yet supported)
#'
#' @param formatter A log formatter from to_text(), to_json(), etc.
#' @param url HTTP endpoint URL (full URL including protocol)
#' @param method HTTP method (default: "POST")
#' @param headers Named list of HTTP headers (e.g., `list(Authorization = "Bearer token")`)
#' @param content_type Content-Type header (default: "text/plain" for to_text(), "application/json" for to_json())
#' @param timeout_seconds Request timeout in seconds (default: 30)
#' @param max_tries Maximum number of retry attempts (default: 3)
#' @param ... Additional arguments (reserved for future use)
#' @return Enriched log formatter; <log_formatter>
#' @export
#' @family handlers
#'
#' @section Type Contract:
#' ```
#' on_webhook(formatter: log_formatter, url: string, method: string = "POST",
#'            headers: list = NULL, content_type: string = NULL,
#'            timeout_seconds: numeric = 30, max_tries: numeric = 3) -> log_formatter
#' ```
#'
#' @examples
#' \dontrun{
#' # Basic webhook (text format)
#' to_text() %>% on_webhook(url = "https://example.com/logs")
#'
#' # JSON to webhook with auth
#' to_json() %>% on_webhook(
#'   url = "https://api.example.com/events",
#'   headers = list(Authorization = "Bearer YOUR_TOKEN"),
#'   max_tries = 5
#' )
#'
#' # Microsoft Teams (use to_teams() instead for MessageCard format)
#' to_json() %>% on_webhook(
#'   url = "https://outlook.office.com/webhook/...",
#'   content_type = "application/json"
#' )
#'
#' # Use in logger
#' log_this <- logger() %>%
#'   with_receivers(
#'     to_console(),
#'     to_json() %>% on_webhook(url = "https://logs.example.com/ingest")
#'   )
#' }
on_webhook <- function(formatter,
                       url,
                       method = "POST",
                       headers = NULL,
                       content_type = NULL,
                       timeout_seconds = 30,
                       max_tries = 3,
                       ...) {
  if (!inherits(formatter, "log_formatter")) {
    stop("`formatter` must be a log_formatter created by to_text(), to_json(), etc.\n",
         "  Got: ", class(formatter)[1], "\n",
         "  Solution: Use to_text() or to_json() to create formatter first\n",
         "  Example: to_json() %>% on_webhook(url = \"https://example.com/logs\")")
  }

  # Validate URL
  if (!is.character(url) || length(url) != 1 || url == "") {
    stop("`url` must be a non-empty character string")
  }

  # Validate URL format (basic check)
  if (!grepl("^https?://", url, ignore.case = TRUE)) {
    stop("`url` must start with http:// or https://\n",
         "  Got: ", url, "\n",
         "  Example: https://example.com/webhook")
  }

  # Validate method
  valid_methods <- c("POST", "PUT", "PATCH")
  method <- toupper(method)
  if (!method %in% valid_methods) {
    stop("`method` must be one of: ", paste(valid_methods, collapse = ", "), "\n",
         "  Got: ", method)
  }

  # Validate timeout
  if (!is.numeric(timeout_seconds) || timeout_seconds <= 0) {
    stop("`timeout_seconds` must be a positive number")
  }

  # Validate max_tries
  if (!is.numeric(max_tries) || max_tries < 1) {
    stop("`max_tries` must be >= 1")
  }

  # Auto-detect content_type from formatter if not specified
  if (is.null(content_type)) {
    format_type <- attr(formatter, "config")$format_type
    content_type <- switch(format_type,
                           "text" = "text/plain",
                           "json" = "application/json",
                           "text/plain")  # default
  }

  config <- attr(formatter, "config")

  config$backend <- "webhook"
  config$backend_config <- list(
    url = url,
    method = method,
    headers = headers,
    content_type = content_type,
    timeout_seconds = timeout_seconds,
    max_tries = as.integer(max_tries),
    extra_args = list(...)
  )

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
  # Check if formatter requires buffering (Parquet/Feather)
  if (isTRUE(config$requires_buffering)) {
    return(.build_buffered_local_receiver(formatter, config))
  }

  # Standard line-by-line receiver (text/JSON/CSV)
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

# Build buffered local filesystem receiver (for Parquet/Feather)
.build_buffered_local_receiver <- function(formatter, config) {
  bc <- config$backend_config
  format_type <- config$format_type

  # Check if arrow package is available
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("Package 'arrow' required for ", format_type, " format.\n",
         "  Solution: Install with install.packages('arrow')\n",
         "  Or: Use to_csv() or to_json() instead")
  }

  # Initialize buffer (data frame accumulator)
  buffer_df <- NULL
  flush_threshold <- bc$flush_threshold %||% 1000  # Default to 1000 events

  # Flush function - writes accumulated data frame to file
  flush <- function(force = FALSE) {
    if (is.null(buffer_df) || nrow(buffer_df) == 0) {
      return(invisible(NULL))
    }

    tryCatch({
      # Convert to Arrow Table for writing
      arrow_table <- arrow::as_arrow_table(buffer_df)

      if (format_type == "parquet") {
        # Write Parquet file
        if (file.exists(bc$path) && isTRUE(bc$append)) {
          # Append to existing Parquet file using dataset API
          existing_ds <- arrow::open_dataset(bc$path, format = "parquet")
          combined <- rbind(
            as.data.frame(existing_ds),
            buffer_df
          )
          arrow::write_parquet(
            combined,
            bc$path,
            compression = config$compression
          )
        } else {
          # Write new file
          arrow::write_parquet(
            arrow_table,
            bc$path,
            compression = config$compression
          )
        }
      } else if (format_type == "feather") {
        # Write Feather file
        if (file.exists(bc$path) && isTRUE(bc$append)) {
          # Feather doesn't support direct append, so read + combine + write
          existing_df <- arrow::read_feather(bc$path)
          combined <- rbind(existing_df, buffer_df)
          arrow::write_feather(
            combined,
            bc$path,
            compression = config$compression
          )
        } else {
          # Write new file
          arrow::write_feather(
            arrow_table,
            bc$path,
            compression = config$compression
          )
        }
      }

      # Clear buffer on success
      buffer_df <<- NULL

    }, error = function(e) {
      warning("Buffered write failed for ", bc$path, ": ",
              conditionMessage(e), call. = FALSE)
    })

    invisible(NULL)
  }

  # Create receiver with buffering
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

    # Format event (returns single-row data frame)
    row_df <- formatter(event)

    # Add to buffer
    if (is.null(buffer_df)) {
      buffer_df <<- row_df
    } else {
      # Use bind_rows for robust column merging
      buffer_df <<- tryCatch({
        dplyr::bind_rows(buffer_df, row_df)
      }, error = function(e) {
        # Fallback to rbind if dplyr not available
        rbind(buffer_df, row_df)
      })
    }

    # Auto-flush if threshold reached
    if (nrow(buffer_df) >= flush_threshold) {
      flush()
    }

    invisible(NULL)
  })

  # Attach flush function and buffer info as attributes
  attr(recv, "flush") <- flush
  attr(recv, "get_buffer_size") <- function() {
    if (is.null(buffer_df)) 0 else nrow(buffer_df)
  }

  recv
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

# Build webhook (HTTP) receiver
.build_webhook_receiver <- function(formatter, config) {
  bc <- config$backend_config

  # Check package availability
  if (!requireNamespace("httr2", quietly = TRUE)) {
    stop("Package 'httr2' required for webhook backend.\n",
         "  Solution: Install with install.packages('httr2')\n",
         "  Or: Use on_local() for local file logging instead")
  }

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

    # Format event
    content <- formatter(event)

    # Build HTTP request using httr2
    tryCatch({
      req <- httr2::request(bc$url)

      # Set method
      req <- switch(bc$method,
                    "POST" = httr2::req_method(req, "POST"),
                    "PUT" = httr2::req_method(req, "PUT"),
                    "PATCH" = httr2::req_method(req, "PATCH"),
                    httr2::req_method(req, "POST"))  # default

      # Set body and content-type
      req <- httr2::req_body_raw(req, charToRaw(content))
      req <- httr2::req_headers(req, `Content-Type` = bc$content_type)

      # Add custom headers
      if (!is.null(bc$headers) && length(bc$headers) > 0) {
        req <- httr2::req_headers(req, !!!bc$headers)
      }

      # Set timeout
      req <- httr2::req_timeout(req, bc$timeout_seconds)

      # Set retry policy (exponential backoff)
      if (bc$max_tries > 1) {
        req <- httr2::req_retry(req,
                                max_tries = bc$max_tries,
                                is_transient = function(resp) {
                                  # Retry on 5xx errors and network errors
                                  httr2::resp_status(resp) >= 500
                                })
      }

      # Perform request
      resp <- httr2::req_perform(req)

      # Check response (2xx = success)
      if (httr2::resp_status(resp) < 200 || httr2::resp_status(resp) >= 300) {
        warning("Webhook request failed with status ", httr2::resp_status(resp),
                " for URL: ", bc$url, call. = FALSE)
      }

    }, error = function(e) {
      warning("Webhook request failed for URL '", bc$url, "': ",
              conditionMessage(e), call. = FALSE)
    })

    invisible(NULL)
  })
}

# Register built-in backends
.register_backend("local", .build_local_receiver)
.register_backend("s3", .build_s3_receiver)
.register_backend("azure", .build_azure_receiver)
.register_backend("webhook", .build_webhook_receiver)

# ============================================================================
# Standalone Receivers (not formatter/handler pattern)
# ============================================================================

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
      warning("Failed to open syslog connection (", transport, "): ",
              conditionMessage(e), call. = FALSE)
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
      warning("Syslog write failed: ", conditionMessage(e), call. = FALSE)
      # Try to reconnect on next event
      if (!is.null(conn)) {
        try(close(conn), silent = TRUE)
        conn <<- NULL
      }
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

        # Map log level to shinyalert type (info, success, warning, error)
        alert_type <- get_shiny_type(event$level_number, "shinyalert")
        shinyalert::shinyalert(text = event$message,
                               type = alert_type,
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

        # Map log level to shiny notification type (default, message, warning, error)
        notif_type <- get_shiny_type(event$level_number, "notif")
        shiny::showNotification(event$message,
                                type = notif_type,
                                ...)
      }
      invisible(NULL)
    })
}

# ==============================================================================
# Async Receiver Wrapper (v0.2.0)
# ==============================================================================
# General async wrapper using mirai for non-blocking, high-throughput scenarios
# Based on research in docs/async-logging-research.md

#' Make any receiver asynchronous using mirai
#'
#' Wraps a receiver to process events asynchronously in a background R process.
#' Events are buffered and flushed in batches for performance. Works with ANY
#' receiver - formatters, handlers, or standalone receivers.
#'
#' @param receiver A log_receiver to wrap (created with \code{receiver()})
#' @param flush_threshold Number of events to buffer before flushing (default: 100)
#' @param max_queue_size Maximum queue size before blocking (default: 10000)
#'
#' @details
#' The first call to \code{as_async()} automatically initializes one mirai daemon
#' if none exist. For better performance with multiple async receivers, create a
#' daemon pool before setting up loggers:
#'
#' \code{mirai::daemons(4)}  # Pool of 4 background workers
#'
#' All async receivers share the daemon pool. This prevents slow receivers
#' (e.g., S3 uploads) from blocking fast receivers (e.g., local files).
#'
#' Events are buffered in memory until \code{flush_threshold} is reached, then
#' sent to the daemon for processing. Remaining events are flushed automatically
#' when the receiver is garbage collected.
#'
#' @section Backpressure:
#' If the queue reaches \code{max_queue_size}, the receiver will flush
#' synchronously and warn the user. This prevents memory exhaustion when the
#' daemon cannot keep up with event production.
#'
#' @section Performance:
#' - **Latency**: 0.1-1ms to queue (vs 10-50ms for synchronous writes)
#' - **Throughput**: 10,000-50,000 events/sec
#' - **Memory**: ~1KB per queued event
#'
#' @section Trade-offs:
#' - **Pros**: Non-blocking, high throughput, minimal latency impact
#' - **Cons**: Events may be lost if process crashes before flush,
#'   requires mirai package, slightly higher memory usage
#'
#' @return A log_receiver that processes events asynchronously
#'
#' @examples
#' \dontrun{
#' # Auto-init with 1 daemon (simple)
#' logger() %>%
#'   with_receivers(
#'     to_text() %>% on_local("app.log") %>% as_async()
#'   )
#'
#' # Daemon pool for multiple async receivers (recommended)
#' mirai::daemons(4)
#' logger() %>%
#'   with_receivers(
#'     to_text() %>% on_local("app.log") %>% as_async(),
#'     to_json() %>% on_s3("logs", "events") %>% as_async(flush_threshold = 1000),
#'     to_csv() %>% on_local("metrics.csv") %>% as_async(),
#'     to_teams(webhook_url = "...") %>% as_async(),
#'     to_syslog(host = "syslog.local") %>% as_async()
#'   )
#'
#' # Works with any receiver!
#' to_console() %>% as_async()  # Even console (though not recommended)
#'
#' # Cleanup (optional - happens automatically on exit)
#' mirai::daemons(0)
#' }
#'
#' @family receivers
#' @export
as_async <- function(receiver,
                     flush_threshold = 100,
                     max_queue_size = 10000) {

  if (!inherits(receiver, "log_receiver")) {
    stop("`receiver` must be a log_receiver (created with receiver())")
  }

  if (!requireNamespace("mirai", quietly = TRUE)) {
    stop("Package 'mirai' required for async logging.\n",
         "  Install with: install.packages('mirai')")
  }

  # Auto-initialize one daemon if none exist
  if (mirai::daemons()$n == 0) {
    mirai::daemons(1, dispatcher = FALSE)
  }

  # Closure state for buffering
  event_queue <- list()
  queue_size <- 0

  # Flush buffered events to daemon
  flush <- function() {
    if (length(event_queue) == 0) return(invisible(NULL))

    # Capture queue locally
    events_batch <- event_queue
    event_queue <<- list()
    queue_size <<- 0

    # Send to daemon (non-blocking!)
    mirai::mirai({
      for (evt in events_batch) {
        receiver_func(evt)
      }
      invisible(NULL)
    }, events_batch = events_batch,
       receiver_func = receiver)

    invisible(NULL)
  }

  # Wrapped receiver
  async_recv <- receiver(function(event) {
    # Backpressure: block if queue is full
    if (queue_size >= max_queue_size) {
      warning("Async log queue full (", max_queue_size, " events). ",
              "Flushing synchronously to prevent memory exhaustion.",
              call. = FALSE)
      flush()
      # Wait briefly for daemon to catch up
      Sys.sleep(0.01)
    }

    # Add event to queue
    event_queue <<- c(event_queue, list(event))
    queue_size <<- queue_size + 1

    # Flush if threshold reached
    if (length(event_queue) >= flush_threshold) {
      flush()
    }

    invisible(NULL)
  })

  # Cleanup finalizer - flush remaining events on GC
  reg.finalizer(environment(async_recv), function(env) {
    if (exists("flush", envir = env, inherits = FALSE)) {
      env$flush()
      Sys.sleep(0.1)  # Give daemon time to write
    }
  }, onexit = TRUE)

  async_recv
}


#' @rdname as_async
#' @export
deferred <- as_async


# Internal helper to stop all mirai daemons on package unload
.stop_async_daemons <- function() {
  if (requireNamespace("mirai", quietly = TRUE)) {
    if (mirai::daemons()$n > 0) {
      mirai::daemons(0)  # Stop all daemons
    }
  }
}
