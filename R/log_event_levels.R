#' Log Event Levels
#'
#' Creates a constructor function for log events at a specific level.
#'
#' @param level_class S3 class of the event; <character>
#' @param level_number level number; <integer>
#' @param message The log message when using the returned constructor function.
#'   Supports glue template syntax: `"User {user_id} paid {amount}"`.
#'   Template variables are interpolated from custom fields in `...`.
#' @param ... Additional parameters passed to the log event when using the returned constructor function.
#'   These become custom event fields and are available for template interpolation.
#'   Fields are validated for size and complexity (see Performance Notes).
#'
#' @return log event constructor; <function>
#' @export
#'
#' @section Type Contract:
#' ```
#' log_event_level(level_class: string, level_number: numeric) -> log_event_level
#'   where log_event_level = function(message: string = "", ...) -> log_event
#' ```
#'
#' @section Performance Notes:
#' **Glue interpolation cost is paid for ALL events, even filtered ones.**
#'
#' Example: `DEBUG("User {user_id} logged in", user_id = 123)` interpolates
#' immediately, even if DEBUG level is filtered by logger. This is a
#' trade-off for user-friendly syntax.
#'
#' For high-volume logging, consider:
#' - Using `void_logger()` in production
#' - Setting appropriate logger limits to filter early
#' - Avoiding verbose levels (TRACE, DEBUG) in hot paths
#'
#' **Field validation**: Custom fields are checked for size/complexity to prevent
#' memory issues. Functions, environments, and very large objects will error.
log_event_level <- function(level_class, level_number){

  `if`(!is.character(level_class),
       stop("level_class must be character."))

  `if`(missing(level_class) | is.null(level_class) | is.na(level_class) | level_class == "",
       stop("level_class must be non empty."))

  level_number <- make_level_number(level_number, validate = TRUE)

  structure(
    function(message = "", ...){
      # Capture custom fields
      custom_fields <- list(...)

      # Validate custom fields
      if (length(custom_fields) > 0) {
        for (field_name in names(custom_fields)) {
          field_value <- custom_fields[[field_name]]

          # Reject dangerous types
          if (is.function(field_value)) {
            stop("Custom field '", field_name, "' cannot be a function.\n",
                 "  Solution: Log a description or identifier instead")
          }
          if (is.environment(field_value)) {
            stop("Custom field '", field_name, "' cannot be an environment.\n",
                 "  Solution: Extract specific values from the environment")
          }
          if (inherits(field_value, "connection")) {
            stop("Custom field '", field_name, "' cannot be a connection.\n",
                 "  Solution: Log connection details (host, port) instead")
          }

          # Warn about complex types
          if (is.data.frame(field_value) && nrow(field_value) > 10) {
            warning("Custom field '", field_name, "' is a large data.frame (",
                    nrow(field_value), " rows).\n",
                    "  Consider logging summary statistics instead", call. = FALSE)
          }

          # Check size limits
          if (is.character(field_value)) {
            total_size <- sum(nchar(field_value))
            if (total_size > 10000) {  # 10KB limit
              stop("Custom field '", field_name, "' is too large (",
                   total_size, " characters).\n",
                   "  Solution: Truncate string or log a summary")
            }
          }

          if (is.atomic(field_value) && length(field_value) > 1000) {
            warning("Custom field '", field_name, "' is a large vector (",
                    length(field_value), " elements).\n",
                    "  Consider logging length or summary instead", call. = FALSE)
          }
        }
      }

      # Interpolate message with glue if template syntax present
      if (grepl("\\{[^}]+\\}", message) && length(custom_fields) > 0) {
        message <- glue::glue(message,
                              .envir = list2env(custom_fields, parent = emptyenv()),
                              .open = "{", .close = "}")
      }

      structure(list(message = message,
                     time = Sys.time(),
                     level_class = level_class,
                     level_number = level_number,
                     tags = c(),
                     ...),
                class = c(level_class,
                          "log_event"))
    },
    level_number = level_number,
    level_class = level_class,
    class = c("log_event_level",
              "function"))
}

#' Extract and normalize level number from log_event_level or numeric values
#'
#' Converts log_event_level objects to numeric values, handles rounding and validation
#'
#' @param x A log_event_level object, log_event object, or numeric value
#' @param validate Whether to validate range and warn about rounding (default TRUE for level creation, FALSE for limits)
#' @return Numeric level number, rounded if necessary
#' @keywords internal
make_level_number <- function(x, validate = FALSE) {
  if (inherits(x, "log_event_level")) {
    res <- attr(x, "level_number")
  } else if (inherits(x, "log_event")) {
    res <- x$level_number
  } else if (is.numeric(x)) {
    res <- x
  } else {
    stop("Level must be a log_event_level object, log_event object, or numeric value")
  }
  
  if (validate) {
    if (res < 0 | res > 100) {
      stop("Level number must be within [0, 100].")
    }

    original_res <- res
    res <- round(res)

    if (original_res != res) {
      warning(glue::glue("Level number {{original_res}} is rounded to {{res}}."))
    }
    
    return(structure(res, class = "level_number"))
  } else {
    return(round(res))
  }
}

#' @export
#' @rdname log_event_level
LOWEST <- log_event_level("LOWEST", 0)

#' @export
#' @rdname log_event_level
TRACE <- log_event_level("TRACE", 10)

#' @export
#' @rdname log_event_level
DEBUG <- log_event_level("DEBUG", 20)

#' @export
#' @rdname log_event_level
NOTE <- log_event_level("NOTE", 30)

#' @export
#' @rdname log_event_level
MESSAGE <- log_event_level("MESSAGE", 40)

#' @export
#' @rdname log_event_level
WARNING <- log_event_level("WARNING", 60)

#' @export
#' @rdname log_event_level
ERROR <- log_event_level("ERROR", 80)

#' @export
#' @rdname log_event_level
CRITICAL <- log_event_level("CRITICAL", 90)

#' @export
#' @rdname log_event_level
HIGHEST <- log_event_level("HIGHEST", 100)
