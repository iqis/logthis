# logthis 0.1.0

## Initial CRAN Release

### Core Features

* **Hierarchical Event Levels**: 0-100 scale with pre-defined levels (TRACE, DEBUG, NOTE, MESSAGE, WARNING, ERROR, CRITICAL)
* **Multiple Output Receivers**: Console, files (text, JSON, CSV, Parquet, Feather), cloud storage (AWS S3, Azure Blob), webhooks, email, syslog, Microsoft Teams
* **Composable Design**: Pipe-based functional API for logger configuration
* **Two-Level Filtering**: Independent filtering at logger and receiver levels
* **Logger Chaining**: Chain multiple loggers together for complex routing
* **Scope-Based Enhancement**: Add receivers within specific scopes without affecting parent loggers
* **Tag-Based Organization**: Flexible tagging system for categorization and filtering

### Advanced Features

* **Middleware Pipeline**: Transform events with PII redaction, context enrichment, and sampling
* **Async Logging**: Non-blocking logging with `as_async()` for cloud receivers
* **Buffer Management**: Named receivers with manual flush control for batched cloud uploads
* **Contract System**: Design-by-contract support with runtime validation
* **Structured Events**: Rich metadata with timestamps, tags, and custom fields

### Integration Features

* **Shiny Integration**: Companion `logshiny` package with 7 receivers (alert panels, modals, toasts, browser console)
* **Tidyverse Pipeline Logging**: Automatic audit trails for dplyr/tidyr transformations via tidylog integration
* **GxP Validation**: 21 CFR Part 11 compliant audit trails for pharmaceutical applications
* **Validation Framework Integration**: Built-in helpers for {validate}, {pointblank}, {arsenal} packages

### AI-Forward Design

* **Copy-Paste Integration Prompts**: 7 ready-to-use prompts for common use cases
* **Self-Documenting API**: Consistent naming patterns (`to_*`, `on_*`, `with_*`)
* **Comprehensive Documentation**: 7 vignettes covering all major use cases

### Documentation

* Professional pkgdown site: https://iqis.github.io/logthis/
* 7 comprehensive vignettes
* AI-assisted integration prompts in README

### Testing

* 14 test files with comprehensive coverage
* GitHub Actions CI/CD pipeline
* Codecov integration for test coverage tracking

## Development

Package developed with AI assistance using [Claude Code](https://claude.com/claude-code)
