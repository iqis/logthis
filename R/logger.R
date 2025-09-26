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
#' log_file <- logger() %>% with_receivers(to_identity()) # placeholder for file logger
#' 
#' # Chain loggers: event goes through both
#' WARNING("Database error") %>% 
#'     log_console() %>% 
#'     log_file()
#'     
#' # Scope-based logger masking
#' process_data <- function() {
#'     # Add file logging in this scope only  
#'     log_this <- log_this %>% with_receivers(to_identity()) # add file receiver
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
                receiver_calls = list()))
}

#' @export
#' @rdname logger
dummy_logger <- function(){
  structure(function(event, ...){
    invisible(event)
  },
  class = c("logger",
            "function"),
  config = list(limits = list(lower = 0,
                              upper = 120),
                receivers = list(),
                receiver_calls = list()))
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
#'         with_receivers(to_identity()) # represents file logger
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
#' @param lower lower limit (inclusive); <numeric> | <log_event_level>
#' @param upper upper limit (inclusive); <numeric> | <log_event_level>
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

with_limits.log_receiver <- function(x, lower, upper, ...){
  log_receiver <- x





}


# TODO:
# with_tags() associates tags with log events.
# This can be done to log event levels and receivers, too.
with_tags <- function(x, ...){
  UseMethod("with_tags", x)
}

with_tags.log_event <- function(x, ..., append = TRUE){
  log_event <- x
  tags <- unlist(list(...))

  old_tags <- attr(log_event, "tags")

  if (append) {
    new_tags <- c(old_tags, tags)
  } else {
    new_tags <- tags
  }

  attr(log_event,  "tags") <- new_tags

  log_event
}

with_tags.log_event_level <- function(x, ..., append = TRUE){

  # automatically give every event the tags

}


with_tags.logger <- function(x, ..., append = TRUE){

  # automatically give every event the tags, configure only, implement in logger

  logger <- x
  if (!inherits(logger, "logger")) {
    stop("Argument `logger` must be of type 'logger'. ")
  }

  tags <- unlist(list(...))

  if (length(tags) == 0) {
    warning("`...` (tags) is not supplied.")
  }

  purrr::map(tags,
             ~ {if (!inherits(., "character")) {
               stop("Argument `...` (tags) must be of type 'character'")
             }})

  config <- attr(logger, "config")
  if (append) {
    config$tags <- c(config$tags, tags)
  } else {
    config$tags <- tags
  }
  attr(logger, "config") <- config

  logger


}
