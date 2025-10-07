#' Create a logger
#'
#' Creates a logger function that processes log events through configured receivers.
#' Loggers return the log event invisibly, enabling chaining multiple loggers together.
#'
#' @return logger; <logger>
#' @export
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
#' log_file <- logger() %>% with_receivers(to_text_file(path = "app.log"))
#'
#' # Chain loggers: event goes through both
#' WARNING("Database error") %>%
#'     log_console() %>%
#'     log_file()
#'
#' # Scope-based logger masking
#' process_data <- function() {
#'     # Add file logging in this scope only
#'     log_this <- log_this %>% with_receivers(to_text_file(path = "process.log"))
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

      # Event passes logger filter, send to receivers
      config$receivers %>%
        purrr::walk(purrr::exec, event = event)

      # Return the event to enable chaining
      invisible(event)
    }
  },
  class = c("logger",
            "function"),
  config = list(limits = list(lower = 0,
                              upper = 120),
                receivers = list(),
                receiver_calls = list(),
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
                              upper = 120),
                receivers = list(),
                receiver_calls = list(),
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
#'         with_receivers(to_text_file(path = "data.log"))
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
    stop("Argument `logger` must be of type 'logger'. ")
  }

  # Capture the original calls to the receivers
  receiver_calls <- substitute(list(...))[-1]  # Remove the 'list' part
  receivers <- unlist(list(...))

  if (length(receivers) == 0) {
    warning("`...` (receivers) is not supplied.")
  }

  purrr::map(receivers,
             ~ {if (!inherits(., "log_receiver")) {
               stop("Argument `...` (receivers) must be of type 'log_receiver'")
             }})

  config <- attr(logger, "config")
  if (append) {
    config$receivers <- c(config$receivers, receivers)
    # Also store the receiver calls for printing
    if (is.null(config$receiver_calls)) {
      config$receiver_calls <- receiver_calls
    } else {
      config$receiver_calls <- c(config$receiver_calls, receiver_calls)
    }
  } else {
    config$receivers <- receivers
    config$receiver_calls <- receiver_calls
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
#' log_this(CHATTER("Blocked by logger"))    # Below logger limit (40 < 40)
#' log_this(NOTE("Blocked by receiver"))     # Passes logger (40 >= 40), blocked by receiver (40 < 80)
#' log_this(WARNING("Reaches console"))      # Passes both filters (80 >= 40 AND 80 >= 80)
#'
with_limits.logger <- function(x, lower = LOWEST, upper = HIGHEST, ...){
  logger <- x

  lower <- make_level_number(lower)
  upper <- make_level_number(upper)

  config <- attr(logger, "config")

  # guard limit values & apply to config if not null
  if (!is.null(lower)) {
    if (lower < 0 | lower > 119) {
      stop(glue::glue("Lower limit must be in [0, 119], got {lower}"))
    }
    config$limits$lower <- lower
  }

  if (!is.null(upper)) {
    if (upper < 1 | upper > 120) {
      stop(glue::glue("Upper limit must be in [1, 120], got {upper}"))
    }
    config$limits$upper <- upper
  }

  attr(logger, "config") <- config

  logger
}

#' @export
with_limits.log_receiver <- function(x, lower = LOWEST, upper = HIGHEST, ...){
  original_receiver <- x

  lower_num <- make_level_number(lower)
  upper_num <- make_level_number(upper)

  # Validate limit ranges
  if (lower_num < 0 | lower_num > 119) {
    stop(glue::glue("Lower limit must be in [0, 119], got {lower_num}"))
  }

  if (upper_num < 1 | upper_num > 120) {
    stop(glue::glue("Upper limit must be in [1, 120], got {upper_num}"))
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
  purrr::walk(tag_list,
              ~ {if (!is.character(.)) {
                stop("Tags must be character strings")
              }})

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
  purrr::walk(tag_list,
              ~ {if (!is.character(.)) {
                stop("Tags must be character strings")
              }})

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
  purrr::walk(tag_list,
              ~ {if (!is.character(.)) {
                stop("Argument `...` (tags) must be of type 'character'")
              }})

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
