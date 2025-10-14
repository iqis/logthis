# ==============================================================================
# Receiver Console and Testing
# ==============================================================================
# Console output receivers and testing utilities (to_identity, to_void).

# Dummy receivers, mainly for testing
#' Identity receiver for testing
#'
#' A receiver that returns the event unchanged. Primarily used for testing
#' purposes to verify that events are being processed correctly.
#'
#' @return A log receiver that returns the log event as-is
#' @family receivers
#' @export
#'
#' @seealso [to_void()] for discarding events, [to_console()] for display
to_identity <- function(){
  receiver(function(event){
    event  # This one returns the event for testing purposes
  })
}

#' @rdname to_identity
#' @export
to_itself <- to_identity

#' Void receiver that discards events
#'
#' A receiver that discards all log events by returning NULL invisibly.
#' Used for testing or when you want to disable logging temporarily.
#'
#' @return A log receiver that discards all events
#' @family receivers
#' @export
#'
#' @seealso [to_identity()] for testing events, [to_console()] for display
to_void <- function(){
  receiver(function(event){
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
#' @family receivers
#'
#' @seealso [to_identity()], [to_void()] for testing receivers, [receiver()] for creating custom receivers
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

