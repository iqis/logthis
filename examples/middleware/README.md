# Middleware Examples

This directory contains example middleware functions for `logthis`. Middleware allows you to transform log events before they reach receivers, enabling powerful patterns like PII redaction, context enrichment, performance tracking, and event sampling.

## What is Middleware?

Middleware is a function that transforms log events in a pipeline:

```
Event → Middleware 1 → Middleware 2 → Logger Filter → Receivers
```

Each middleware can:
- **Transform** the event (add fields, modify message)
- **Drop** the event (return NULL to short-circuit)
- **Pass through** unchanged

## Core Concept

Middleware runs **before** logger-level filtering, so it can:
- Modify event levels (for dynamic routing)
- Add tags/flags (for receiver filtering)
- Drop events (for sampling/rate limiting)
- Enrich events (add context automatically)

## Files in This Directory

### 1. `redact_pii.R` - Privacy and Security
Remove personally identifiable information from logs before storage:
- Credit card number redaction
- SSN/SIN redaction
- Email address redaction
- Pharmaceutical patient identifier redaction (GxP compliance)

**Use cases:**
- GDPR/CCPA compliance
- HIPAA compliance (healthcare)
- 21 CFR Part 11 compliance (pharmaceutical)
- Financial services logging

### 2. `add_context.R` - Automatic Enrichment
Add contextual information to all events automatically:
- System context (hostname, OS, R version)
- Application context (version, environment, git commit)
- Request/trace IDs (distributed tracing)
- User context (authentication, roles)
- GxP audit trail context (study ID, site ID, operator)

**Use cases:**
- Microservices observability
- Multi-tenant applications
- Distributed systems debugging
- Pharmaceutical audit trails

### 3. `add_shiny_context.R` - Shiny Applications
Extract Shiny session information automatically:
- Session tokens and client IPs
- Reactive context tracking
- Input value logging (debugging)
- User authentication context
- Multi-user Shiny app audit trails

**Use cases:**
- Debugging Shiny apps
- User behavior analytics
- GxP-compliant Shiny applications
- Multi-user application monitoring

### 4. `add_timing.R` - Performance Monitoring
Calculate durations and track performance:
- Duration calculation from start_time fields
- Performance classification (fast/acceptable/slow)
- Level escalation for slow operations
- Rate limiting and throttling
- Performance percentile tracking

**Use cases:**
- API performance monitoring
- Database query optimization
- Reactive expression profiling (Shiny)
- SLA monitoring and alerting

### 5. `sample_events.R` - Volume Control
Reduce log volume while maintaining visibility:
- Percentage-based sampling
- Level-based sampling (keep errors, sample DEBUG)
- Rate limiting (token bucket algorithm)
- Adaptive sampling (adjust based on volume)
- Tag-based sampling (different rates per component)
- GxP-safe sampling (never drop audit-critical events)

**Use cases:**
- High-throughput systems
- Production log volume control
- Cost reduction (cloud logging fees)
- Development vs production sampling

## Common Patterns

### Pattern 1: Event Routing with Middleware

Use middleware to add flags that receivers filter on:

```r
# Middleware adds routing flags
route_events <- middleware(function(event) {
  if (event$level_number >= attr(ERROR, "level_number")) {
    event$route_to_pagerduty <- TRUE
  }

  if (!is.null(event$tags) && "security" %in% event$tags) {
    event$route_to_siem <- TRUE
  }

  event
})

# Receivers filter on flags
log_this <- logger() %>%
  with_middleware(route_events) %>%
  with_receivers(
    # PagerDuty receiver (filter in receiver function)
    receiver(function(event) {
      if (isTRUE(event$route_to_pagerduty)) {
        # ... send to PagerDuty
      }
      invisible(NULL)
    }),

    # SIEM receiver
    receiver(function(event) {
      if (isTRUE(event$route_to_siem)) {
        # ... send to SIEM
      }
      invisible(NULL)
    }),

    # All events to file
    to_json() %>% on_local("app.jsonl")
  )
```

### Pattern 2: Scope-Based Receivers (Multi-Destination Logging)

Use scope-based pattern to send events to multiple destinations:

