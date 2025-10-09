# ==============================================================================
# Receiver Shiny UI
# ==============================================================================
# Shiny UI receivers for displaying log events in Shiny applications.
# Includes shinyalert, notifications, sweetalert, toasts, and browser console.

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
#' @family receivers
#'
#' @seealso [to_sweetalert()], [to_notif()], [to_show_toast()], [to_toastr()], [to_js_console()] for other Shiny receivers
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

        # Map log level to shinyalert type (info, success, warning, error)
        alert_type <- get_shiny_type(event$level_number, "shinyalert")
        shinyalert::shinyalert(text = event$message,
                               type = alert_type,
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
#' @family receivers
#'
#' @seealso [to_shinyalert()], [to_sweetalert()], [to_show_toast()], [to_toastr()], [to_js_console()] for other Shiny receivers
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

        # Map log level to shiny notification type (default, message, warning, error)
        notif_type <- get_shiny_type(event$level_number, "notif")
        shiny::showNotification(event$message,
                                type = notif_type,
                                ...)
      }
      invisible(NULL)
    })
}

#' SweetAlert2 modal receiver (shinyWidgets)
#'
#' Displays log events as SweetAlert2 modal alerts using the shinyWidgets package.
#' SweetAlert2 provides modern, customizable alerts with more options than shinyalert.
#' Requires the 'shinyWidgets' package and an active Shiny session.
#'
#' @param lower minimum level to display (inclusive, optional); <log_event_level>
#' @param upper maximum level to display (inclusive, optional); <log_event_level>
#' @param ... additional arguments passed to shinyWidgets::sendSweetAlert
#'
#' @return log receiver function; <log_receiver>
#' @export
#' @family receivers
#'
#' @seealso [to_shinyalert()], [to_notif()], [to_show_toast()], [to_toastr()], [to_js_console()] for other Shiny receivers
#'
#' @examples
#' \dontrun{
#' # Requires shinyWidgets package and active Shiny session
#' sweet_recv <- to_sweetalert()
#' }
to_sweetalert <- function(lower = WARNING, upper = HIGHEST, ...){
  receiver(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number <= attr(upper, "level_number")) {

        # Check if shinyWidgets is available
        if (!requireNamespace("shinyWidgets", quietly = TRUE)) {
          warning("shinyWidgets package is required for to_sweetalert() receiver but is not installed. ",
                  "Install with: install.packages('shinyWidgets')")
          return(invisible(NULL))
        }

        # Map log level to SweetAlert type (info, success, warning, error)
        alert_type <- get_shiny_type(event$level_number, "sweetalert")
        shinyWidgets::sendSweetAlert(
          session = shiny::getDefaultReactiveDomain(),
          text = event$message,
          type = alert_type,
          ...
        )
      }
      invisible(NULL)
    })
}

#' shinyWidgets toast notification receiver
#'
#' Displays log events as toast notifications using shinyWidgets::show_toast().
#' Provides an alternative toast style compared to base Shiny notifications.
#' Requires the 'shinyWidgets' package and an active Shiny session.
#'
#' @param lower minimum level to display (inclusive, optional); <log_event_level>
#' @param upper maximum level to display (inclusive, optional); <log_event_level>
#' @param ... additional arguments passed to shinyWidgets::show_toast
#'
#' @return log receiver function; <log_receiver>
#' @export
#' @family receivers
#'
#' @seealso [to_shinyalert()], [to_sweetalert()], [to_notif()], [to_toastr()], [to_js_console()] for other Shiny receivers
#'
#' @examples
#' \dontrun{
#' # Requires shinyWidgets package and active Shiny session
#' toast_recv <- to_show_toast()
#' }
to_show_toast <- function(lower = NOTE, upper = WARNING, ...){
  receiver(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number <= attr(upper, "level_number")) {

        # Check if shinyWidgets is available
        if (!requireNamespace("shinyWidgets", quietly = TRUE)) {
          warning("shinyWidgets package is required for to_show_toast() receiver but is not installed. ",
                  "Install with: install.packages('shinyWidgets')")
          return(invisible(NULL))
        }

        # Map log level to toast type (default, success, error, info, warning, question)
        toast_type <- get_shiny_type(event$level_number, "show_toast")
        shinyWidgets::show_toast(
          text = event$message,
          type = toast_type,
          ...
        )
      }
      invisible(NULL)
    })
}

