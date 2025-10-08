#' Create a logger
#'
#' Creates a logger function that processes log events through configured receivers.
#' Loggers return the log event invisibly, enabling chaining multiple loggers together.
#'
#' @return logger; <logger>
#' @export
#'
#' @section Type Contract:
#' ```
#' logger() -> logger
#'   where logger = function(log_event, ...) -> log_event
#' ```
#'
#' @examples
#'
#' # Basic logger
#' log_this <- logger()
#' 
#' # Configure with receivers
#' log_this <- logger() %>%
#'     with_receivers(to_console()) %>%
#'     with_limits(lower = NOTE, upper = HIGHEST)
#' 
#' # Chain multiple loggers together
#' log_console <- logger() %>% with_receivers(to_console())
#' log_file <- logger() %>% with_receivers(to_text() %>% on_local(path = "app.log"))
#'
#' # Chain loggers: event goes through both
#' WARNING("Database error") %>%
#'     log_console() %>%
#'     log_file()
#'
#' # Scope-based logger masking
#' process_data <- function() {
#'     # Add file logging in this scope only
#'     log_this <- log_this %>% with_receivers(to_text() %>% on_local(path = "process.log"))
#'
#'     log_this(NOTE("Starting data processing"))
#'     # ... processing logic
#' }
#'
logger <- function(){
  structure(function(event, ...){

    config <- attr(sys.function(),
                   "config")

    # Logger-level filtering: check if event level is within logger limits (inclusive)
    if (event$level_number < config$limits$lower ||
        event$level_number > config$limits$upper) {
      # Event is outside logger limits, return early without processing
      invisible(event)
    } else {
      # Apply logger-level tags to event if configured
      if (!is.null(config$tags) && length(config$tags) > 0) {
        # Combine event tags with logger tags
        event$tags <- c(event$tags, config$tags)
      }

      # Event passes logger filter, send to receivers with error handling
      for (idx in seq_along(config$receivers)) {
        receiver <- config$receivers[[idx]]

        # Execute receiver with error handling
        result <- tryCatch(
          {
            receiver(event = event)
            list(result = NULL, error = NULL)
          },
          error = function(e) {
            list(result = NULL, error = e)
          }
        )

        if (!is.null(result$error)) {
          # Get receiver label for error reporting
          receiver_label <- if (idx <= length(config$receiver_labels)) {
            config$receiver_labels[[idx]]
          } else {
            class(receiver)[1]
          }

          # Create error event and send to console fallback
          error_event <- ERROR(sprintf("Receiver #%d failed: %s\nReceiver: %s",
                                       idx,
                                       conditionMessage(result$error),
                                       receiver_label))
          error_event$tags <- c(error_event$tags, "receiver_error")

          # Use to_console() as fallback to report the receiver failure
          tryCatch(
            to_console()(error_event),
            error = function(e) {
              # Only if to_console() itself fails, use warning
              warning("Logger receiver error AND console fallback failed: ",
                      conditionMessage(e), call. = FALSE)
            }
          )
        }
      }

      # Return the event to enable chaining
      invisible(event)
    }
  },
  class = c("logger",
            "function"),
  config = list(limits = list(lower = 0,
                              upper = 100),
                receivers = list(),
                receiver_labels = list(),
                receiver_names = character(0),
                tags = NULL))
}

#' @export
#' @rdname logger
void_logger <- function(){
  structure(function(event, ...){
    invisible(event)
  },
  class = c("logger",
            "function"),
  config = list(limits = list(lower = 0,
                              upper = 100),
                receivers = list(),
                receiver_labels = list(),
                receiver_names = character(0),
                tags = NULL))
}

