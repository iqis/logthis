#' Create an Alert Panel for Log Messages
#'
#' Creates a UI container for displaying log messages as Bootstrap alert panels.
#' This function generates a placeholder that will be populated by log events
#' from a `to_alert_panel()` receiver.
#'
#' @param output_id Character string; the output ID that matches the receiver's
#'   output_id parameter.
#' @param max_alerts Integer; maximum number of alerts to display at once.
#'   Older alerts are removed when this limit is reached. Default: 10.
#' @param dismissible Logical; whether alerts should have a close (X) button.
#'   Default: TRUE.
#' @param auto_dismiss_ms Integer or NULL; milliseconds after which alerts
#'   auto-dismiss. NULL means alerts stay until manually dismissed. Default: NULL.
#' @param position Character; where new alerts appear. Either "top" (newest first)
#'   or "bottom" (newest last). Default: "top".
#' @param max_height Character; CSS max-height value for the container
#'   (e.g., "300px"). NULL means no height limit. Default: NULL.
#' @param show_clear_all Logical; whether to show a "Clear All" button.
#'   Default: FALSE.
#' @param container_class Character; additional CSS classes for the container.
#'   Default: NULL.
#'
#' @return A Shiny UI element (HTML div) containing the alert panel placeholder.
#'
#' @export
#'
#' @family shiny_ui
#'
#' @examples
#' \dontrun{
#' library(shiny)
#' library(logshiny)
#' library(logthis)
#'
#' ui <- fluidPage(
#'   alert_panel(
#'     "app_alerts",
#'     max_alerts = 5,
#'     dismissible = TRUE,
#'     auto_dismiss_ms = 5000,
#'     position = "top"
#'   ),
#'   actionButton("log_btn", "Generate Log")
#' )
#'
#' server <- function(input, output, session) {
#'   log_this <- logger() %>%
#'     with_receivers(to_alert_panel("app_alerts"))
#'
#'   observeEvent(input$log_btn, {
#'     log_this(WARNING("This is a warning message"))
#'   })
#' }
#'
#' shinyApp(ui, server)
#' }
alert_panel <- function(
  output_id,
  max_alerts = 10,
  dismissible = TRUE,
  auto_dismiss_ms = NULL,
  position = c("top", "bottom"),
  max_height = NULL,
  show_clear_all = FALSE,
  container_class = NULL
) {
  # Validate inputs
  if (!is.character(output_id) || length(output_id) != 1) {
    stop("`output_id` must be a single character string")
  }

  position <- match.arg(position)

  # Build config object
  config <- list(
    max_alerts = as.integer(max_alerts),
    dismissible = isTRUE(dismissible),
    auto_dismiss_ms = if (is.null(auto_dismiss_ms)) NULL else as.integer(auto_dismiss_ms),
    position = position,
    max_height = max_height,
    show_clear_all = isTRUE(show_clear_all)
  )

  # Build container style
  container_style <- if (!is.null(max_height)) {
    paste0("max-height: ", max_height, "; overflow-y: auto;")
  } else {
    NULL
  }

  # Create the UI element
  htmltools::div(
    class = paste("logthis-alert-panel", container_class),
    id = paste0(output_id, "_container"),
    style = container_style,

    # JavaScript to push config to session on initialization
    htmltools::tags$script(
      htmltools::HTML(
        sprintf(
          "
          $(document).on('shiny:sessioninitialized', function() {
            Shiny.setInputValue('%s_config', %s, {priority: 'event'});
          });
          ",
          output_id,
          jsonlite::toJSON(config, auto_unbox = TRUE)
        )
      )
    ),

    # The actual output placeholder
    shiny::uiOutput(output_id)
  )
}
