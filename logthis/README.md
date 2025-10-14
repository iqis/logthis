# logthis <img src="man/figures/logo.png" align="right" height="139" />

> **A Structured Logging Framework for R**

<!-- badges: start -->
[![Lifecycle: experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![R-CMD-check](https://github.com/iqis/logthis/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/iqis/logthis/actions/workflows/R-CMD-check.yaml)
[![Codecov test coverage](https://codecov.io/gh/iqis/logthis/branch/main/graph/badge.svg)](https://app.codecov.io/gh/iqis/logthis?branch=main)
[![CRAN status](https://www.r-pkg.org/badges/version/logthis)](https://CRAN.R-project.org/package=logthis)
<!-- badges: end -->

`logthis` is a sophisticated logging package for R that provides a flexible, structured approach to application logging. It implements enterprise-level logging patterns similar to log4j or Python's logging module, specifically designed for the R ecosystem.

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
# Level limits: 30 to 80
# Receivers:
#   [1] to_console()
```

## AI-Assisted Integration

Too busy to read the docs? Copy and paste these prompts into your AI assistant to quickly integrate `logthis` into your project:

<details>
<summary><strong>🆕 Add logthis to a new R project</strong></summary>

```
I'm starting a new R project. Please help me set up the logthis package
for structured logging with:
- Console output for development
- JSON file logging for production
- Appropriate log levels (NOTE, WARNING, ERROR)
- Example usage in my main script

Install from: devtools::install_github("iqis/logthis", subdir = "logthis")
```
</details>

<details>
<summary><strong>📦 Add logthis to an existing project (no current logging)</strong></summary>

```
I have an existing R project without logging. Please help me integrate
the logthis package to:
1. Add structured logging throughout my codebase
2. Identify key points where logging would be valuable (errors, state changes)
3. Set up multiple output receivers (console + file)
4. Use appropriate log levels

My project structure: [describe your project]
Install from: devtools::install_github("iqis/logthis", subdir = "logthis")
```
</details>

<details>
<summary><strong>🔄 Migrate from existing logging (log4r, logging, futile.logger)</strong></summary>

```
I'm currently using [log4r/logging/futile.logger] in my R project.
Please help me migrate to logthis:
1. Identify all existing logging calls
2. Create equivalent logthis configuration
3. Replace old logging calls with logthis syntax
4. Maintain the same log levels and output destinations
5. Ensure no functionality is lost

Install from: devtools::install_github("iqis/logthis", subdir = "logthis")
```
</details>

<details>
<summary><strong>✨ Add logthis to a Shiny application</strong></summary>

```
I have a Shiny application and want to add user-facing notifications
and logging using logthis + logshiny:
1. Install both packages
2. Add inline alert panels for user notifications
3. Set up backend logging to file/cloud
4. Log user actions and errors
5. Show examples of NOTE, WARNING, and ERROR notifications

Install:
devtools::install_github("iqis/logthis", subdir = "logthis")
devtools::install_github("iqis/logthis", subdir = "logshiny")
```
</details>

<details>
<summary><strong>📊 Add logthis to a data pipeline (dplyr/tidyr)</strong></summary>

```
I have data processing pipelines using dplyr/tidyr. Please help me:
1. Set up logthis with automatic tidyverse logging
2. Create audit trails for all transformations
3. Log to JSON Lines format for analysis
4. Track data lineage and row counts
5. Add custom tags for pipeline identification

Install from: devtools::install_github("iqis/logthis", subdir = "logthis")
```
</details>

<details>
<summary><strong>🏥 Set up GxP-compliant logging (pharmaceutical/clinical)</strong></summary>

```
I need 21 CFR Part 11 compliant audit trails for clinical data validation.
Please help me set up logthis with:
1. Tamper-evident JSON logging with timestamps
2. User identification and electronic signatures
3. Integration with the 'validate' package
4. Complete audit trail for all data transformations
5. Structured tags for study/protocol identification

Install from: devtools::install_github("iqis/logthis", subdir = "logthis")
See: https://iqis.github.io/logthis/articles/gxp-compliance.html
```
</details>

<details>
<summary><strong>☁️ Set up cloud logging (AWS S3, Azure, webhooks)</strong></summary>

```
I want to send logs to [AWS S3/Azure Blob/Webhooks/Microsoft Teams].
Please help me:
1. Configure logthis to write to [your cloud service]
2. Set up appropriate credentials/authentication
3. Use JSON format for structured logging
4. Filter logs by level (e.g., only ERROR to Teams)
5. Handle connection failures gracefully

Install from: devtools::install_github("iqis/logthis", subdir = "logthis")
```
</details>

**Pro tip:** After installation, ask your AI assistant to explain what the code does and how to customize it for your needs.

## Why logthis?

- **🎯 Hierarchical Event Levels** - Categorize messages by importance (0-100 scale)
- **🎨 Multiple Output Receivers** - Send logs to console, files, cloud storage, webhooks, and more
- **⚙️ Composable Design** - Use functional programming patterns with pipes
- **🔗 Logger Chaining** - Chain multiple loggers together for complex routing
- **🏥 GxP Validation** - 21 CFR Part 11 compliant audit trails for pharmaceutical applications
- **✨ Shiny Integration** - Companion [logshiny](https://github.com/iqis/logthis/tree/main/logshiny) package with inline alerts, modals, and toasts
- **📊 Pipeline Logging** - Automatic audit trails for dplyr/tidyr transformations (tidylog integration)
- **⚡ Middleware Pipeline** - Transform events with PII redaction, context enrichment, and sampling
- **📝 Structured Events** - Rich metadata with timestamps, tags, and custom fields
- **🤖 AI-Forward Design** - Built for seamless integration with AI coding assistants like [Claude Code](https://claude.com/claude-code)

## Installation

### Core Package

```r
# From GitHub (development version)
devtools::install_github("iqis/logthis", subdir = "logthis")

# From CRAN (when available)
# install.packages("logthis")
```

### Shiny Integration

For Shiny applications, install the companion package:

```r
devtools::install_github("iqis/logthis", subdir = "logshiny")
```

The `logshiny` package provides inline alert panels, modal alerts, toast notifications, and browser console logging.

## Key Features

### Multiple Output Receivers

Send logs to multiple destinations simultaneously:

```r
log_this <- logger() %>%
  with_receivers(
    to_console(),                                    # Console output
    to_json() %>% on_local("app.jsonl"),            # JSON Lines file
    to_json() %>% on_s3(bucket = "logs"),           # AWS S3
    to_teams(webhook_url = "...", lower = ERROR)    # MS Teams (errors only)
  )
```

### Event Levels

```r
# Pre-defined event levels (value in parentheses)
TRACE     # Detailed diagnostic output (10)
DEBUG     # Debugging information (20)
NOTE      # General notes/observations (30)
MESSAGE   # Important messages (40)
WARNING   # Warning conditions (60)
ERROR     # Error conditions (80)
CRITICAL  # Severe failures (90)

# Use them to create log events
log_this(NOTE("Application started"))
log_this(ERROR("Something went wrong!"))
```

### Structured Events with Tags

```r
# Tag events for filtering and categorization
log_this <- logger() %>%
  with_receivers(to_json() %>% on_local("audit.jsonl")) %>%
  with_tags(environment = "production", app = "api")

log_this(NOTE("User logged in", user_id = "12345", ip = "192.168.1.1"))
```

### Cloud & Integration Support

```r
# AWS S3
to_json() %>% on_s3(bucket = "logs", key_prefix = "app/events")

# Azure Blob Storage
to_json() %>% on_azure(container = "logs", blob = "app.jsonl")

# Webhooks
to_json() %>% on_webhook(url = "https://webhook.site/xyz")

# Microsoft Teams
to_teams(webhook_url = "...", title = "App Logs")

# Syslog
to_syslog(host = "localhost", protocol = "rfc5424")

# Email
to_email(to = "alerts@example.com", smtp_settings = ...)
```

## Learn More

Detailed guides and advanced techniques:

- **[Getting Started](articles/getting-started.html)** - Basic setup and usage patterns
- **[GxP Compliance & Pharmaceutical Logging](articles/gxp-compliance.html)** - 21 CFR Part 11 compliance and ALCOA+ audit trails
- **[Patterns](articles/patterns.html)** - Advanced patterns: middleware, logger chaining, architecture
- **[Advanced Receivers](articles/advanced-receivers.html)** - Custom receivers, async logging, buffering
- **[Tagging and Provenance](articles/tagging-and-provenance.html)** - Track data lineage and execution context
- **[Python Comparison](articles/python-comparison.html)** - Comparison with Python logging
- **[Migration Guide](articles/migration-guide.html)** - Migrate from other logging packages
- **[Function Reference](reference/index.html)** - Complete API documentation

## Use Cases

### 🏥 GxP Validation & Pharmaceutical Compliance

Complete audit trails for clinical data validation with 21 CFR Part 11 compliance:

```r
library(validate)
library(logthis)

log_gxp <- logger() %>%
  with_tags(study_id = "STUDY-001", regulation = "21CFR11") %>%
  with_receivers(to_json() %>% on_local("audit_trail.jsonl"))

validate_with_audit(
  data = clinical_data,
  rules = validator(age >= 18, weight > 0),
  logger = log_gxp,
  user_id = "data_manager"
)
```

See [GxP Compliance vignette](articles/gxp-compliance.html) for details.

### 📊 Data Pipeline Audit Trails

Automatic logging of dplyr/tidyr transformations:

```r
log_pipe <- logger() %>%
  with_tags(study_id = "STUDY-001") %>%
  with_receivers(to_json() %>% on_local("pipeline.jsonl"))

log_tidyverse(logger = log_pipe, pipeline_id = "data_cleaning")

# All dplyr/tidyr operations automatically logged
result <- mtcars %>%
  filter(mpg > 20) %>%      # Logged: "filter: removed 18 rows (56%)"
  mutate(efficiency = mpg / hp)  # Logged: "mutate: new variable"
```

### ✨ Shiny Applications

Inline alert panels for user notifications:

```r
library(shiny)
library(logshiny)

ui <- fluidPage(
  logshiny::alert_panel("app_alerts"),
  actionButton("submit", "Submit")
)

server <- function(input, output, session) {
  log_this <- logger() %>%
    with_receivers(logshiny::to_alert_panel("app_alerts"))

  observeEvent(input$submit, {
    log_this(NOTE("Form submitted successfully"))
  })
}
```

See the [logshiny package](https://github.com/iqis/logthis/tree/main/logshiny) for more.

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

To cite logthis in publications:

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
