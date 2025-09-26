## ----include = FALSE--------------------------------------------------------------------------------------------------
knitr::opts_chunk$set(
  collapse = TRUE,
  comment = "#>"
)

## ----setup------------------------------------------------------------------------------------------------------------
library(logthis)

## ----basic-logger-----------------------------------------------------------------------------------------------------
# Create a basic logger
log_this <- logger() %>%
    with_receivers(to_console()) %>%
    with_limits(lower = NOTE, upper = HIGHEST)

# Test it out
log_this(NOTE("Hello, logging world!"))
log_this(WARNING("This is a warning"))
log_this(ERROR("This is an error"))

## ----event-levels-----------------------------------------------------------------------------------------------------
# Create events at different levels
log_this(CHATTER("This is very detailed debug info"))
log_this(NOTE("Application started successfully"))
log_this(MESSAGE("Processing 1000 records"))
log_this(WARNING("Found 5 missing values"))
log_this(ERROR("Database connection failed"))

## ----logger-filtering-------------------------------------------------------------------------------------------------
# Only WARNING and ERROR events are processed at all
log_this <- logger() %>%
    with_receivers(to_console()) %>%
    with_limits(lower = WARNING, upper = HIGHEST)

log_this(NOTE("This won't be processed"))      # Blocked by logger
log_this(WARNING("This will be processed"))    # Passes logger filter

## ----receiver-filtering-----------------------------------------------------------------------------------------------
# Logger allows NOTE+, but console receiver only shows WARNING+
log_this <- logger() %>%
    with_receivers(to_console(lower = WARNING)) %>%
    with_limits(lower = NOTE, upper = HIGHEST)

log_this(CHATTER("Blocked by logger"))      # Below logger limit  
log_this(NOTE("Blocked by receiver"))       # Passes logger, blocked by receiver
log_this(WARNING("Reaches console"))        # Passes both filters

## ----combined-filtering-----------------------------------------------------------------------------------------------
# Sophisticated filtering with multiple receivers
log_this <- logger() %>%
    with_receivers(
        to_console(lower = WARNING),     # Console: warnings and errors only
        to_identity()                        # Audit: all events that pass logger  
    ) %>%
    with_limits(lower = NOTE, upper = HIGHEST)  # Logger: notes and above

# Events flow: CHATTER blocked by logger
#              NOTE reaches audit receiver only  
#              WARNING+ reaches both receivers

## ----multiple-receivers-----------------------------------------------------------------------------------------------
# Send to console and capture for testing
log_this <- logger() %>%
    with_receivers(
        to_console(),
        to_identity()  # Returns the event for inspection
    )

result <- log_this(WARNING("Sent to multiple receivers"))
print(result)  # The returned event object

## ----multiple-receivers-----------------------------------------------------------------------------------------------
# Send to console and capture for testing
log_this <- logger() %>%
    with_receivers(
        to_console(),
        to_identity()  # Returns the event for inspection
    )

result <- log_this(WARNING("Sent to multiple receivers"))
print(result)  # The returned event object

## ----custom-levels----------------------------------------------------------------------------------------------------
# Define custom levels
TRACE <- log_event_level("TRACE", 10)
DEBUG <- log_event_level("DEBUG", 30)
INFO <- log_event_level("INFO", 50)

# Use custom levels
log_this(TRACE("Entering function xyz()"))
log_this(DEBUG("Variable x = 42"))  
log_this(INFO("Processing completed"))

## ----structured-------------------------------------------------------------------------------------------------------
# Create events with custom fields
user_event <- WARNING("User login failed", 
                     user_id = "john_doe",
                     ip_address = "192.168.1.100",
                     attempt_count = 3)

log_this(user_event)

