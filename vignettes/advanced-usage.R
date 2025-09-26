## ----include = FALSE--------------------------------------------------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ----setup------------------------------------------------------------------------------------------------------------
library(logthis)

## ----chaining-basic---------------------------------------------------------------------------------------------------
# Create specialized loggers
log_this_console <- logger() %>% with_receivers(to_console())
log_this_capture <- logger() %>% with_receivers(to_identity())

# Chain them - event goes through both
result <- WARNING("System warning") %>%
    log_this_console() %>%
    log_this_capture()

# The final result is the original log event
print(result$message)
print(result$level_class)

## ----scope-enhancement------------------------------------------------------------------------------------------------
# Base logger in outer scope
log_this <- logger() %>% with_receivers(to_console())

process_data <- function() {
    # Add file logging within this scope only  
    log_this <- log_this %>% 
        with_receivers(to_identity())  # represents file logger
    
    log_this(NOTE("Processing data with enhanced logging"))
    
    # Nested function with additional receivers
    validate_data <- function() {
        log_this <- log_this %>%
            with_receivers(to_void())  # represents alert system
        
        log_this(WARNING("Data validation with full logging stack"))
    }
    
    validate_data()
}

# Base logger unchanged outside scope
log_this(NOTE("Back to base logger functionality"))

## ----scope-enhancement------------------------------------------------------------------------------------------------
# Base logger in outer scope
log_this <- logger() %>% with_receivers(to_console())

process_data <- function() {
    # Add file logging within this scope only  
    log_this <- log_this %>% 
        with_receivers(to_identity())  # represents file logger
    
    log_this(NOTE("Processing data with enhanced logging"))
    
    # Nested function with additional receivers
    validate_data <- function() {
        log_this <- log_this %>%
            with_receivers(to_void())  # represents alert system
        
        log_this(WARNING("Data validation with full logging stack"))
    }
    
    validate_data()
}

# Base logger unchanged outside scope
log_this(NOTE("Back to base logger functionality"))

## ----logger-pipelines-------------------------------------------------------------------------------------------------
# Define a logging pipeline
create_audit_pipeline <- function() {
    console_logger <- logger() %>% with_receivers(to_console())
    audit_logger <- logger() %>% with_receivers(to_identity())
    alert_logger <- logger() %>% with_receivers(to_void())
    
    function(event) {
        event %>%
            console_logger() %>%
            audit_logger() %>%
            alert_logger()
    }
}

audit_log <- create_audit_pipeline()

# Use the pipeline
audit_log(ERROR("Security violation detected"))

## ----filtering-architecture-------------------------------------------------------------------------------------------
# Complex filtering scenario
multi_filter_logger <- logger() %>%
    with_receivers(
        to_console(lower = WARNING, upper = ERROR),     # Console: WARNING to ERROR
        to_identity(),                                          # File: all events (no receiver filter)
        to_void()                                              # Monitor: all events (silent)
    ) %>%
    with_limits(lower = NOTE, upper = HIGHEST)                 # Logger: NOTE and above

# Event processing flow:
# CHATTER(10) -> Blocked by logger filter (< 40)
# NOTE(40)    -> Passes logger, reaches file & monitor only (< 80)  
# WARNING(80) -> Passes logger, reaches all three receivers
# ERROR(100)  -> Passes logger, reaches all three receivers
# HIGHEST(120) -> Blocked by logger filter (> 120) 

## ----performance-filtering--------------------------------------------------------------------------------------------
# Efficient: Logger blocks low-priority events early
log_this <- logger() %>%
    with_receivers(
        to_console(),
        to_identity(),  # Represents expensive file I/O
        to_void()       # Represents expensive network call
    ) %>%
    with_limits(lower = ERROR, upper = HIGHEST)  # Block most events at logger level

# Less efficient: All events reach expensive receivers  
log_this_inefficient <- logger() %>%
    with_receivers(
        to_console(lower = ERROR),
        to_identity(),  # Still processes all events
        to_void()       # Still processes all events  
    )
    # No logger-level filtering

## ----env-filtering----------------------------------------------------------------------------------------------------
create_env_logger <- function(env = "development") {
    log_this <- logger()
    
    if (env == "production") {
        # Production: restrictive logger filter, specific receiver filters
        log_this %>%
            with_receivers(
                to_console(lower = ERROR),        # Console: errors only
                to_identity()                         # File: all events that pass logger
            ) %>%
            with_limits(lower = WARNING, upper = HIGHEST)  # Logger: warnings and above
    } else {
        # Development: permissive logger filter, receiver-level control
        log_this %>%
            with_receivers(
                to_console(lower = CHATTER),      # Console: verbose output
                to_identity()                         # File: everything
            ) %>%
            with_limits(lower = CHATTER, upper = HIGHEST)  # Logger: everything
    }
}

## ----shiny-example, eval=FALSE----------------------------------------------------------------------------------------
# library(shiny)
# library(logthis)
# library(shinyalert)
# 
# # Setup application logger
# app_logger <- logger() %>%
#     with_receivers(
#         to_console(lower = CHATTER),    # All events to console
#         to_shinyalert(lower = ERROR)        # Only errors as alerts
#     )
# 
# ui <- fluidPage(
#     useShinyalert(),
#     actionButton("process", "Process Data"),
#     actionButton("error", "Trigger Error")
# )
# 
# server <- function(input, output, session) {
#     observeEvent(input$process, {
#         app_logger(NOTE("User clicked process button"))
# 
#         tryCatch({
#             # Simulate processing
#             app_logger(MESSAGE("Processing started"))
#             Sys.sleep(1)
#             app_logger(MESSAGE("Processing completed successfully"))
#         }, error = function(e) {
#             app_logger(ERROR(paste("Processing failed:", e$message)))
#         })
#     })
# 
#     observeEvent(input$error, {
#         app_logger(ERROR("User triggered an error for testing"))
#     })
# }
# 
# shinyApp(ui, server)

## ----custom-receivers-------------------------------------------------------------------------------------------------
# File logging receiver
to_text_file <- function(filepath, lower = LOWEST, upper = HIGHEST) {
    structure(
        function(event) {
            if (attr(lower, "level_number") <= event$level_number &&
                event$level_number <= attr(upper, "level_number")) {
                
                log_line <- paste0(
                    format(event$time, "%Y-%m-%d %H:%M:%S"), " ",
                    "[", event$level_class, "] ",
                    event$message
                )
                
                cat(log_line, "\n", file = filepath, append = TRUE)
            }
            event
        },
        class = c("log_receiver", "function")
    )
}

# Email notification receiver (pseudo-code)
to_email <- function(recipient, lower = ERROR) {
    structure(
        function(event) {
            if (event$level_number >= attr(lower, "level_number")) {
                # Send email notification
                # email_service$send(
                #     to = recipient,
                #     subject = paste("Log Alert:", event$level_class),
                #     body = event$message
                # )
            }
            event
        },
        class = c("log_receiver", "function")
    )
}

