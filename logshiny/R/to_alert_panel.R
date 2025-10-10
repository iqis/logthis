#' Log to Shiny Alert Panel
#'
#' Creates a receiver that displays log events as Bootstrap alert panels in a
#' Shiny application. Alerts are displayed in a designated UI container created
#' by `alert_panel()`.
#'
#' @param output_id Character string; the output ID matching the `alert_panel()`
#'   in the UI.
#' @param lower Log event level; minimum level to display (inclusive).
#'   Default: LOWEST().
#' @param upper Log event level; maximum level to display (inclusive).
#'   Default: HIGHEST().
#'
#' @return A log receiver function.
#'
#' @export
#'
#' @family shiny_receivers
#'
#' @examples
#' \dontrun{
#' library(shiny)
#' library(logshiny)
#' library(logthis)
#'
#' ui <- fluidPage(
#'   alert_panel("alerts", max_alerts = 5, auto_dismiss_ms = 3000),
#'   actionButton("warn_btn", "Warning"),
#'   actionButton("error_btn", "Error")
#' )
#'
#' server <- function(input, output, session) {
#'   log_this <- logger() %>%
#'     with_receivers(
#'       to_alert_panel("alerts"),
#'       to_console()
#'     )
#'
#'   observeEvent(input$warn_btn, {
#'     log_this(WARNING("This is a warning"))
#'   })
#'
#'   observeEvent(input$error_btn, {
#'     log_this(ERROR("This is an error"))
#'   })
#' }
#'
#' shinyApp(ui, server)
#' }
to_alert_panel <- function(
  output_id,
  lower = logthis::LOWEST(),
  upper = logthis::HIGHEST()
) {
  # Closure state
  initialized <- FALSE

  # Default config (fallback if JS hasn't run yet)
  default_config <- list(
    max_alerts = 10,
    dismissible = TRUE,
    auto_dismiss_ms = NULL,
    position = "top",
    max_height = NULL,
    show_clear_all = FALSE
  )

  # Level to Bootstrap status mapping
  level_to_status <- function(level) {
    switch(
      level,
      "CRITICAL" = "danger",
      "ERROR" = "danger",
      "WARNING" = "warning",
      "NOTE" = "info",
      "MESSAGE" = "info",
      "DEBUG" = "secondary",
      "TRACE" = "secondary",
      "info"  # default
    )
  }

  # Main receiver function
  logthis::receiver(function(event) {
    session <- shiny::getDefaultReactiveDomain()
    if (is.null(session)) {
      warning("to_alert_panel requires active Shiny session", call. = FALSE)
      return(invisible(NULL))
    }

    # Level filtering
    if (event$level_number < attr(lower, "level_number") ||
        event$level_number > attr(upper, "level_number")) {
      return(invisible(NULL))
    }

    # Initialize on first event
    if (!initialized) {
      config_input <- paste0(output_id, "_config")
      config <- session$input[[config_input]]

      # Fallback to defaults if config not available yet
      if (is.null(config)) {
        warning(
          sprintf(
            "Config for alert_panel('%s') not yet available. Using defaults. Did you include alert_panel() in UI?",
            output_id
          ),
          call. = FALSE
        )
        config <- default_config
      }

      # Store config in userData
      session$userData[[paste0(output_id, "_config")]] <- config

      # Initialize alert queue (reactiveVal)
      session$userData[[paste0(output_id, "_alerts")]] <- shiny::reactiveVal(list())

      # Set up dismissal observer
      dismiss_input <- paste0(output_id, "_dismissed")
      shiny::observeEvent(
        session$input[[dismiss_input]],
        {
          dismissed_id <- session$input[[dismiss_input]]
          alerts_rv <- session$userData[[paste0(output_id, "_alerts")]]
          current <- alerts_rv()
          # Remove dismissed alert from queue
          alerts_rv(Filter(function(a) a$id != dismissed_id, current))
        },
        ignoreInit = TRUE
      )

      # Set up renderUI
      session$output[[output_id]] <- shiny::renderUI({
        alerts <- session$userData[[paste0(output_id, "_alerts")]]()

        if (length(alerts) == 0) {
          return(NULL)
        }

        # Build alert divs
        alert_divs <- lapply(alerts, function(alert) {
          status <- level_to_status(alert$level)

          htmltools::div(
            class = paste0(
              "alert alert-", status,
              if (config$dismissible) " alert-dismissible fade show" else ""
            ),
            role = "alert",
            id = alert$id,

            # Content
            htmltools::tags$strong(alert$level), " ", alert$message,

            # Dismiss button
            if (config$dismissible) {
              htmltools::tags$button(
                type = "button",
                class = "close",
                `data-dismiss` = "alert",
                `aria-label` = "Close",
                # Callback when dismissed
                onclick = sprintf(
                  "Shiny.setInputValue('%s_dismissed', '%s', {priority: 'event'});",
                  output_id, alert$id
                ),
                htmltools::tags$span(`aria-hidden` = "true", htmltools::HTML("&times;"))
              )
            },

            # Auto-dismiss JS
            if (!is.null(config$auto_dismiss_ms)) {
              htmltools::tags$script(
                htmltools::HTML(
                  sprintf(
                    "
                    setTimeout(function() {
                      $('#%s').alert('close');
                      Shiny.setInputValue('%s_dismissed', '%s', {priority: 'event'});
                    }, %d);
                    ",
                    alert$id, output_id, alert$id, config$auto_dismiss_ms
                  )
                )
              )
            }
          )
        })

        # Clear all button
        if (config$show_clear_all && length(alerts) > 0) {
          alert_divs <- c(
            list(
              htmltools::tags$button(
                "Clear All",
                class = "btn btn-sm btn-secondary mb-2",
                onclick = sprintf(
                  "
                  $('#%s .alert').each(function() {
                    var id = $(this).attr('id');
                    $(this).alert('close');
                    Shiny.setInputValue('%s_dismissed', id, {priority: 'event'});
                  });
                  ",
                  output_id, output_id
                )
              )
            ),
            alert_divs
          )
        }

        htmltools::tagList(alert_divs)
      })

      initialized <<- TRUE
    }

    # Add alert to queue
    alerts_rv <- session$userData[[paste0(output_id, "_alerts")]]
    config <- session$userData[[paste0(output_id, "_config")]]
    current_alerts <- alerts_rv()

    # Create new alert
    new_alert <- list(
      id = paste0("alert_", as.numeric(Sys.time()) * 1000, "_", sample.int(10000, 1)),
      level = event$level_class,
      level_number = as.numeric(event$level_number),
      message = event$message,
      time = event$time
    )

    # Position new alert
    if (config$position == "top") {
      current_alerts <- c(list(new_alert), current_alerts)
    } else {
      current_alerts <- c(current_alerts, list(new_alert))
    }

    # Enforce max_alerts limit (FIFO)
    if (length(current_alerts) > config$max_alerts) {
      if (config$position == "top") {
        current_alerts <- head(current_alerts, config$max_alerts)
      } else {
        current_alerts <- tail(current_alerts, config$max_alerts)
      }
    }

    # Update reactiveVal
    alerts_rv(current_alerts)

    invisible(NULL)
  })
}
