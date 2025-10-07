# logthis <img src="man/figures/logo.png" align="right" height="139" />

> **A Structured Logging Framework for R**

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/iqis/logthis/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/iqis/logthis/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/iqis/logthis/branch/main/graph/badge.svg)](https://app.codecov.io/gh/iqis/logthis?branch=main)
[![CRAN status](https://www.r-pkg.org/badges/version/logthis)](https://CRAN.R-project.org/package=logthis)
<!-- badges: end -->

`logthis` is a sophisticated logging package for R that provides a flexible, structured approach to application logging. It implements enterprise-level logging patterns similar to log4j or Python's logging module, specifically designed for the R ecosystem.

## Features

- 🎯 **Hierarchical Event Levels** - Categorize messages by importance (0-120 scale)
- 🎨 **Multiple Output Receivers** - Send logs to console, files, Shiny alerts, and more
- ⚙️ **Configurable Filtering** - Set min/max level limits to control output
- 🔧 **Composable Design** - Use functional programming patterns with pipes
- 🔗 **Logger Chaining** - Chain multiple loggers together for complex routing
- 📋 **Scope-Based Enhancement** - Add receivers within specific scopes without affecting parent loggers
- 🌈 **Color-Coded Console Output** - Visual distinction for different log levels
- 📝 **Structured Events** - Rich metadata with timestamps, tags, and custom fields
- 🏷️ **Flexible Tagging System** - Track provenance, context, and categorization with hierarchical tags
- 🔗 **Shiny Integration** - Built-in support for Shiny applications

## Installation

You can install the development version of logthis from [GitHub](https://github.com/) with:

```r
# install.packages("devtools")
devtools::install_github("iqis/logthis")
```

Or install from CRAN with:

```r
# Not yet on CRAN
# install.packages("logthis")
```

## Quick Start

```r
library(logthis)

# Create a basic logger
log_this <- logger() %>%
    with_receivers(to_console()) %>%
    with_limits(lower = NOTE, upper = ERROR)

# Log some events
log_this(NOTE("Application started"))
log_this(WARNING("This is a warning message"))
log_this(ERROR("Something went wrong!"))

# Inspect logger configuration
print(log_this)
# <logger>
# Level limits: 40 to 100  
# Receivers:
#   [1] to_console()
#
# This logger processes events from NOTE (40) to ERROR (100) inclusive
```

**Note:** The package also exports a void logger called `log_this()` that discards all events - perfect for testing or when you want to disable logging without changing your code.

## Event Levels

`logthis` uses a hierarchical system with predefined levels:

| Level    | Number | Purpose                    | Color* |
|----------|--------|----------------------------|--------|
| LOWEST   | 0      | Lowest priority debugging  | White  |
| CHATTER  | 20     | Verbose debugging output   | Silver |
| NOTE     | 40     | General notes/info         | Green  |
| MESSAGE  | 60     | Important messages         | Yellow |
| WARNING  | 80     | Warning conditions         | Red    |
| ERROR    | 100    | Error conditions           | Bold Red |
| HIGHEST  | 120    | Critical events            | Bold Red |

*Colors are applied by the default `to_console()` receiver. Other receivers may use different formatting.

## Creating Custom Levels

```r
# Define a custom log level
DEBUG <- log_event_level("DEBUG", 30)

# Use it in logging
log_this(DEBUG("Custom debug message"))
```

## Receivers

Receivers determine where log events are sent. Multiple receivers can be attached to a single logger.

### Built-in Receivers

```r
# Console output with color coding (filtering is optional)
to_console(lower = LOWEST, upper = HIGHEST)

# Shiny alerts (for Shiny applications)  
to_shinyalert(lower = WARNING, upper = HIGHEST)

# Notifications
to_notif(lower = NOTE, upper = WARNING)

# Testing receivers
to_identity()  # Returns the event as-is
to_void()      # Discards the event
```

**Note:** Setting `lower`/`upper` boundaries is strictly optional for receivers. When omitted, receivers process all events that pass through the logger-level filter. Level limits are **inclusive** - events with `level_number >= lower AND <= upper` will be processed.

### Creating Custom Receivers

Custom receivers are functions that process log events for side effects (writing to console, files, databases, etc.). They should return `NULL` since they're called for their side effects only.

The recommended approach is to use the `receiver()` constructor function, which validates the receiver interface:

```r
# Using the receiver() constructor (recommended)
my_receiver <- receiver(function(event) {
  cat("CUSTOM LOG:", event$message, "\n")
  invisible(NULL)  # Receivers return NULL for side effects
})

# Use it in a logger
log_this <- logger() %>% with_receivers(my_receiver)

# Email notification receiver with configuration
to_email <- function(recipient = "admin@company.com", min_level = ERROR()) {
  receiver(function(event) {
    if (event$level_number >= attr(min_level, "level_number")) {
      # Send email logic here
      cat("EMAIL to", recipient, ":", event$message, "\n")
    }
    invisible(NULL)
  })
}

# Database logging receiver
to_database <- function(connection) {
  receiver(function(event) {
    # Insert into database logic
    query <- paste0("INSERT INTO logs VALUES ('", 
                   event$time, "', '", event$level_class, "', '", 
                   event$message, "')")
    # DBI::dbExecute(connection, query)  # Uncomment with real DB
    cat("DB INSERT:", query, "\n")
    invisible(NULL)
  })
}

# Slack notification receiver
to_slack <- function(webhook_url, channel = "#alerts") {
  receiver(function(event) {
    # Only send ERROR and above to Slack
    if (event$level_number >= 100) {
      payload <- list(
        text = paste("🚨", event$level_class, ":", event$message),
        channel = channel
      )
      # httr::POST(webhook_url, body = payload, encode = "json")  # Uncomment with real webhook
      cat("SLACK:", payload$text, "to", channel, "\n")
    }
    invisible(NULL)
  })
}
```

**Key Requirements for Custom Receivers:**
- Must accept exactly one argument named `event`
- Should return `invisible(NULL)` (called for side effects)
- Use `receiver()` constructor for validation and proper class assignment
- Access event properties: `event$message`, `event$time`, `event$level_class`, `event$level_number`
```

### Multiple Receivers Example

```r
# Send logs to both console and Shiny alerts
log_this <- logger() %>%
    with_receivers(
        to_console(lower = CHATTER),
        to_shinyalert(lower = ERROR)
    )

# Check configuration
print(log_this)
# <logger>
# Level limits: 0 to 120
# Receivers:
#   [1] to_console(lower = CHATTER)
#   [2] to_shinyalert(lower = ERROR)
```

## Advanced Configuration

### Two-Level Filtering System

`logthis` provides a sophisticated two-level filtering system with **inclusive** level limits:

1. **Logger-level filtering** (via `with_limits()`) - Filters events before they reach any receivers
2. **Receiver-level filtering** (via `lower`/`upper` parameters) - Each receiver can further filter events

**All level limits are inclusive**: events with `level_number >= lower AND <= upper` will be processed.

```r
# Logger-level: Only WARNING and above reach receivers (80 <= level <= 120)
# Receiver-level: Console shows NOTE and above (40 <= level <= 120), file shows ERROR only (100 <= level <= 120)
log_this <- logger() %>%
    with_receivers(
        to_console(lower = NOTE),        # Receiver filter: NOTE to HIGHEST (inclusive)
        to_text_file(lower = ERROR)      # Receiver filter: ERROR to HIGHEST (inclusive)  
    ) %>%
    with_limits(lower = WARNING, upper = HIGHEST)  # Logger filter: WARNING to HIGHEST (inclusive)

# Result: Console gets WARNING+, File gets ERROR+ (logger filter blocks NOTE/MESSAGE)
log_this(NOTE("This won't reach any receiver"))        # Blocked by logger (40 < 80)
log_this(WARNING("This goes to console only"))         # Passes logger (80 >= 80), blocked by file receiver (80 < 100)
log_this(ERROR("This goes to both console and file"))  # Passes both filters (100 >= 80 AND 100 >= 100)
```

### Setting Logger-Level Limits

```r
# Logger-level filtering - events outside these limits are dropped entirely
log_this <- logger() %>%
    with_receivers(to_console()) %>%
    with_limits(lower = WARNING, upper = HIGHEST)
```

### Setting Receiver-Level Limits

```r
# Each receiver can have its own filtering independent of logger limits
console_receiver <- to_console(lower = CHATTER, upper = WARNING)
file_receiver <- to_text_file(lower = ERROR, upper = HIGHEST)

log_this <- logger() %>%
    with_receivers(console_receiver, file_receiver)
```

### Appending vs Replacing Receivers

```r
# Replace existing receivers
log_this <- log_this %>%
    with_receivers(to_console(), append = FALSE)

# Append to existing receivers (default)
log_this <- log_this %>%
    with_receivers(to_shinyalert(), append = TRUE)
```

## Logger Chaining and Composition

`logthis` supports flexible logger composition through chaining and scope-based masking. Loggers return log events invisibly, enabling powerful patterns:

### Chaining Multiple Loggers

```r
# Create specialized loggers for specific use cases
log_this_console <- logger() %>% with_receivers(to_console())
log_this_file <- logger() %>% with_receivers(to_text_file(path = "app.log"))
log_this_alerts <- logger() %>% with_receivers(to_shinyalert(lower = ERROR))

# Chain them together - event flows through all loggers
WARNING("Database connection unstable") %>%
    log_this_console() %>%
    log_this_file() %>%
    log_this_alerts()

# Or create a pipeline
log_this_pipeline <- function(event) {
    event %>%
        log_this_console() %>%
        log_this_file() %>%
        log_this_alerts()
}

log_this_pipeline(ERROR("Critical system failure"))
```

### Scope-Based Logger Enhancement

```r
# Base application logger
log_this <- logger() %>% with_receivers(to_console())

process_sensitive_data <- function() {
    # Add audit logging in this scope only
    log_this <- log_this %>%
        with_receivers(to_text_file(path = "audit.log"))
    
    log_this(NOTE("Processing sensitive data"))
    log_this(MESSAGE("Data validation complete"))
    
    # Nested scope with even more logging
    validate_permissions <- function() {
        log_this <- log_this %>% 
            with_receivers(to_shinyalert(lower = WARNING))
        
        log_this(WARNING("Permission check required"))
    }
    
    validate_permissions()
}

# Base logger unchanged outside the scope
log_this(NOTE("Regular operation"))  # Only goes to console
```

### Conditional Logger Composition

```r
# Environment-aware logger building
create_logger <- function(env = "development") {
    log_this <- logger() %>% with_receivers(to_console())
    
    if (env == "production") {
        log_this <- log_this %>%
            with_receivers(to_text_file(path = "production.log")) %>%
            with_limits(lower = WARNING, upper = HIGHEST)
    } else if (env == "development") {
        log_this <- log_this %>%
            with_limits(lower = CHATTER, upper = HIGHEST)
    }
    
    return(log_this)
}

log_this <- create_logger(Sys.getenv("R_ENV", "development"))
```

## Structured Log Events

Each log event contains rich metadata:

```r
# Create a custom event with additional data
my_event <- WARNING("Database connection failed", 
                   retry_count = 3,
                   database = "prod_db")

log_this(my_event)
```

Event structure:
- `message` - The log message
- `time` - Timestamp when event was created
- `level_class` - Event level name (e.g., "WARNING")
- `level_number` - Numeric level (e.g., 80)
- `tags` - Array of tags for categorization
- `...` - Any additional custom fields

## Working with Tags

Tags provide a flexible categorization system for log events. They can be applied at three levels, and tags from all levels are combined when logging.

### Tagging Individual Events

```r
# Add tags to specific events
event <- NOTE("User logged in") %>%
    with_tags("authentication", "security")

log_this(event)
```

### Auto-Tagging by Level

Create custom event levels that automatically tag all events:

```r
# Create a tagged level for critical errors
CRITICAL <- ERROR %>% with_tags("critical", "alert", "pagerduty")

# All events from this level automatically have these tags
log_this(CRITICAL("Database connection lost"))
log_this(CRITICAL("Payment processing failed"))
```

### Logger-Level Tagging

Apply tags to all events passing through a logger:

```r
# Tag all logs from this service
log_this <- logger() %>%
    with_receivers(to_console()) %>%
    with_tags("production", "api-service", "us-east-1")

# All events logged here get these tags
log_this(NOTE("Service started"))
log_this(ERROR("Request timeout"))
```

### Tag Hierarchy

Tags from all three levels are combined:

```r
# 1. Create tagged level
AUTH_ERROR <- ERROR %>% with_tags("authentication")

# 2. Create tagged logger
log_api <- logger() %>%
    with_receivers(to_console()) %>%
    with_tags("api", "production")

# 3. Create event with its own tags
event <- AUTH_ERROR("Invalid credentials") %>%
    with_tags("user:12345")

# Event will have all tags: "authentication", "api", "production", "user:12345"
log_api(event)
```

### Practical Tag Patterns

```r
# Environment tagging
log_this <- logger() %>%
    with_receivers(to_console()) %>%
    with_tags(Sys.getenv("ENVIRONMENT", "dev"))

# Component tagging for microservices
log_database <- logger() %>%
    with_receivers(to_text_file(path = "db.log")) %>%
    with_tags("database", "postgres")

log_cache <- logger() %>%
    with_receivers(to_text_file(path = "cache.log")) %>%
    with_tags("cache", "redis")

# Request-specific tagging
process_request <- function(request_id) {
    log_this(NOTE("Processing request") %>%
        with_tags(paste0("request:", request_id)))
}
```

## Use Cases

### Shiny Applications

```r
library(shiny)
library(logthis)

# Setup logging for Shiny app
log_this <- logger() %>%
    with_receivers(
        to_console(lower = NOTE),
        to_shinyalert(lower = ERROR)
    )

server <- function(input, output, session) {
    observeEvent(input$submit, {
        tryCatch({
            # Your app logic here
            log_this(NOTE("User submitted form"))
        }, error = function(e) {
            log_this(ERROR(paste("Form submission failed:", e$message)))
        })
    })
}
```

### Data Analysis Pipelines

```r
# Pipeline logging
log_this <- logger() %>%
    with_receivers(to_console()) %>%
    with_limits(lower = NOTE, upper = HIGHEST)

# Track pipeline progress
log_this(NOTE("Starting data processing"))
log_this(MESSAGE(paste("Processed", nrow(data), "records")))

if (any(is.na(data))) {
    log_this(WARNING("Found missing values in dataset"))
}
```

### Package Development

```r
# Internal package logging
.onLoad <- function(libname, pkgname) {
    # Create package logger
    assign("log_this", 
           logger() %>% with_receivers(to_console()),
           envir = parent.env(environment()))
}

# Use in package functions
my_function <- function() {
    log_this(NOTE("Function my_function() called"))
    # ... function logic
}
```

## Testing

`logthis` provides excellent support for testing logging behavior in your applications.

### Using the Void Logger for Tests

The exported `log_this()` function is a void logger that discards all events - perfect for tests where you don't want actual logging output:

```r
library(testthat)
library(logthis)

test_that("function works with logging disabled", {
    # Your function uses log_this() internally
    my_function <- function(x) {
        log_this(NOTE(paste("Processing", x)))
        x * 2
    }
    
    # No logging output during tests
    result <- my_function(5)
    expect_equal(result, 10)
})
```

### Capturing Log Events for Testing

Use `to_identity()` receiver to capture and inspect log events:

```r
test_that("correct log events are generated", {
    # Create a logger that captures events
    log_capture <- logger() %>% with_receivers(to_identity())
    
    # Function that logs events
    process_data <- function(data) {
        if (nrow(data) == 0) {
            return(log_capture(WARNING("Empty dataset received")))
        }
        log_capture(NOTE(paste("Processing", nrow(data), "records")))
    }
    
    # Test with empty data
    empty_result <- process_data(data.frame())
    expect_equal(empty_result$level_class, "WARNING")
    expect_match(empty_result$message, "Empty dataset")
    
    # Test with actual data
    data_result <- process_data(data.frame(x = 1:3))
    expect_equal(data_result$level_class, "NOTE")
    expect_match(data_result$message, "Processing 3 records")
})
```

### Testing Logger Configuration

Test that loggers are configured correctly:

```r
test_that("logger filters events correctly", {
    # Create logger with specific limits
    test_logger <- logger() %>%
        with_receivers(to_identity()) %>%
        with_limits(lower = WARNING, upper = HIGHEST)
    
    # Events below WARNING should be filtered out
    note_event <- NOTE("This should be filtered")
    result_note <- test_logger(note_event)
    expect_null(result_note)  # Filtered events return NULL
    
    # Events at WARNING and above should pass through
    warn_event <- WARNING("This should pass")
    result_warn <- test_logger(warn_event)
    expect_equal(result_warn$level_class, "WARNING")
})
```

### Testing Receiver Behavior

Test individual receivers:

```r
test_that("to_console receiver respects filtering", {
    # Create console receiver with filtering
    console_receiver <- to_console(lower = ERROR, upper = HIGHEST)
    
    # Test that it's a proper receiver function
    expect_s3_class(console_receiver, "log_receiver")
    expect_s3_class(console_receiver, "function")
    
    # Test event handling (console output testing would require more setup)
    warn_event <- WARNING("Should be filtered")
    error_event <- ERROR("Should be shown")
    
    # Both should return the original event (receivers are pass-through)
    result_warn <- console_receiver(warn_event)
    result_error <- console_receiver(error_event)
    
    expect_equal(result_warn, warn_event)
    expect_equal(result_error, error_event)
})
```

### Testing Logger Chaining

Test that chaining works correctly:

```r
test_that("logger chaining preserves events", {
    # Create loggers that capture events
    log_first <- logger() %>% with_receivers(to_identity())
    log_second <- logger() %>% with_receivers(to_identity())
    
    # Chain them together
    original_event <- ERROR("Test message")
    final_result <- original_event %>%
        log_first() %>%
        log_second()
    
    # Should return the original event unchanged
    expect_equal(final_result, original_event)
    expect_equal(final_result$message, "Test message")
    expect_equal(final_result$level_class, "ERROR")
})
```

### Mocking Loggers in Tests

Replace loggers with test doubles:

```r
test_that("can mock logger behavior", {
    # Save original logger
    original_log_this <- log_this
    
    # Create mock logger that captures events
    captured_events <- list()
    mock_logger <- function(event) {
        captured_events <<- append(captured_events, list(event))
        return(event)
    }
    
    # Replace global logger
    assign("log_this", mock_logger, envir = globalenv())
    
    # Test your function
    my_function <- function() {
        log_this(NOTE("Function called"))
        log_this(WARNING("Warning occurred"))
        return("done")
    }
    
    result <- my_function()
    
    # Verify logging behavior
    expect_equal(length(captured_events), 2)
    expect_equal(captured_events[[1]]$level_class, "NOTE")
    expect_equal(captured_events[[2]]$level_class, "WARNING")
    
    # Restore original logger
    assign("log_this", original_log_this, envir = globalenv())
})
```

### Integration Testing with Multiple Receivers

Test complex logging setups:

```r
test_that("multi-receiver logger works correctly", {
    # Create logger with multiple receivers
    captured_events <- list()
    capture_receiver <- function(event) {
        captured_events <<- append(captured_events, list(event))
        return(event)
    }
    
    multi_logger <- logger() %>%
        with_receivers(
            capture_receiver,
            to_identity(),  # Pass-through
            to_void()       # Discard
        )
    
    # Send event through logger
    test_event <- WARNING("Multi-receiver test")
    result <- multi_logger(test_event)
    
    # Verify all receivers processed the event
    expect_equal(length(captured_events), 1)
    expect_equal(captured_events[[1]]$message, "Multi-receiver test")
    expect_equal(result, test_event)  # Should return original event
})
```

### Running Package Tests

The package includes comprehensive tests using `testthat`:

```r
# Run all tests
devtools::test()

# Run specific test file
testthat::test_file("tests/testthat/test-logger.R")

# Run tests with coverage
covr::package_coverage()
```

## Dependencies

- `magrittr` - Pipe operators
- `purrr` - Functional programming utilities
- `crayon` - Console text coloring
- `glue` - String interpolation

## Learn More

For detailed guides and advanced techniques:

- **[Getting Started](vignettes/getting-started.Rmd)** - Basic setup and usage patterns
- **[Tagging and Provenance](vignettes/tagging-and-provenance.Rmd)** - Track data lineage, execution context, and build audit trails with hierarchical tags

## Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass (`devtools::test()`)
6. Update documentation (`devtools::document()`)
7. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Citation

To cite logthis in publications use:

```r
citation("logthis")
```

Or manually:

```
logthis: Structured Logging Framework for R.
R package version 0.1.0.9000.
https://github.com/iqis/logthis
```

## Code of Conduct

Please note that the logthis project is released with a [Contributor Code of Conduct](https://contributor-covenant.org/version/2/0/CODE_OF_CONDUCT.html). By contributing to this project, you agree to abide by its terms.

## Acknowledgments

Originally developed as part of the `ocs.ianalyze` project for pharmaceutical data analysis workflows.


