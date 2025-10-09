# Shiny Context Middleware
#
# Demonstrates how to automatically extract and attach Shiny session information
# to log events. Essential for debugging multi-user Shiny applications.

library(logthis)

# ==============================================================================
# Example 1: Basic Shiny Session Context
# ==============================================================================

#' Extract Shiny session information and add to log events
#'
#' Automatically captures session token, user agent, and client IP from the
#' active Shiny session. Useful for debugging user-specific issues.
#'
#' @param session Shiny session object (optional, defaults to current session)
#' @return middleware function
add_shiny_session <- function(session = NULL) {
  middleware(function(event) {
    # Get session from environment if not provided
    if (is.null(session)) {
      if (exists(".shiny_session", envir = .GlobalEnv)) {
        session <- get(".shiny_session", envir = .GlobalEnv)
      } else {
        # Not in Shiny context, skip
        return(event)
      }
    }

    # Check if we have a valid session
    if (!is.null(session) && inherits(session, "ShinySession")) {
      # Session token (unique identifier for this user's session)
      event$session_token <- session$token

      # Client data (if available)
      if (!is.null(session$clientData)) {
        event$user_agent <- session$clientData$url_search %||% NA
        event$client_url <- session$clientData$url_protocol %||% NA
      }

      # Request object (for IP address)
      if (!is.null(session$request)) {
        event$client_ip <- session$request$REMOTE_ADDR %||% NA
        event$server_port <- session$request$SERVER_PORT %||% NA
      }
    }

    event
  })
}

# Usage in Shiny server
if (interactive()) {
  library(shiny)

  ui <- fluidPage(
    titlePanel("Logging Demo"),
    actionButton("btn", "Click Me")
  )

  server <- function(input, output, session) {
    # Store session in global env for middleware access
    .shiny_session <- session

    # Create logger with session context
    log_this <- logger() %>%
      with_middleware(add_shiny_session(session)) %>%
      with_receivers(
        to_console(),
        to_json() %>% on_local("shiny_events.jsonl")
      )

    observeEvent(input$btn, {
      log_this(NOTE("Button clicked"))
      # Output: Includes session_token, user_agent, client_ip
    })
  }

  # shinyApp(ui, server)
}

# ==============================================================================
# Example 2: Reactive Context Tracking
# ==============================================================================

#' Add reactive context information to log events
#'
#' Captures which reactive expression triggered the log event. Useful for
#' understanding reactive dependency chains.
#'
#' @return middleware function
add_reactive_context <- middleware(function(event) {
  # Check if we're in a reactive context
  if (requireNamespace("shiny", quietly = TRUE)) {
    ctx <- tryCatch(
      shiny::getDefaultReactiveDomain(),
      error = function(e) NULL
    )

    if (!is.null(ctx)) {
      # Add reactive context label
      event$reactive_context <- "active"

      # Try to get current reactive label (if available)
      # Note: This is internal Shiny API, may not always work
      current_ctx <- tryCatch(
        shiny::getCurrentContext(),
        error = function(e) NULL
      )

      if (!is.null(current_ctx) && !is.null(current_ctx$label)) {
        event$reactive_label <- current_ctx$label
      }
    }
  }

  event
})

# ==============================================================================
# Example 3: Input Value Logging (Debugging)
# ==============================================================================

#' Create middleware that logs specific input values with events
#'
#' Useful for debugging reactive issues - automatically includes current values
#' of specific inputs with each log event.
#'
#' @param session Shiny session object
#' @param inputs Character vector of input IDs to log
#' @return middleware function
add_input_values <- function(session, inputs = NULL) {
  middleware(function(event) {
    if (!is.null(session) && inherits(session, "ShinySession")) {
      if (!is.null(inputs)) {
        # Log specific inputs
        input_values <- list()
        for (inp_id in inputs) {
          tryCatch({
            input_values[[inp_id]] <- session$input[[inp_id]]
          }, error = function(e) {
            input_values[[inp_id]] <- NA
          })
        }
        event$input_values <- input_values
      } else {
        # Log all input IDs (not values, to avoid huge logs)
        event$input_names <- names(session$input)
      }
    }

    event
  })
}

# Usage: Debug specific inputs
server <- function(input, output, session) {
  log_this <- logger() %>%
    with_middleware(
      add_input_values(session, inputs = c("slider", "select", "text"))
    ) %>%
    with_receivers(to_console())

  observe({
    log_this(DEBUG("Reactive triggered"))
    # Output: Includes current values of slider, select, text inputs
  })
}

# ==============================================================================
# Example 4: User Authentication Context
# ==============================================================================

#' Add authenticated user information from Shiny session
#'
#' For Shiny apps with authentication (e.g., using shinyauthr, auth0, or custom
#' authentication). Captures user ID and roles.
#'
#' @param session Shiny session object
#' @param user_info_fn Function that extracts user info from session
#'   Should return list with user_id, username, roles, etc.
#' @return middleware function
add_shiny_user <- function(session, user_info_fn = NULL) {
  middleware(function(event) {
    if (!is.null(session) && inherits(session, "ShinySession")) {
      # Default: try to get user from session$user (common pattern)
      if (is.null(user_info_fn)) {
        user_info <- session$user
      } else {
        user_info <- user_info_fn(session)
      }

      if (!is.null(user_info)) {
        if (!is.null(user_info$user_id)) {
          event$user_id <- user_info$user_id
        }
        if (!is.null(user_info$username)) {
          event$username <- user_info$username
        }
        if (!is.null(user_info$roles)) {
          event$user_roles <- paste(user_info$roles, collapse = ",")
        }
      }
    }

    event
  })
}