#' Add receivers to a logger
#'
#' Adds one or more receivers to a logger. Receivers determine where log events
#' are sent (console, files, alerts, etc.). When append=TRUE (default), new
#' receivers are added to existing ones, enabling incremental logger composition.
#'
#' @param logger a logger; <logger>
#' @param ... receivers; <log_receiver>
#' @param append to append to existing receivers, or to overwrite; <logical>
#'
#' @return logger; <logger>
#' @export
#'
#' @section Type Contract:
#' ```
#' with_receivers(logger, ...: log_receiver | log_formatter, append: logical = TRUE) -> logger
#'   Formatters auto-convert to receivers
#' ```
#'
#' @examples
#'
#' # Basic receiver addition
#' log_this <- logger() %>%
#'     with_receivers(to_console(), to_identity())
#'
#' # Incremental composition (append=TRUE by default)
#' log_this <- logger() %>%
#'     with_receivers(to_console())
#'     
#' # Later, in a child scope, add more receivers
#' process_data <- function() {
#'     # Add file logging to existing console logging
#'     log_this <- log_this %>%
#'         with_receivers(to_text() %>% on_local(path = "data.log"))
#'
#'     log_this(NOTE("Now logs to both console and file"))
#' }
#'
#' # Replace all receivers (append=FALSE)
#' log_this <- log_this %>%
#'     with_receivers(to_console(), append = FALSE)
#'
with_receivers <- function(logger, ..., append = TRUE){
  if (!inherits(logger, "logger")) {
    stop("Argument `logger` must be of type 'logger'.\n",
         "  Solution: Create a logger first with logger() or void_logger()\n",
         "  Example: log_this <- logger() %>% with_receivers(to_console())")
  }

  # Capture the original calls to the receivers
  receiver_calls <- substitute(list(...))[-1]  # Remove the 'list' part
  receivers_or_formatters <- unlist(list(...))  # Flatten nested lists like old behavior

  if (length(receivers_or_formatters) == 0) {
    warning("`...` (receivers) is not supplied.")
  }

  # Auto-convert formatters to receivers
  receivers <- lapply(receivers_or_formatters,
                      function(x) {
                        if (inherits(x, "log_formatter")) {
                          # Convert formatter to receiver
                          .formatter_to_receiver(x)
                        } else if (inherits(x, "log_receiver")) {
                          # Already a receiver
                          x
                        } else {
                          stop("Arguments must be log_receiver or log_formatter.\n",
                               "  Got: ", class(x)[1], "\n",
                               "  Solution: Use receiver functions like to_console(), to_identity(), etc.\n",
                               "  Or: Create formatted receiver with to_text() %>% on_local() pattern\n",
                               "  See: .claude/use-cases.md for examples")
                        }
                      })

  # Convert receiver calls to plain text labels for error reporting
  receiver_labels <- vapply(as.list(receiver_calls),
                            function(x) deparse(x, width.cutoff = 500),
                            character(1))

  # Extract or generate receiver names
  provided_names <- names(list(...))
  if (is.null(provided_names)) {
    provided_names <- character(length(receivers))
  }

  # Generate auto-names for unnamed receivers
  config <- attr(logger, "config")
  existing_count <- if (append) length(config$receivers) else 0

  receiver_names <- character(length(receivers))
  for (i in seq_along(receivers)) {
    if (provided_names[i] == "" || is.na(provided_names[i])) {
      # Auto-generate name
      receiver_names[i] <- paste0("receiver_", existing_count + i)
    } else {
      receiver_names[i] <- provided_names[i]
    }
  }

  # Handle name collisions with existing receivers (if appending)
  if (append && !is.null(config$receiver_names)) {
    existing_names <- config$receiver_names
    for (i in seq_along(receiver_names)) {
      original_name <- receiver_names[i]
      suffix <- 2
      while (receiver_names[i] %in% existing_names) {
        receiver_names[i] <- paste0(original_name, "_", suffix)
        suffix <- suffix + 1
      }
    }
  }

  if (append) {
    config$receivers <- c(config$receivers, receivers)
    # Store receiver labels as plain text for error reporting
    if (is.null(config$receiver_labels)) {
      config$receiver_labels <- receiver_labels
    } else {
      config$receiver_labels <- c(config$receiver_labels, receiver_labels)
    }
    # Append receiver names
    if (is.null(config$receiver_names)) {
      config$receiver_names <- receiver_names
    } else {
      config$receiver_names <- c(config$receiver_names, receiver_names)
    }
  } else {
    config$receivers <- receivers
    config$receiver_labels <- receiver_labels
    config$receiver_names <- receiver_names
  }
  attr(logger, "config") <- config

  logger
}