#' toastr.js toast notification receiver
#'
#' Displays log events as toastr.js toast notifications using the shinytoastr package.
#' toastr.js is a popular JavaScript toast library with different styling than
#' shinyWidgets or base Shiny. Requires the 'shinytoastr' package and an active
#' Shiny session. You must call shinytoastr::useToastr() in your UI.
#'
#' @param lower minimum level to display (inclusive, optional); <log_event_level>
#' @param upper maximum level to display (inclusive, optional); <log_event_level>
#' @param ... additional arguments passed to shinytoastr toastr_* functions
#'
#' @return log receiver function; <log_receiver>
#' @export
#' @family receivers
#'
#' @seealso [to_shinyalert()], [to_sweetalert()], [to_notif()], [to_show_toast()], [to_js_console()] for other Shiny receivers
#'
#' @examples
#' \dontrun{
#' # Requires shinytoastr package and active Shiny session
#' # In UI: shinytoastr::useToastr()
#' toastr_recv <- to_toastr()
#' }
to_toastr <- function(lower = NOTE, upper = WARNING, ...){
  receiver(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number <= attr(upper, "level_number")) {

        # Check if shinytoastr is available
        if (!requireNamespace("shinytoastr", quietly = TRUE)) {
          warning("shinytoastr package is required for to_toastr() receiver but is not installed. ",
                  "Install with: install.packages('shinytoastr')")
          return(invisible(NULL))
        }

        # Map log level to toastr type (success, info, warning, error)
        toastr_type <- get_shiny_type(event$level_number, "toastr")

        # shinytoastr uses different functions for each type
        switch(toastr_type,
          "success" = shinytoastr::toastr_success(message = event$message, ...),
          "info" = shinytoastr::toastr_info(message = event$message, ...),
          "warning" = shinytoastr::toastr_warning(message = event$message, ...),
          "error" = shinytoastr::toastr_error(message = event$message, ...)
        )
      }
      invisible(NULL)
    })
}

#' Browser JavaScript console receiver
#'
#' Sends log events to the browser's JavaScript console (DevTools). This is
#' extremely useful for debugging Shiny applications, as R-side log events
#' appear in the browser console alongside JavaScript events. Requires the
#' 'shinyjs' package and an active Shiny session. You must call shinyjs::useShinyjs()
#' in your UI.
#'
#' NO PYTHON EQUIVALENT EXISTS - Python web frameworks (Dash, Streamlit, Flask)
#' cannot send server-side logs to browser console without custom JavaScript.
#'
#' @param lower minimum level to display (inclusive, optional); <log_event_level>
#' @param upper maximum level to display (inclusive, optional); <log_event_level>
#'
#' @return log receiver function; <log_receiver>
#' @export
#' @family receivers
#'
#' @seealso [to_shinyalert()], [to_sweetalert()], [to_notif()], [to_show_toast()], [to_toastr()] for other Shiny receivers, [to_console()] for R console output
#'
#' @examples
#' \dontrun{
#' # Requires shinyjs package and active Shiny session
#' # In UI: shinyjs::useShinyjs()
#' js_console_recv <- to_js_console()
#'
#' # Use in logger for simultaneous R console and browser console output
#' log_this <- logger() %>%
#'   with_receivers(
#'     to_console(),      # R console
#'     to_js_console()    # Browser console
#'   )
#' }
to_js_console <- function(lower = LOWEST, upper = HIGHEST){
  receiver(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number <= attr(upper, "level_number")) {

        # Check if shinyjs is available
        if (!requireNamespace("shinyjs", quietly = TRUE)) {
          warning("shinyjs package is required for to_js_console() receiver but is not installed. ",
                  "Install with: install.packages('shinyjs')")
          return(invisible(NULL))
        }

        # Map log level to console method (debug, log, warn, error)
        console_method <- get_shiny_type(event$level_number, "js_console")

        # Format message with timestamp and level
        formatted_msg <- paste0(
          "[", format(event$time, "%H:%M:%S"), "] ",
          "[", event$level_class, "] ",
          event$message
        )

        # Send to appropriate console method
        js_code <- switch(console_method,
          "debug" = sprintf("console.debug('%s');", formatted_msg),
          "log" = sprintf("console.log('%s');", formatted_msg),
          "warn" = sprintf("console.warn('%s');", formatted_msg),
          "error" = sprintf("console.error('%s');", formatted_msg)
        )

        # Execute JavaScript
        shinyjs::runjs(js_code)
      }
      invisible(NULL)
    })
}

