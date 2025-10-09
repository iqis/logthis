# ==============================================================================
# Receiver Formatters
# ==============================================================================
# Format converters that transform log events into various output formats.
# Formatters must be paired with handlers (on_local, on_s3, etc.) to create
# complete receivers.

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
#' @seealso [on_local()], [on_s3()], [on_azure()], [on_webhook()] for backend handlers
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
#' @seealso [on_local()], [on_s3()], [on_azure()], [on_webhook()] for backend handlers
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
#' @seealso [on_local()], [on_s3()], [on_azure()], [on_webhook()] for backend handlers, [to_text()], [to_json()] for other line-based formatters
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
#' - **time**: timestamp\[ms, UTC\]
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
#' @seealso [on_local()], [on_s3()], [on_azure()] for backend handlers, [to_feather()] for similar columnar format
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
#' - **time**: timestamp\[ms, UTC\]
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
#' @seealso [on_local()], [on_s3()], [on_azure()] for backend handlers, [to_parquet()] for similar columnar format
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