# Usage with shinyauthr or similar
server <- function(input, output, session) {
  # After authentication, store user in session
  session$user <- list(
    user_id = "12345",
    username = "john.doe",
    roles = c("analyst", "viewer")
  )

  log_this <- logger() %>%
    with_middleware(
      add_shiny_user(session)
    ) %>%
    with_receivers(
      to_json() %>% on_local("user_actions.jsonl")
    )

  observeEvent(input$export_data, {
    log_this(WARNING("Data export initiated", dataset = "patient_data"))
    # Output: Includes user_id, username, user_roles
  })
}

# ==============================================================================
# Example 5: Performance Timing in Reactive Context
# ==============================================================================

#' Add reactive execution timing to log events
#'
#' Tracks how long reactive expressions take to execute. Useful for performance
#' optimization.
#'
#' @return middleware function
add_reactive_timing <- middleware(function(event) {
  # If event has start_time field, calculate duration
  if (!is.null(event$start_time)) {
    event$duration_ms <- as.numeric(Sys.time() - event$start_time) * 1000
    event$start_time <- NULL  # Remove start_time from output
  }

  event
})

# Usage: Time reactive expressions
server <- function(input, output, session) {
  log_this <- logger() %>%
    with_middleware(add_reactive_timing) %>%
    with_receivers(to_console())

  expensive_reactive <- reactive({
    start_time <- Sys.time()

    # ... expensive computation ...
    Sys.sleep(0.5)  # Simulate work

    log_this(DEBUG("Expensive reactive completed", start_time = start_time))
    # Output: "duration_ms: 500"
  })
}

# ==============================================================================
# Example 6: Comprehensive Shiny Logger Factory
# ==============================================================================

#' Create production Shiny logger with full context
#'
#' Factory function that creates a logger with all Shiny context automatically
#' attached. Use this pattern for consistent logging across Shiny apps.
#'
#' @param session Shiny session object
#' @param app_name Application name
#' @param app_version Application version
#' @param log_dir Directory for log files
#' @param console_level Minimum level for console output
#' @return Configured logger
create_shiny_logger <- function(session,
                                app_name,
                                app_version,
                                log_dir = "logs",
                                console_level = WARNING) {
  # Ensure log directory exists
  if (!dir.exists(log_dir)) {
    dir.create(log_dir, recursive = TRUE)
  }

  # Create logger with comprehensive context
  logger() %>%
    with_middleware(
      # Shiny session context
      add_shiny_session(session),
      add_shiny_user(session),
      add_reactive_context,
      add_reactive_timing,

      # Application context
      middleware(function(event) {
        event$app_name <- app_name
        event$app_version <- app_version
        event$environment <- Sys.getenv("ENVIRONMENT", "production")
        event
      })
    ) %>%
    with_receivers(
      # Console (warnings and above)
      to_console(lower = console_level),

      # JSON file (all events)
      to_json() %>% on_local(file.path(log_dir, "app.jsonl")),

      # Text file (readable format)
      to_text(template = "{time} [{level}] {message}") %>%
        on_local(file.path(log_dir, "app.log"))
    )
}

# Usage in Shiny app
server <- function(input, output, session) {
  # Create logger once at app start
  log_this <- create_shiny_logger(
    session = session,
    app_name = "clinical-data-viewer",
    app_version = "1.0.0",
    log_dir = "logs",
    console_level = WARNING
  )

  # Use throughout app
  log_this(NOTE("App session started"))

  observeEvent(input$load_data, {
    log_this(NOTE("Loading data", dataset_id = input$dataset_selector))
    # ... load data ...
  })

  observeEvent(input$export, {
    log_this(WARNING("Data export requested", format = input$export_format))
    # ... export data ...
  })

  session$onSessionEnded(function() {
    log_this(NOTE("App session ended"))
  })
}

# ==============================================================================
# Example 7: Multi-User Shiny App Audit Trail
# ==============================================================================

#' Pharmaceutical Shiny app with complete audit trail
#'
#' Example of a GxP-compliant Shiny application that logs all user actions
#' with full context for regulatory audit.

if (interactive()) {
  library(shiny)

  ui <- fluidPage(
    titlePanel("Clinical Data Review (GxP)"),
    sidebarLayout(
      sidebarPanel(
        selectInput("study", "Study:", choices = c("TRIAL-001", "TRIAL-002")),
        actionButton("load", "Load Data"),
        actionButton("approve", "Approve Dataset")
      ),
      mainPanel(
        tableOutput("data_table")
      )
    )
  )

  server <- function(input, output, session) {
    # Simulate authentication
    session$user <- list(
      user_id = "USER-12345",
      username = "jane.scientist",
      roles = c("data_reviewer", "approver")
    )

    # Create GxP logger
    log_gxp <- logger() %>%
      with_middleware(
        # Shiny context
        add_shiny_session(session),
        add_shiny_user(session),

        # GxP context
        middleware(function(event) {
          event$system_id <- "SHINY-APP-PROD-001"
          event$system_validated <- TRUE
          event$timestamp_iso <- format(event$time, "%Y-%m-%dT%H:%M:%S%z")
          event
        })
      ) %>%
      with_tags("GxP", "audit_trail", "21CFR11") %>%
      with_receivers(
        to_json() %>% on_local("gxp_audit.jsonl"),
        to_console(lower = WARNING)
      )

    # Log all user actions
    observeEvent(input$load, {
      log_gxp(WARNING(
        "Data load initiated",
        study_id = input$study,
        action = "load_data"
      ))
    })

    observeEvent(input$approve, {
      log_gxp(CRITICAL(
        "Dataset approved",
        study_id = input$study,
        action = "approve_dataset",
        requires_signature = TRUE
      ))
    })

    session$onSessionEnded(function() {
      log_gxp(NOTE("Session ended"))
    })
  }

  # shinyApp(ui, server)
}