```r
# SCOPE-BASED PATTERN: Configure log_this in function scope
database_operation <- function() {
  # Configure log_this for database component with multiple receivers
  log_this <- logger() %>%
    with_tags(component = "database") %>%
    with_receivers(
      # All events to component-specific log
      to_text() %>% on_local("database.log"),

      # All events to application-wide audit trail
      to_json() %>% on_local("app.jsonl"),

      # Only errors to global error store
      to_json() %>% on_s3(bucket = "global-logs", key = "errors.jsonl") %>% with_limits(lower = ERROR)
    )

  # Single call, multiple destinations
  log_this(ERROR("Database connection failed", retry_count = 3))
  # Goes to: database.log + app.jsonl + S3 global-logs
}
```

**Benefits:**
- Single logger name (`log_this`) everywhere
- Multiple receivers with different filtering
- Scope-based configuration (doesn't pollute parent scope)
- Component-specific tags automatically applied

### Pattern 3: Scope-Based Logger Masking

Middleware works with scope-based masking (no conflict):

```r
# Parent logger with middleware
log_this <- logger() %>%
  with_middleware(add_system_context) %>%
  with_receivers(to_console())

log_this(NOTE("Parent scope"))  # Has system context

# Child scope - adds MORE middleware
my_function <- function() {
  log_this <- log_this %>%
    with_middleware(add_request_id("REQ-123"))

  log_this(NOTE("Child scope"))  # Has system context AND request ID
}
my_function()

# Back to parent scope
log_this(NOTE("Parent again"))  # Only system context
```

**Key insight:** Middleware chains just like receivers and tags!

### Pattern 4: Conditional Routing with Level Modification

Use middleware to dynamically change event levels for routing:

```r
# Escalate specific errors to CRITICAL for alerting
escalate_critical_errors <- middleware(function(event) {
  critical_errors <- c("OutOfMemoryError", "DatabaseConnectionLost")

  if (event$level_class == "ERROR" &&
      !is.null(event$error_type) &&
      event$error_type %in% critical_errors) {

    # Escalate to CRITICAL
    event$level_class <- "CRITICAL"
    event$level_number <- attr(CRITICAL, "level_number")
    event$escalated <- TRUE
  }

  event
})

log_this <- logger() %>%
  with_middleware(escalate_critical_errors) %>%
  with_receivers(
    to_console(lower = WARNING),  # Warnings and above

    # PagerDuty receiver (CRITICAL only)
    receiver(function(event) {
      if (event$level_class == "CRITICAL") {
        # ... alert via PagerDuty
      }
      invisible(NULL)
    })
  )

log_this(ERROR("OutOfMemoryError", error_type = "OutOfMemoryError"))
# Escalated to CRITICAL → triggers PagerDuty alert
```

### Pattern 5: Multi-Stage Middleware Pipeline

Complex transformations with ordered middleware:

```r
log_this <- logger() %>%
  with_middleware(
    # Stage 1: Security (FIRST - before any other processing)
    redact_all_pii(),

    # Stage 2: Enrichment (add context)
    add_system_context,
    add_app_context(app_name = "api", app_version = "1.0.0", environment = "prod"),
    add_request_id(),

    # Stage 3: Performance (calculate timings)
    add_duration,
    classify_performance(),

    # Stage 4: Routing (add flags for receivers)
    route_events,

    # Stage 5: Sampling (LAST - after enrichment, reduces volume)
    sample_by_level(debug_rate = 0.01, note_rate = 0.1)
  ) %>%
  with_receivers(
    to_console(lower = WARNING),
    to_json() %>% on_local("app.jsonl")
  )
```

**Order matters!**
1. Security first (redaction)
2. Enrichment (context)
3. Performance (timing)
4. Routing (flags)
5. Sampling last (after enrichment)

### Pattern 6: Environment-Specific Middleware

Different middleware for dev vs production:

```r
create_logger <- function(environment = "production") {
  base_logger <- logger()

  if (environment == "production") {
    # Production: redaction, sampling, alerting
    base_logger <- base_logger %>%
      with_middleware(
        redact_all_pii(redact_ips = TRUE),
        add_production_context(app_config),
        sample_by_level(debug_rate = 0.01),
        escalate_slow_operations(threshold_ms = 5000)
      ) %>%
      with_receivers(
        to_console(lower = ERROR),  # Only errors to console
        to_json() %>% on_s3(bucket = "prod-logs", key = "app.jsonl")
      )
  } else if (environment == "development") {
    # Development: verbose, no sampling, local files
    base_logger <- base_logger %>%
      with_middleware(
        add_system_context,
        add_duration
      ) %>%
      with_receivers(
        to_console(lower = DEBUG),  # All events to console
        to_json() %>% on_local("dev.jsonl")
      )
  }

  base_logger
}

log_this <- create_logger(Sys.getenv("ENVIRONMENT", "development"))
```

### Pattern 7: Receiver-Specific Transforms (Without Middleware)

**Current approach:** Use formatters for receiver-specific transforms

```r
# Different outputs for different receivers (no receiver middleware needed)
log_this <- logger() %>%
  with_middleware(
    add_system_context  # Global: all receivers get this
  ) %>%
  with_receivers(
    # Console: redacted + human-readable
    to_text(template = "{level} {message}") %>%
      on_local("/dev/stdout"),  # Could use formatter for redaction

    # File: full JSON with all fields
    to_json(pretty = FALSE) %>% on_local("app.jsonl"),

    # S3: redacted JSON for long-term storage
    # Note: Redaction happens in logger middleware (affects all receivers)
    to_json() %>% on_s3(bucket = "logs", key = "app.jsonl")
  )
```

**Limitation:** Can't apply different transforms per receiver with current design

**Workaround:** Use separate loggers with different middleware:

```r
# Public logger (redacted)
log_public <- logger() %>%
  with_middleware(redact_all_pii()) %>%
  with_receivers(to_json() %>% on_s3(bucket = "public-logs"))

# Internal logger (unredacted)
log_internal <- logger() %>%
  with_receivers(to_json() %>% on_local("internal.jsonl"))

# Send to both
ERROR("Authentication failed", user_email = "user@example.com") %>%
  log_public() %>%    # Email redacted
  log_internal()      # Email preserved
```

### Pattern 7.1: Receiver-Level Middleware (IMPLEMENTED!)

**Same `with_middleware()` function, works on both loggers AND receivers via S3 dispatch!**

```r
# Different redaction per receiver
redact_full <- middleware(function(event) {
  event$message <- gsub("\\d{3}-\\d{2}-\\d{4}", "***-**-****", event$message)
  event
})

redact_partial <- middleware(function(event) {
  event$message <- gsub("(\\d{3}-\\d{2}-)\\d{4}", "\\1****", event$message)
  event
})

logger() %>%
  with_receivers(
    # Console: full SSN redaction
    to_console() %>% with_middleware(redact_full),

    # Internal log: partial redaction (last 4 digits visible)
    to_json() %>% on_local("internal.jsonl") %>%
      with_middleware(redact_partial),

    # Secure vault: no redaction
    to_json() %>% on_s3(bucket = "vault", key = "full.jsonl")
  )

log_this(NOTE("Patient SSN: 123-45-6789"))
# Console: "Patient SSN: ***-**-****"
# Internal: "Patient SSN: 123-45-****"
# Vault: "Patient SSN: 123-45-6789" (original)
```

**Execution order:**
```
Event → Logger Middleware → Logger Filter → Logger Tags →
  Receiver 1 Middleware → Receiver 1 Output
  Receiver 2 Middleware → Receiver 2 Output
```

**Use cases:**
- **Differential PII redaction:** Full redaction for console, partial for internal, none for secure vault
- **Cost optimization:** Sample events before expensive cloud logging
- **Format-specific enrichment:** Add fields only for specific outputs

## Pharmaceutical/Clinical Examples

All example files include GxP-specific patterns:

```r
# Clinical trial audit trail
log_clinical <- logger() %>%
  with_middleware(
    # Security: redact patient identifiers
    redact_patient_identifiers,

    # Context: GxP audit requirements
    add_gxp_context(
      study_id = "TRIAL-2024-001",
      site_id = "SITE-NYU-01",
      operator_id = "OP-12345",
      system_id = "LIMS-PROD-001"
    ),

    # Timing: operation durations for audit
    add_gxp_timing,

    # Sampling: NEVER drop audit-critical events
    sample_gxp_safe(debug_sample_rate = 0.05)
  ) %>%
  with_tags("GxP", "audit_trail", "21CFR11") %>%
  with_receivers(
    to_json() %>% on_local("gxp_audit.jsonl"),
    to_text() %>% on_local("gxp_audit.log")
  )

log_clinical(NOTE(
  "Sample analysis completed",
  sample_id = "SMP-001",
  assay = "HPLC",
  result = "PASS",
  start_time = start_time
))
# Output: Includes study_id, operator_id, duration_seconds, timestamp_iso
# Patient identifiers redacted, audit tags preserved
```

## Best Practices

### 1. Order Middleware Carefully
```r
# GOOD: Security first, sampling last
with_middleware(
  redact_pii,      # 1. Security
  add_context,     # 2. Enrich
  sample_events    # 3. Sample (after enrichment)
)

# BAD: Sampling before enrichment loses context
with_middleware(
  sample_events,   # 1. Sample first (loses context!)
  add_context,     # 2. Enrich (only sampled events)
  redact_pii       # 3. Security
)
```

### 2. Use Middleware for Cross-Cutting Concerns
Middleware is ideal for:
- ✅ PII redaction (affects all receivers)
- ✅ Context enrichment (adds fields globally)
- ✅ Performance tracking (timing all events)
- ✅ Event sampling (volume control)

NOT ideal for:
- ❌ Formatting (use formatters instead)
- ❌ Output-specific transforms (use logger chaining)

### 3. Test Middleware Independently
```r
test_that("redact_ssn middleware works", {
  mw <- redact_ssn

  event <- NOTE("SSN: 123-45-6789")
  result <- mw(event)

  expect_equal(result$message, "SSN: ***-**-****")
})
```

### 4. Document Middleware Behavior
```r
#' Redact credit card numbers
#'
#' Replaces all but last 4 digits with asterisks. Matches Visa, Mastercard,
#' Amex, Discover patterns with or without dashes.
#'
#' @return middleware function
#' @examples
#' log_this <- logger() %>%
#'   with_middleware(redact_credit_cards) %>%
#'   with_receivers(to_console())
redact_credit_cards <- middleware(function(event) {
  # ...
})
```

## Performance Considerations

### Middleware Overhead
Each middleware adds function call overhead:
- **Minimal impact:** 1-3 middleware functions (~microseconds)
- **Moderate impact:** 5-10 middleware functions
- **High impact:** Complex regex in PII redaction (milliseconds)

### Optimization Tips

1. **Conditional execution:**
```r
# GOOD: Early return for non-applicable events
redact_pii <- middleware(function(event) {
  # Skip if message is NULL or empty
  if (is.null(event$message) || nchar(event$message) == 0) {
    return(event)
  }

  # ... redaction logic
})
```

2. **Compile regexes once:**
```r
# GOOD: Regex compiled once (closure)
redact_ssn <- function() {
  ssn_pattern <- "\\b\\d{3}-?\\d{2}-?\\d{4}\\b"  # Compiled once

  middleware(function(event) {
    event$message <- gsub(ssn_pattern, "***-**-****", event$message)
    event
  })
}
```

3. **Sample before expensive operations:**
```r
# GOOD: Sample first (reduces work)
with_middleware(
  sample_by_level(debug_rate = 0.01),  # 1. Drop 99% of DEBUG
  redact_pii                           # 2. Redact remaining 1%
)
```

## Testing Middleware

Use `to_identity()` receiver to capture events:

```r
test_that("middleware adds context", {
  log_capture <- logger() %>%
    with_middleware(add_system_context) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("Test"))

  expect_true(!is.null(result$hostname))
  expect_true(!is.null(result$os))
  expect_true(!is.null(result$r_version))
})
```

## Questions and Feedback

- **Issue tracker:** https://github.com/iqis/logthis/issues
- **Discussions:** https://github.com/iqis/logthis/discussions

## See Also

- Main documentation: `/vignettes/patterns.Rmd` (Middleware Pattern section)
- Core implementation: `/R/logger.R` (`middleware()`, `with_middleware()`)
- Test suite: `/tests/testthat/test-middleware.R`