#' Generic function for setting limits
#' 
#' This is a generic function for setting limits on loggers and receivers.
#' See the specific methods for details.
#' 
#' @param x The object to set limits on
#' @param lower Lower limit
#' @param upper Upper limit
#' @param ... Additional arguments passed to methods
#' @export
with_limits <- function(x, lower, upper, ...){
  UseMethod("with_limits", x)
}

#' Set logger-level limits
#'
#' Sets filtering limits at the logger level. Events with level numbers outside
#' these bounds are dropped entirely before reaching any receivers. This is the
#' first level of filtering - receiver-level filtering happens second.
#'
#' Limits are inclusive: events with level_number >= lower AND <= upper
#' will be processed by the logger.
#'
#' @param logger logger; <logger>
#' Set level limits for logger
#'
#' Configures the logger to only process events within the specified level range.
#'
#' @param x logger object to modify
#' @param lower lower limit (inclusive); <numeric> | <log_event_level>
#' @param upper upper limit (inclusive); <numeric> | <log_event_level>
#' @param ... additional arguments (currently unused)
#'
#' @return logger; <logger>
#' @export
#'
#' @section Type Contract:
#' ```
#' with_limits.logger(logger, lower: numeric | log_event_level = LOWEST,
#'                    upper: numeric | log_event_level = HIGHEST, ...) -> logger
#' ```
#'
#' @examples
#' # Logger-level filtering: only WARNING and ERROR events processed (inclusive)
#' log_this <- logger() %>%
#'     with_receivers(to_console()) %>%
#'     with_limits(lower = WARNING, upper = ERROR)
#'     
#' # Two-level filtering example:
#' # Logger allows NOTE+ events (inclusive), console receiver further filters to WARNING+ (inclusive)
#' log_this <- logger() %>%
#'     with_receivers(to_console(lower = WARNING)) %>%
#'     with_limits(lower = NOTE, upper = HIGHEST)
#'
#' log_this(DEBUG("Blocked by logger"))      # Below logger limit (20 < 30)
#' log_this(NOTE("Blocked by receiver"))     # Passes logger (30 >= 30), blocked by receiver (30 < 60)
#' log_this(WARNING("Reaches console"))      # Passes both filters (60 >= 30 AND 60 >= 60)
#'
with_limits.logger <- function(x, lower = LOWEST, upper = HIGHEST, ...){
  logger <- x

  lower <- make_level_number(lower)
  upper <- make_level_number(upper)

  config <- attr(logger, "config")

  # guard limit values & apply to config if not null
  if (!is.null(lower)) {
    if (lower < 0 | lower > 99) {
      stop(glue::glue("Lower limit must be in [0, 99], got {lower}\n",
                      "  Solution: Use standard levels like LOWEST(0), TRACE(10), DEBUG(20), NOTE(30), etc.\n",
                      "  Or: Use numeric value in range [0, 99]\n",
                      "  See: R/log_event_levels.R for standard levels"))
    }
    config$limits$lower <- lower
  }

  if (!is.null(upper)) {
    if (upper < 1 | upper > 100) {
      stop(glue::glue("Upper limit must be in [1, 100], got {upper}\n",
                      "  Solution: Use standard levels like ERROR(80), CRITICAL(90), HIGHEST(100)\n",
                      "  Or: Use numeric value in range [1, 100]\n",
                      "  See: R/log_event_levels.R for standard levels"))
    }
    config$limits$upper <- upper
  }

  attr(logger, "config") <- config

  logger
}

