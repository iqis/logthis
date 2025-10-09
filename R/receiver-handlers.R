# ==============================================================================
# Receiver Handlers
# ==============================================================================
# Backend handlers that attach storage/transport mechanisms to formatters.
# Handlers configure where formatted log events are sent (local files, S3,
# Azure, webhooks, etc.).

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
#' @param flush_threshold Number of events to buffer before flushing (for buffered formatters like Parquet/Feather)
#' @return Enriched log formatter; <log_formatter>
#' @export
#' @family handlers
#'
#' @seealso [to_text()], [to_json()], [to_csv()], [to_parquet()], [to_feather()] for formatters, [on_s3()], [on_azure()], [on_webhook()] for other handlers
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

  # Validate path parameter
  if (is.null(path)) {
    stop("`path` must be a non-NULL character string\n",
         "  Got: NULL\n",
         "  Solution: Provide a valid file path\n",
         "  Example: to_text() %>% on_local(path = \"app.log\")")
  }

  if (!is.character(path) || length(path) != 1) {
    stop("`path` must be a single character string\n",
         "  Got: ", class(path)[1], " of length ", length(path), "\n",
         "  Solution: Provide a single file path as a character string\n",
         "  Example: to_text() %>% on_local(path = \"app.log\")")
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
#' @seealso [to_text()], [to_json()], [to_csv()], [to_parquet()], [to_feather()] for formatters, [on_local()], [on_azure()], [on_webhook()] for other handlers
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
#' @seealso [to_text()], [to_json()], [to_csv()], [to_parquet()], [to_feather()] for formatters, [on_local()], [on_s3()], [on_webhook()] for other handlers
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
#' @seealso [to_text()], [to_json()], [to_csv()] for formatters, [on_local()], [on_s3()], [on_azure()] for other handlers
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
      # Use rbind to combine data frames
      buffer_df <<- rbind(buffer_df, row_df)
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

