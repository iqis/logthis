# ==============================================================================
# Receiver Core Infrastructure
# ==============================================================================
# Core constructors and backend registry for log receivers.
# This file provides the foundational building blocks for all receiver types.

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
#' @family constructors
#'
#' @seealso [formatter()] for creating formatters, [to_console()] and other to_* functions for built-in receivers
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
# RECEIVER-LEVEL MIDDLEWARE
# ============================================================================

#' Apply middleware to a receiver
#'
#' Applies one or more middleware functions to a specific receiver. Receiver
#' middleware transforms events **after** logger-level middleware and filtering,
#' but **before** the receiver processes them. This enables receiver-specific
#' transformations like differential PII redaction or cost-optimized sampling.
#'
#' Receiver middleware is applied in the order specified. Each middleware receives
#' the event (possibly modified by previous middleware) and can:
#' - Return the event unchanged
#' - Return a modified event
#' - Return NULL to drop the event (short-circuit, receiver won't be called)
#'
#' Execution order:
#' ```
#' Event → Logger Middleware → Logger Filter → Logger Tags →
#'   Receiver 1 Middleware → Receiver 1 Output
#'   Receiver 2 Middleware → Receiver 2 Output
#' ```
#'
#' @param x A log receiver to apply middleware to
#' @param ... One or more middleware functions (created with [middleware()] or
#'   plain functions)
#'
#' @return Receiver with middleware applied
#' @export
#' @family logger_configuration
#'
#' @examples
#' \dontrun{
#' # Different PII redaction per receiver
#' redact_full <- middleware(function(event) {
#'   event$message <- gsub("\\d{3}-\\d{2}-\\d{4}", "***-**-****", event$message)
#'   event
#' })
#'
#' redact_partial <- middleware(function(event) {
#'   event$message <- gsub("(\\d{3}-\\d{2}-)\\d{4}", "\\1****", event$message)
#'   event
#' })
#'
#' logger() %>%
#'   with_receivers(
#'     # Console: full redaction
#'     to_console() %>% with_middleware(redact_full),
#'
#'     # Internal log: partial redaction
#'     to_json() %>% on_local("internal.jsonl") %>%
#'       with_middleware(redact_partial),
#'
#'     # Secure vault: no redaction
#'     to_json() %>% on_s3(bucket = "vault", key = "full.jsonl")
#'   )
#'
#' # Cost optimization: sample before expensive cloud service
#' sample_10pct <- middleware(function(event) {
#'   if (runif(1) > 0.1) return(NULL)
#'   event
#' })
#'
#' logger() %>%
#'   with_receivers(
#'     to_json() %>% on_local("app.jsonl"),  # All events
#'     to_json() %>% on_s3(bucket = "logs", key = "app.jsonl") %>%
#'       with_middleware(sample_10pct)  # Only 10% to cloud (reduce costs)
#'   )
#' }
#'
#' @seealso [middleware()] for creating middleware, [with_middleware.logger()] for logger-level middleware
with_middleware.log_receiver <- function(x, ...) {
  receiver_func <- x
  middleware_fns <- list(...)

  # Validate all are functions
  for (i in seq_along(middleware_fns)) {
    mw <- middleware_fns[[i]]
    if (!is.function(mw)) {
      stop("`with_middleware()` requires function arguments. ",
           "Argument ", i, " is <", class(mw)[1], ">.\n",
           "  Solution: Pass functions created with middleware() or plain functions\n",
           "  Example: to_console() %>% with_middleware(middleware(function(event) event), ...)")
    }
  }

  # Get existing middleware (if any)
  existing_middleware <- attr(receiver_func, "middleware") %||% list()

  # Combine: existing + new
  all_middleware <- c(existing_middleware, middleware_fns)

  # Wrap receiver to apply middleware before execution
  wrapped_func <- function(event) {
    # Apply middleware transformations
    for (mw_fn in all_middleware) {
      event <- mw_fn(event)
      if (is.null(event)) {
        # Middleware short-circuited (dropped event)
        return(invisible(NULL))
      }
    }

    # Call original receiver with transformed event
    receiver_func(event)
  }

  # Preserve class and attach middleware list
  structure(
    wrapped_func,
    class = c("log_receiver", "function"),
    middleware = all_middleware
  )
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
#' @family constructors
#'
#' @seealso [receiver()] for creating receivers, [to_text()], [to_json()], [to_csv()] for built-in formatters, [on_local()], [on_s3()], [on_azure()], [on_webhook()] for handlers
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

# ============================================================================
# INTERNAL: Formatter → Receiver Conversion
# ============================================================================
# Note: .backend_registry, .register_backend(), and .formatter_to_receiver()
# are defined in receiver-handlers.R where backend registrations occur
