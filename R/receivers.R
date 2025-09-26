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

# Dummy receivers, mainly for testing
#' @export
to_identity <- function(){
  receiver(function(event){
    event  # This one returns the event for testing purposes
  })
}

#' @export
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
#'     with_limits(lower = CHATTER, upper = HIGHEST)     # Logger: CHATTER+ (inclusive)
#' # Result: Shows CHATTER+ events, console receiver shows NOTE+ subset
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

        log_color <- function(level_number){
          level_color_lookup <-
            tibble::tibble(level_number = seq(0, 100, 20),
                           crayon_f = list(crayon::white,
                                           crayon::silver,
                                           crayon::green,
                                           crayon::yellow,
                                           crayon::red,
                                           purrr::compose(crayon::red, crayon::bold)))
          for (i in 1:nrow(level_color_lookup)) {
            if (level_color_lookup$level_number[i] >= level_number) {
              res <- level_color_lookup$crayon_f[[i]]
              break
            }
          }
          res
        }

        with(event,
             cat(log_color(level_number)(paste0(time, " ",
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

        # TODO: add level lookup table
        shinyalert::shinyalert(text = event$message,
                               type = "error",
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

        # TODO: build event level mapping
        shiny::showNotification(event$message,
                                ...)
      }
      invisible(NULL)
    })
}

#' Text file logging receiver
#'
#' Writes log events to a text file with timestamp and level information.
#' Level limits are inclusive: events with level_number >= lower AND <= upper
#' will be written to the file.
#'
#' @param lower minimum level to log (inclusive, optional); <log_event_level>
#' @param upper maximum level to log (inclusive, optional); <log_event_level>
#' @param path file path for log output; <character>
#' @param append whether to append to existing file; <logical>
#' @param ... additional arguments (unused)
#'
#' @return log receiver function; <log_receiver>
#' @export
#'
#' @examples
#' # Basic file logging
#' file_recv <- to_text_file(path = "app.log")
#' 
#' # Log only errors and above (inclusive)
#' error_file <- to_text_file(lower = ERROR, path = "errors.log")
#' 
#' # Custom file receiver using the receiver() constructor
#' simple_file_logger <- receiver(function(event) {
#'   cat(paste(event$time, event$level_class, event$message), 
#'       file = "simple.log", append = TRUE, sep = "\n")
#'   invisible(NULL)
#' })
#'
to_text_file <- function(lower = LOWEST,
                         upper = HIGHEST,
                         path = "log.txt",
                         append = FALSE, ...){
  stopifnot(is.character(path),
            is.logical(append))

  if (!append) {
    unlink(path)
  }

  con <- file(path)

  receiver(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number <= attr(upper, "level_number")) {

        with(event,
             cat(paste0(time, " ",
                        "[", level_class, "]", " ",
                        message,
                        "\n"),
                 file = path,
                 append = TRUE))
      }
      invisible(NULL)
    })
}