#' Set receiver-level limits
#'
#' Creates a wrapper receiver that filters events by level before passing them
#' to the original receiver. This provides fine-grained control over which events
#' each receiver processes, independent of logger-level filtering.
#'
#' Receiver-level filtering happens AFTER logger-level filtering. Events must
#' pass both filters to reach the receiver.
#'
#' Limits are inclusive: events with level_number >= lower AND <= upper
#' will be passed to the receiver.
#'
#' @param x receiver object to wrap; <log_receiver>
#' @param lower lower limit (inclusive); <numeric> | <log_event_level>
#' @param upper upper limit (inclusive); <numeric> | <log_event_level>
#' @param ... additional arguments (currently unused)
#'
#' @return wrapped receiver; <log_receiver>
#' @export
#'
#' @examples
#' # Console receiver that only shows WARNING and above
#' warn_console <- to_console() %>%
#'     with_limits(lower = WARNING, upper = HIGHEST)
#'
#' # Multiple receivers with different level filters
#' log_this <- logger() %>%
#'     with_receivers(
#'         to_console() %>% with_limits(lower = WARNING),      # Console: warnings+
#'         to_text() %>% on_local("debug.log") %>% with_limits(lower = TRACE)  # File: everything
#'     )
#'
#' # Two-level filtering example:
#' log_this <- logger() %>%
#'     with_limits(lower = NOTE, upper = HIGHEST) %>%           # Logger: NOTE+
#'     with_receivers(
#'         to_console() %>% with_limits(lower = WARNING),       # Console: WARNING+
#'         to_text() %>% on_local("all.log")                     # File: NOTE+ (from logger)
#'     )
#'
#' log_this(DEBUG("Blocked by logger"))       # Below logger limit
#' log_this(NOTE("Only in file"))             # Passes logger, blocked by console receiver
#' log_this(WARNING("Both outputs"))          # Passes both filters
#'
with_limits.log_receiver <- function(x, lower = LOWEST, upper = HIGHEST, ...){
  original_receiver <- x

  lower_num <- make_level_number(lower)
  upper_num <- make_level_number(upper)

  # Validate limit ranges
  if (lower_num < 0 | lower_num > 99) {
    stop(glue::glue("Lower limit must be in [0, 99], got {lower_num}"))
  }

  if (upper_num < 1 | upper_num > 100) {
    stop(glue::glue("Upper limit must be in [1, 100], got {upper_num}"))
  }

  # Create a wrapper receiver that checks new limits before calling original
  wrapped_receiver <- receiver(
    function(event) {
      # Check if event is within new limits
      if (event$level_number >= lower_num && event$level_number <= upper_num) {
        # Call the original receiver
        original_receiver(event)
      }
      invisible(NULL)
    }
  )

  # Store limits as attributes for introspection/printing
  attr(wrapped_receiver, "lower") <- lower_num
  attr(wrapped_receiver, "upper") <- upper_num
  attr(wrapped_receiver, "original_receiver") <- original_receiver

  wrapped_receiver
}

#' Set formatter-level limits
#'
#' Sets filtering limits on a formatter before it's converted to a receiver.
#' This allows for level filtering to be configured on formatters.
#'
#' @param x A log formatter from to_text(), to_json(), etc.
#' @param lower Lower level limit (inclusive)
#' @param upper Upper level limit (inclusive)
#' @param ... Additional arguments (unused)
#' @return Enriched log formatter; <log_formatter>
#' @export
#' @family formatters
with_limits.log_formatter <- function(x,
                                      lower = LOWEST,
                                      upper = HIGHEST,
                                      ...) {
  formatter <- x
  guard_level_type(lower)
  guard_level_type(upper)

  config <- attr(formatter, "config")
  config$lower <- lower
  config$upper <- upper

  attr(formatter, "config") <- config
  formatter
}


