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
```

## Event Levels

`logthis` uses a hierarchical system with predefined levels:

| Level    | Number | Purpose                    | Color  |
|----------|--------|----------------------------|--------|
| LOWEST   | 0      | Lowest priority debugging  | White  |
| CHATTER  | 20     | Verbose debugging output   | Silver |
| NOTE     | 40     | General notes/info         | Green  |
| MESSAGE  | 60     | Important messages         | Yellow |
| WARNING  | 80     | Warning conditions         | Red    |
| ERROR    | 100    | Error conditions           | Bold Red |
| HIGHEST  | 120    | Critical events            | Bold Red |

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
# Console output with color coding
to_console(min_level = LOWEST, max_level = HIGHEST)

# Shiny alerts (for Shiny applications)
to_shinyalert(lower = WARNING, upper = HIGHEST)

# Notifications
to_notif(lower = NOTE, upper = WARNING)

# Testing receivers
to_identity()  # Returns the event as-is
to_void()      # Discards the event
```

### Multiple Receivers Example

```r
# Send logs to both console and Shiny alerts
log_this <- logger() %>%
    with_receivers(
        to_console(min_level = CHATTER),
        to_shinyalert(lower = ERROR)
    )
```

## Advanced Configuration

### Setting Level Limits

```r
# Only process WARNING and ERROR events
log_this <- logger() %>%
    with_receivers(to_console()) %>%
    with_limits(lower = WARNING, upper = HIGHEST)
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
# Create specialized loggers
log_console <- logger() %>% with_receivers(to_console())
log_file <- logger() %>% with_receivers(to_identity())  # placeholder for file logger
log_alerts <- logger() %>% with_receivers(to_shinyalert(lower = ERROR))

# Chain them together - event flows through all loggers
WARNING("Database connection unstable") %>%
    log_console() %>%
    log_file() %>%
    log_alerts()

# Or create a pipeline
log_pipeline <- function(event) {
    event %>%
        log_console() %>%
        log_file() %>%
        log_alerts()
}

log_pipeline(ERROR("Critical system failure"))
```

### Scope-Based Logger Enhancement

```r
# Base application logger
log_this <- logger() %>% with_receivers(to_console())

process_sensitive_data <- function() {
    # Add audit logging in this scope only
    log_this <- log_this %>% 
        with_receivers(to_identity())  # represents audit logger
    
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
    base_logger <- logger() %>% with_receivers(to_console())
    
    if (env == "production") {
        base_logger <- base_logger %>%
            with_receivers(to_identity()) %>%  # file logging
            with_limits(lower = WARNING, upper = HIGHEST)
    } else if (env == "development") {
        base_logger <- base_logger %>%
            with_limits(lower = CHATTER, upper = HIGHEST)
    }
    
    return(base_logger)
}

app_logger <- create_logger(Sys.getenv("R_ENV", "development"))
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

## Use Cases

### Shiny Applications

```r
library(shiny)
library(logthis)

# Setup logging for Shiny app
app_logger <- logger() %>%
    with_receivers(
        to_console(min_level = NOTE),
        to_shinyalert(lower = ERROR)
    )

server <- function(input, output, session) {
    observeEvent(input$submit, {
        tryCatch({
            # Your app logic here
            app_logger(NOTE("User submitted form"))
        }, error = function(e) {
            app_logger(ERROR(paste("Form submission failed:", e$message)))
        })
    })
}
```

### Data Analysis Pipelines

```r
# Pipeline logging
pipeline_logger <- logger() %>%
    with_receivers(to_console()) %>%
    with_limits(lower = NOTE, upper = HIGHEST)

# Track pipeline progress
pipeline_logger(NOTE("Starting data processing"))
pipeline_logger(MESSAGE(paste("Processed", nrow(data), "records")))

if (any(is.na(data))) {
    pipeline_logger(WARNING("Found missing values in dataset"))
}
```

### Package Development

```r
# Internal package logging
.onLoad <- function(libname, pkgname) {
    # Create package logger
    assign("pkg_logger", 
           logger() %>% with_receivers(to_console()),
           envir = parent.env(environment()))
}

# Use in package functions
my_function <- function() {
    pkg_logger(NOTE("Function my_function() called"))
    # ... function logic
}
```

## Testing

The package includes comprehensive tests using `testthat`:

```r
# Run tests
devtools::test()

# Run specific test file
testthat::test_file("tests/testthat/test-logger.R")
```

## Dependencies

- `magrittr` - Pipe operators
- `purrr` - Functional programming utilities  
- `crayon` - Console text coloring
- `tibble` - Modern data frames
- `glue` - String interpolation

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


