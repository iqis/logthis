# logthis - AI Assistant Context

**Last Updated:** 2025-10-07
**Package Version:** 0.1.0.9000
**Status:** Production-ready, CRAN submission pending

## Project Overview

`logthis` is a structured logging framework for R that provides enterprise-level logging capabilities similar to log4j or Python's logging module. It uses functional composition patterns and is designed for R packages, Shiny applications, and data analysis pipelines.

**Core Philosophy:**
- Functional, composable design with pipe-friendly syntax
- No side effects in loggers (they return events invisibly for chaining)
- Two-level filtering (logger-level + receiver-level)
- Resilient error handling (one receiver failure doesn't stop others)

## Architecture & Key Concepts

### Event Flow
```
Event � Logger Filter (with_limits) � Apply Logger Tags � Receivers � Receiver Filters � Output
```

### Core Components

1. **Log Events** - Structured data with metadata (message, time, level, tags, custom fields)
2. **Event Levels** - Hierarchical 0-100 scale (LOWEST=0, TRACE=10, DEBUG=20, NOTE=30, MESSAGE=40, WARNING=60, ERROR=80, CRITICAL=90, HIGHEST=100)
3. **Loggers** - Functions that process events through configured receivers
4. **Receivers** - Functions that output events (console, files, Shiny alerts, etc.)

### Design Patterns

**Closure-based Configuration:**
```r
logger <- function() {
  structure(function(event, ...) { ... },  # The logger function
            config = list(...))             # Configuration in attributes
}
```

**Receiver Pattern:**
- Receivers are functions: `function(event) { ... }`
- Must return `invisible(NULL)` (called for side effects)
- Wrapped with `receiver()` constructor for validation
- Can have optional level filtering via `lower`/`upper` parameters

**Logger Chaining:**
```r
WARNING("msg") %>% log_console() %>% log_file()  # Event flows through both
```

**Scope-based Masking:**
```r
# Parent logger
log_this <- logger() %>% with_receivers(to_console())

my_function <- function() {
  # Child logger adds receivers, doesn't affect parent
  log_this <- log_this %>% with_receivers(to_text_file("scope.log"))
  log_this(NOTE("Only in this scope"))
}
```

### Error Handling

**Resilient Receiver Execution (R/logger.R:56-84):**
- All receivers wrapped with `purrr::safely()`
- Failures logged as ERROR events with `receiver_error` tag
- Fallback to `to_console()`, then `warning()` as last resort
- Error messages include receiver #, error message, and receiver call

## File Structure

### Core Files (R/)
- **aaa.R** - Package-level utilities, color map, level guards (loaded first)
- **logger.R** - Core logger implementation, `with_*()` functions
- **log_event_levels.R** - Event level constructors (NOTE, WARNING, ERROR, etc.)
- **receivers.R** - All built-in receivers (console, file, JSON, Shiny, testing)
- **print-logger.R** - Print methods for logger inspection
- **zzz.R** - Package hooks (`.onLoad` exports `log_this` void logger)
- **utils-pipe.R** - Pipe operator re-exports

### Testing Structure (tests/testthat/)
- **test-logger.R** - Logger creation, filtering, chaining, tagging
- **test-receivers.R** - Receiver configuration, filtering, error handling
- **test-log-event-levels.R** - Event level creation and validation
- **test-tags.R** - Tagging at event/level/logger levels (24 tests)
- **test-with_limits.R** - Limit setting and validation

**Coverage:** 84.30% (Shiny receivers untestable without active session)
**Test Count:** 130 passing tests

## Code Conventions

### Naming
- **Functions:** `snake_case` (e.g., `with_receivers`, `to_console`)
- **Classes:** Prefix with `log_` (e.g., `log_event`, `log_receiver`, `log_event_level`)
- **Internal:** Prefix with `.` for package-level constants (e.g., `.LEVEL_COLOR_MAP`)
- **Exported constants:** ALL_CAPS for event levels (NOTE, WARNING, ERROR)

### Roxygen2 Patterns
- Use `@export` for all public functions
- Return type format: `@return <class>; description`
- Always include `@examples` for exported functions
- Use `@family` tags: `logger_configuration`, `receivers`, `event_levels`
- Cross-reference with `@seealso`

### Level Filtering Logic
**IMPORTANT:** All level limits are **inclusive**. An event passes if:
```r
event$level_number >= lower AND event$level_number <= upper
```

### Receiver Implementation Pattern
```r
to_my_receiver <- function(config_param = "default", lower = LOWEST(), upper = HIGHEST()) {
  receiver(function(event) {
    # Check receiver-level filtering
    if (event$level_number < attr(lower, "level_number") ||
        event$level_number > attr(upper, "level_number")) {
      return(invisible(NULL))
    }

    # Do the actual work (side effects)
    cat("Output:", event$message, "\n")

    # Always return NULL for receivers
    invisible(NULL)
  })
}
```

## Testing Approach

### Unit Test Strategy
1. **Isolation:** Test each component independently
2. **Testing Receivers:** Use `to_identity()` to capture events for inspection
3. **Shiny Receivers:** Document as untestable without session (acceptable coverage gap)
4. **Error Handling:** Test receiver failures using custom failing receivers

### Running Tests
```r
# All tests
devtools::test()

# Specific file
testthat::test_file("tests/testthat/test-logger.R")

# Coverage report
covr::package_coverage()
```

### Test File Template
```r
test_that("descriptive test name", {
  # Setup
  log_capture <- logger() %>% with_receivers(to_identity())

  # Execute
  result <- log_capture(WARNING("test message"))

  # Assert
  expect_equal(result$level_class, "WARNING")
  expect_equal(result$message, "test message")
})
```

## Common Tasks

### Adding a New Receiver

1. **Create receiver function in R/receivers.R:**
```r
#' @export
#' @family receivers
to_my_output <- function(param = "default", lower = LOWEST(), upper = HIGHEST()) {
  receiver(function(event) {
    # Filtering
    if (event$level_number < attr(lower, "level_number") ||
        event$level_number > attr(upper, "level_number")) {
      return(invisible(NULL))
    }

    # Implementation
    # ... your output logic ...

    invisible(NULL)
  })
}
```

2. **Add tests in tests/testthat/test-receivers.R**
3. **Document in README.md** (Built-in Receivers section)
4. **Update roxygen2:** `devtools::document()`

### Adding a New Event Level

```r
# In R/log_event_levels.R or user code
MY_LEVEL <- log_event_level("MY_LEVEL", 35)  # Between NOTE(30) and MESSAGE(40)
```

### Adding Logger Configuration

1. Add to `config` list in `logger()` (R/logger.R:92-96)
2. Create `with_*()` function following pattern at R/logger.R:244+
3. Add tests in tests/testthat/test-logger.R
4. Document with `@family logger_configuration`

## Important Gotchas

### 1. Receiver Attributes
- **receiver_labels** stores plain text (not pairlists!)
- Used for error messages and `print.logger()`
- Must sync with `receivers` list length

### 2. Shiny Dependencies
- `to_shinyalert()` and `to_notif()` require active Shiny session
- Will fail outside Shiny context
- Test coverage gap is expected and acceptable

### 3. Level Filtering Edge Cases
- Limits are **inclusive** on both ends
- Valid ranges: `lower  [0, 99]`, `upper  [1, 100]`
- Early return in logger if event outside limits (R/logger.R:44-47)

### 4. Logger Returns
- Loggers return events **invisibly** for chaining
- Receivers return `invisible(NULL)` (side effects only)
- Don't confuse the two return patterns

### 5. Tag Combination
Tags from all three sources are combined (order matters):
1. Event-level tags (innermost)
2. Event level constructor tags (via `with_tags.log_event_level()`)
3. Logger-level tags (R/logger.R:50-53)

### 6. File Rotation (to_text_file)
- `max_size` in bytes (not MB/GB)
- Rotation: log.txt � log.1.txt � log.2.txt
- `max_files` excludes current file (total = max_files + 1)

### 7. JSON Logging (to_json_file)
- Outputs JSONL format (one JSON object per line)
- Compact by default, use `pretty = TRUE` for debugging
- Always append mode (no rotation yet)

## Development Workflow

### Package Checks
```r
# Full check (run before commits)
devtools::check()

# Quick load during development
devtools::load_all()

# Update documentation
devtools::document()

# Run tests
devtools::test()
```

### Pre-commit Checklist
- [ ] All tests passing (`devtools::test()`)
- [ ] No R CMD check errors/warnings (`devtools::check()`)
- [ ] Documentation updated (`devtools::document()`)
- [ ] NEWS.md updated if user-facing changes
- [ ] Code coverage maintained or improved

### Git Workflow
- Main branch: `main`
- Feature branches: `feature/description`
- Clean commits, no force-push to main
- Squash minor commits before merging

## Current State & Next Steps

###  Complete (Production-Ready)
- Core logging functionality (loggers, events, receivers)
- Two-level filtering system
- Resilient error handling for receivers
- File rotation (to_text_file)
- JSON logging (to_json_file)
- Tag system (event/logger level)
- 130 passing tests, 84.30% coverage
- R CMD check: 0 errors, 0 warnings, 1 harmless note

### =� Partially Complete
- Event level tagging (`with_tags.log_event_level()` - TODO at R/logger.R:244-303)

### =� Future Enhancements (Post-CRAN)
- Async/buffered logging for high-volume scenarios
- Additional receivers (syslog, webhook, CSV)
- Performance benchmarks and optimization guide
- Migration guide from other logging packages
- Tag filtering/search utilities

### <� CRAN Submission Readiness
**Status:** Package is CRAN-ready. All success criteria met.

**Remaining tasks before submission:**
- [ ] Final review of cran-comments.md
- [ ] Verify all examples run cleanly
- [ ] Double-check DESCRIPTION completeness
- [ ] Test installation on fresh R environment

## References

- **Main Documentation:** README.md
- **Development Plan:** IMPROVEMENT_PLAN.md
- **Contributing:** CONTRIBUTING.md
- **Package Site:** https://iqis.github.io/logthis/
- **Issue Tracker:** https://github.com/iqis/logthis/issues

---

## Maintenance Notes for AI Assistants

**When making changes:**
1. Always read relevant test files before modifying code
2. Preserve functional composition patterns (no imperative refactors)
3. Maintain backward compatibility
4. Update tests, documentation, and this file when adding features
5. Follow roxygen2 conventions strictly
6. Never break the two-level filtering semantics
7. Keep receiver error handling resilient

**Common pitfall to avoid:**
- Don't add side effects to logger functions (they must be pure except for receiver calls)
- Don't skip receiver-level filtering in custom receivers
- Don't modify logger config in-place (always return new logger with updated attributes)

**When in doubt:**
- Check existing patterns in R/logger.R and R/receivers.R
- Consult test files for expected behavior
- Verify changes don't break the 130 existing tests
- when formatting, as much as possible, have the first argument to a function call on the same line as the (, and each argument on a new line) is this Lisp style? I like it very much.