#' Add tags to log events, levels, or loggers
#'
#' Tags provide a flexible categorization system for log events. Tags can be applied
#' at three levels: individual events, event levels (auto-tagging), or loggers
#' (apply to all events). Tags from all three levels are combined when an event
#' is logged.
#'
#' @param x An object to tag: log_event, log_event_level, or logger
#' @param ... Character tags to add
#' @param append Whether to append tags to existing ones (default TRUE) or replace them
#'
#' @return The tagged object (same type as input)
#' @export
#'
#' @section Type Contract:
#' ```
#' with_tags.log_event(log_event, ...: character, append: logical = TRUE) -> log_event
#' with_tags.log_event_level(log_event_level, ...: character, append: logical = TRUE) -> log_event_level
#' with_tags.logger(logger, ...: character, append: logical = TRUE) -> logger
#' ```
#'
#' @examples
#' # Tag individual events
#' event <- NOTE("User login") %>% with_tags("auth", "security")
#'
#' # Create auto-tagged level
#' CRITICAL <- ERROR %>% with_tags("critical", "alert")
#' event <- CRITICAL("System failure")  # Automatically has tags
#'
#' # Tag all logger events
#' log_this <- logger() %>%
#'     with_receivers(to_console()) %>%
#'     with_tags("production", "api-service")
#'
#' # Tag hierarchy: event + level + logger tags are all combined
#' TAGGED_LEVEL <- NOTE %>% with_tags("level_tag")
#' log_tagged <- logger() %>%
#'     with_receivers(to_console()) %>%
#'     with_tags("logger_tag")
#' event <- TAGGED_LEVEL("Message") %>% with_tags("event_tag")
#' log_tagged(event)  # Has all three tags
#'
with_tags <- function(x, ...){
  UseMethod("with_tags", x)
}

#' @exportS3Method
#' @rdname with_tags
with_tags.log_event <- function(x, ..., append = TRUE){
  log_event <- x

  # Validate tags before unlisting to catch type errors
  tag_list <- list(...)
  for (tag in tag_list) {
    if (!is.character(tag)) {
      stop("Tags must be character strings")
    }
  }

  new_tags <- unlist(tag_list)

  # Tags are stored in the list itself, not as attributes
  old_tags <- log_event$tags

  if (append) {
    log_event$tags <- c(old_tags, new_tags)
  } else {
    log_event$tags <- new_tags
  }

  log_event
}

#' @exportS3Method
#' @rdname with_tags
with_tags.log_event_level <- function(x, ..., append = TRUE){
  log_event_level <- x

  # Validate tags before unlisting to catch type errors
  tag_list <- list(...)
  for (tag in tag_list) {
    if (!is.character(tag)) {
      stop("Tags must be character strings")
    }
  }

  new_tags <- unlist(tag_list)

  # Get existing tags from attributes
  old_tags <- attr(log_event_level, "tags")

  # Combine tags
  if (append && !is.null(old_tags)) {
    combined_tags <- c(old_tags, new_tags)
  } else {
    combined_tags <- new_tags
  }

  # Store tags as attribute
  attr(log_event_level, "tags") <- combined_tags

  # Modify the function body to include tags when creating events
  level_class <- attr(log_event_level, "level_class")
  level_number <- attr(log_event_level, "level_number")

  # Create new log_event_level with tags applied
  structure(
    function(message = "", ...){
      structure(list(message = message,
                     time = Sys.time(),
                     level_class = level_class,
                     level_number = level_number,
                     tags = combined_tags,  # Include level tags
                     ...),
                class = c(level_class,
                          "log_event"))
    },
    level_number = level_number,
    level_class = level_class,
    tags = combined_tags,
    class = c("log_event_level",
              "function"))
}

#' @exportS3Method
#' @rdname with_tags
with_tags.logger <- function(x, ..., append = TRUE){
  logger <- x
  if (!inherits(logger, "logger")) {
    stop("Argument `logger` must be of type 'logger'. ")
  }

  # Validate tags before unlisting to catch type errors
  tag_list <- list(...)
  if (length(tag_list) == 0) {
    warning("`...` (tags) is not supplied.")
    return(logger)
  }

  # Check each tag is character before unlisting (to prevent coercion)
  for (tag in tag_list) {
    if (!is.character(tag)) {
      stop("Argument `...` (tags) must be of type 'character'")
    }
  }

  tags <- unlist(tag_list)

  config <- attr(logger, "config")
  if (append) {
    config$tags <- c(config$tags, tags)
  } else {
    config$tags <- tags
  }
  attr(logger, "config") <- config

  logger
}
