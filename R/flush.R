#' Flush buffered cloud receivers
#'
#' Manually flush buffered events in cloud storage receivers (S3, Azure).
#' Can flush all receivers, specific receivers by name, or by index.
#'
#' Cloud receivers (S3, Azure) buffer events in memory before writing to storage.
#' This function forces immediate write of all buffered events. Useful before
#' program termination or at critical checkpoints.
#'
#' @param x A logger object
#' @param receivers Character vector of receiver names, or integer vector of indices.
#'   If NULL (default), flushes all receivers that support flushing.
#' @param ... Additional arguments (unused)
#'
#' @return The logger object invisibly (for chaining)
#' @export
#' @family logger_configuration
#'
#' @section Type Contract:
#' ```
#' flush(logger, receivers: character | integer | NULL = NULL) -> logger
#' ```
#'
#' @examples
#' \dontrun{
#' # Flush all buffered receivers
#' log_this <- logger() %>%
#'   with_receivers(
#'     s3 = to_json() %>% on_s3(bucket = "logs", key_prefix = "app"),
#'     azure = to_text() %>% on_azure(container = "logs", blob = "app.log")
#'   )
#'
#' flush(log_this)  # Flushes both s3 and azure
#'
#' # Flush specific receiver by name
#' flush(log_this, receivers = "s3")
#' flush(log_this, receivers = c("s3", "azure"))
#'
#' # Flush by index
#' flush(log_this, receivers = 1)
#'
#' # Register automatic flush on exit
#' on.exit(flush(log_this), add = TRUE)
#' }
flush <- function(x, ...) {
  UseMethod("flush")
}

#' @exportS3Method
#' @rdname flush
flush.logger <- function(x, receivers = NULL, ...) {
  logger <- x
  config <- attr(logger, "config")
  receiver_list <- config$receivers
  receiver_names <- config$receiver_names

  if (length(receiver_list) == 0) {
    return(invisible(logger))
  }

  # Determine which receivers to flush
  if (is.null(receivers)) {
    # Flush all receivers that support it
    indices <- seq_along(receiver_list)
  } else if (is.character(receivers)) {
    # Flush by name
    if (is.null(receiver_names) || length(receiver_names) == 0) {
      stop("Logger has no named receivers. Use numeric indices instead.")
    }
    indices <- match(receivers, receiver_names)
    missing <- which(is.na(indices))
    if (length(missing) > 0) {
      stop("Receiver(s) not found: ", paste(receivers[missing], collapse = ", "), "\n",
           "  Available: ", paste(receiver_names, collapse = ", "))
    }
  } else if (is.numeric(receivers)) {
    # Flush by index
    indices <- as.integer(receivers)
    if (any(indices < 1 | indices > length(receiver_list))) {
      stop("Receiver index out of bounds: ", max(indices), " (max: ", length(receiver_list), ")")
    }
  } else {
    stop("`receivers` must be NULL, character vector of names, or numeric vector of indices")
  }

  # Flush selected receivers
  flushed_count <- 0
  for (i in indices) {
    recv <- receiver_list[[i]]
    flush_fn <- attr(recv, "flush")

    if (!is.null(flush_fn)) {
      tryCatch({
        flush_fn()
        flushed_count <- flushed_count + 1
      }, error = function(e) {
        recv_label <- if (!is.null(receiver_names) && i <= length(receiver_names)) {
          receiver_names[i]
        } else {
          paste0("receiver ", i)
        }
        warning("Failed to flush receiver '", recv_label, "': ",
                conditionMessage(e), call. = FALSE)
      })
    }
  }

  invisible(logger)
}

#' Get receiver from logger by name or index
#'
#' Retrieve a specific receiver from a logger for inspection or direct manipulation.
#' Useful for accessing receiver-specific functions like flush() or get_buffer_size().
#'
#' @param logger A logger object
#' @param receiver Receiver name (character) or index (integer). Default: 1
#'
#' @return The receiver function
#' @export
#' @family logger_configuration
#'
#' @section Type Contract:
#' ```
#' get_receiver(logger, receiver: character | integer = 1) -> log_receiver
#' ```
#'
#' @examples
#' \dontrun{
#' log_this <- logger() %>%
#'   with_receivers(s3 = to_json() %>% on_s3(bucket = "logs", key_prefix = "app"))
#'
#' # Get receiver by name
#' recv <- get_receiver(log_this, "s3")
#' attr(recv, "get_buffer_size")()
#'
#' # Get receiver by index
#' recv <- get_receiver(log_this, 1)
#'
#' # Manual flush
#' attr(recv, "flush")()
#' }
get_receiver <- function(logger, receiver = 1) {
  config <- attr(logger, "config")
  receiver_list <- config$receivers
  receiver_names <- config$receiver_names

  if (is.character(receiver)) {
    if (is.null(receiver_names) || length(receiver_names) == 0) {
      stop("Logger has no named receivers")
    }
    idx <- match(receiver, receiver_names)
    if (is.na(idx)) {
      stop("Receiver '", receiver, "' not found. Available: ",
           paste(receiver_names, collapse = ", "))
    }
  } else if (is.numeric(receiver)) {
    idx <- as.integer(receiver)
    if (idx < 1 || idx > length(receiver_list)) {
      stop("Index out of bounds: ", idx, " (max: ", length(receiver_list), ")")
    }
  } else {
    stop("`receiver` must be character (name) or numeric (index)")
  }

  receiver_list[[idx]]
}

#' Get buffer status for cloud receivers
#'
#' Returns the number of buffered (unflushed) events for each receiver that
#' supports buffering (S3, Azure). Non-buffered receivers return NA.
#'
#' @param logger A logger object
#'
#' @return Named numeric vector of buffer sizes, or NULL if no buffered receivers.
#'   Names correspond to receiver names. NA values indicate non-buffered receivers.
#' @export
#' @family logger_configuration
#'
#' @section Type Contract:
#' ```
#' buffer_status(logger) -> named numeric vector | NULL
#' ```
#'
#' @examples
#' \dontrun{
#' log_this <- logger() %>%
#'   with_receivers(
#'     console = to_console(),
#'     s3 = to_json() %>% on_s3(bucket = "logs", key_prefix = "app")
#'   )
#'
#' # Log some events
#' log_this(NOTE("Event 1"))
#' log_this(NOTE("Event 2"))
#'
#' # Check buffer status
#' buffer_status(log_this)
#' # console     s3
#' #      NA      2
#' }
buffer_status <- function(logger) {
  config <- attr(logger, "config")
  receiver_list <- config$receivers
  receiver_names <- config$receiver_names

  if (length(receiver_list) == 0) {
    return(NULL)
  }

  sizes <- integer(length(receiver_list))
  names(sizes) <- receiver_names

  for (i in seq_along(receiver_list)) {
    recv <- receiver_list[[i]]
    get_size_fn <- attr(recv, "get_buffer_size")
    if (!is.null(get_size_fn)) {
      sizes[i] <- get_size_fn()
    } else {
      sizes[i] <- NA_integer_
    }
  }

  # Return all receivers to show which are buffered (non-NA) vs not (NA)
  sizes
}
