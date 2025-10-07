# logthis Decision Tree

Quick navigation guide for common tasks. Follow the decision path to find the right implementation.

## 1. I want to create a logger

**Q: Do you want logging active?**
- **YES** → Use `logger()`
- **NO (production optimization)** → Use `void_logger()`

→ **Next**: See section 2 (adding receivers)

---

## 2. I want to add a destination for logs

**Q: Where do you want logs to go?**

### → Console
```r
logger() %>% with_receivers(to_console())
```
**File**: R/receivers.R:to_console()

### → Local file (simple)
```r
logger() %>% with_receivers(to_text_file("app.log"))
```
**File**: R/receivers.R:to_text_file()

### → Local file with rotation
```r
logger() %>% with_receivers(
  to_text_file(path = "app.log",
               max_size = 10485760,  # 10MB
               max_files = 5)
)
```
**File**: R/receivers.R:to_text_file(), R/receivers.R:on_local()

### → Local file with custom format
```r
logger() %>% with_receivers(
  to_text("{time} | {level} | {message}") %>%
    on_local("custom.log")
)
```
**File**: R/receivers.R:to_text(), R/receivers.R:on_local()

### → AWS S3
```r
logger() %>% with_receivers(
  to_json() %>%
    on_s3(bucket = "my-bucket",
          key = "logs/app.jsonl",
          region = "us-east-1")
)
```
**File**: R/receivers.R:to_json(), R/receivers.R:on_s3()

### → Azure Blob Storage
```r
logger() %>% with_receivers(
  to_json() %>%
    on_azure(container = "logs",
             blob = "app.jsonl",
             connection_string = "...")
)
```
**File**: R/receivers.R:to_json(), R/receivers.R:on_azure()

### → Multiple destinations simultaneously
```r
logger() %>% with_receivers(
  to_console(),
  to_text_file("app.log"),
  to_json() %>% on_s3("bucket", "key")
)
```
**File**: R/logger.R:with_receivers()

→ **Next**: See section 3 (filtering) or section 5 (logging events)

---

## 3. I want to filter events by level

**Q: Where do you want filtering?**

### → At logger level (affects ALL receivers)
```r
logger() %>%
  with_receivers(to_console(), to_text_file("app.log")) %>%
  with_limits(lower = WARNING, upper = HIGHEST)
```
**Use case**: Only WARNING+ events reach any receiver
**File**: R/logger.R:with_limits.logger()

### → At receiver level (affects ONE receiver)
```r
logger() %>%
  with_receivers(
    to_console(lower = ERROR),        # Console: ERROR+ only
    to_text_file("all.log")           # File: all levels
  )
```
**Use case**: Different receivers see different levels
**File**: R/receivers.R:to_text_file(), R/receivers.R:with_limits.log_receiver()

### → At formatter level (before attaching handler)
```r
logger() %>%
  with_receivers(
    to_json(lower = WARNING) %>%
      on_s3("bucket", "key")
  )
```
**Use case**: Filter before formatting (more efficient)
**File**: R/receivers.R:with_limits.log_formatter()

→ **Next**: See section 5 (logging events)

---

## 4. I want to customize output format

**Q: What format do you need?**

### → Built-in text format with custom template
```r
to_text("{time} [{level}:{level_number}] {tags} {message}")
```
**Available variables**: time, level, level_number, message, tags, [custom fields]
**File**: R/receivers.R:to_text()

### → JSON/JSONL format
```r
to_json()                    # Compact JSONL
to_json(pretty = TRUE)       # Pretty-printed JSON
```
**File**: R/receivers.R:to_json()

### → Custom format (CSV, XML, etc.)
**See**: .claude/templates/custom-formatter.R
**Steps**:
1. Create formatter function
2. Return `formatter(function(event) {...})`
3. Set config attribute with format_type
4. Extract fields from event: event$time, event$level_class, event$message, etc.

**Example**:
```r
to_csv <- function() {
  formatter(function(event) {
    paste(event$time, event$level_class, event$message, sep = ",")
  })
}
```

→ **Next**: Attach handler with on_local(), on_s3(), or on_azure()

---

## 5. I want to log an event

**Q: What severity level?**

### → Trace-level (ultra-verbose)
```r
log_this(TRACE("Very detailed debugging info"))
```
**Level**: 10, **File**: R/log_event_levels.R

### → Debug-level
```r
log_this(DEBUG("Debugging information"))
```
**Level**: 20, **File**: R/log_event_levels.R

### → Note-level (notable, not just debugging)
```r
log_this(NOTE("Something notable happened"))
```
**Level**: 30, **File**: R/log_event_levels.R

### → Message-level (general info)
```r
log_this(MESSAGE("Application started"))
```
**Level**: 40, **File**: R/log_event_levels.R

### → Warning-level
```r
log_this(WARNING("Deprecated function used"))
```
**Level**: 60, **File**: R/log_event_levels.R

### → Error-level
```r
log_this(ERROR("Operation failed"))
```
**Level**: 80, **File**: R/log_event_levels.R

### → Critical-level
```r
log_this(CRITICAL("System failure imminent"))
```
**Level**: 90, **File**: R/log_event_levels.R

→ **Next**: See section 6 (adding context) or section 9 (custom levels)

---

## 6. I want to add context to events

**Q: What kind of context?**

### → Tags (categorization)
```r
# Per-event tags
log_this(NOTE("User login", tags = c("auth", "success")))

# Global tags (all events from this logger)
log_this <- logger() %>%
  with_receivers(to_console()) %>%
  with_tags("api", "v2")

log_this(NOTE("Request received"))  # Has tags: ["api", "v2"]
```
**File**: R/log_events.R:log_event(), R/logger.R:with_tags()

### → Custom fields
```r
log_this(NOTE("User action",
              user_id = 12345,
              action = "purchase",
              amount = 99.99))
```
**Access in template**: `{user_id}`, `{action}`, `{amount}`
**File**: R/log_events.R:log_event()

→ **Next**: See section 4 (formatting with custom fields)

---

## 7. I want to handle errors in receivers

**Q: What's happening?**

### → One receiver is failing, want others to continue
**Built-in behavior**: Logger catches errors and continues
```r
log_this <- logger() %>%
  with_receivers(
    to_console(),
    buggy_receiver(),  # Fails but doesn't stop others
    to_text_file("app.log")
  )
```
**Error reporting**: Logged to console with receiver provenance
**File**: R/logger.R:logger() (see execute_receivers)

### → Want to inspect receiver configuration
```r
log_this <- logger() %>%
  with_receivers(to_console(), to_text_file("app.log"))

config <- attr(log_this, "config")
config$receivers          # List of receiver functions
config$receiver_labels    # Labels for debugging
```
**File**: R/logger.R:logger()

---

## 8. I want to chain loggers

**Q: Why?**

### → Different scopes need different logging
```r
# Base logger
base_logger <- logger() %>% with_receivers(to_console())

# Enhanced for specific function
enhanced <- base_logger %>%
  with_receivers(to_text_file("detailed.log")) %>%
  with_tags("subsystem")

# Use enhanced in that scope
enhanced(NOTE("Subsystem event"))
```
**Pattern**: Loggers are immutable; enhancement creates new logger
**File**: R/logger.R:with_receivers(), R/logger.R:with_tags()

### → Pipeline-style logging
```r
result <- my_data %>%
  process_step1() %>%
  log_this(NOTE("Step 1 complete")) %>%
  process_step2() %>%
  log_this(NOTE("Step 2 complete"))
```
**Pattern**: Logger returns event unchanged for chaining
**File**: R/logger.R:logger()

---

## 9. I want to create a custom level

**Q: For what purpose?**

### → Application-specific severity
```r
# Pick a number in 0-100 scale (between existing levels)
AUDIT <- log_event_level("AUDIT", 35)  # Between NOTE(30) and MESSAGE(40)

# Use it
log_this(AUDIT("User performed sensitive action"))
```
**File**: R/log_event_levels.R:log_event_level()
**Template**: .claude/templates/custom-level.R

### → Want color for console output
```r
# Define level
AUDIT <- log_event_level("AUDIT", 35)

# Extend color map in R/aaa.R
.LEVEL_COLOR_MAP <- list(
  levels = c(0, 10, 20, 30, 35, 40, 60, 80, 90),
  colors = list(
    crayon::white,      # LOWEST
    crayon::silver,     # TRACE
    crayon::cyan,       # DEBUG
    crayon::green,      # NOTE
    crayon::magenta,    # AUDIT (new!)
    crayon::yellow,     # MESSAGE
    crayon::red,        # WARNING
    # ... etc
  )
)
```
**File**: R/aaa.R:.LEVEL_COLOR_MAP

---

## 10. I want to create a custom destination

**Q: What approach?**

### → New handler (recommended for storage destinations)
**Use when**: Adding a new storage backend (database, webhook, etc.)
**Template**: .claude/templates/custom-handler.R
**Steps**:
1. Create `on_xxx(formatter, ...)` function
2. Validate formatter: `if (!inherits(formatter, "log_formatter")) stop(...)`
3. Enrich config: `config$backend <- "xxx"; config$backend_config <- list(...)`
4. Create `.build_xxx_receiver(formatter)` function
5. Add case to `.formatter_to_receiver()` switch statement

**Example**:
```r
on_database <- function(formatter, conn, table) {
  if (!inherits(formatter, "log_formatter")) {
    stop("formatter must be log_formatter")
  }
  config <- attr(formatter, "config")
  config$backend <- "database"
  config$backend_config <- list(conn = conn, table = table)
  attr(formatter, "config") <- config
  formatter
}

.build_database_receiver <- function(formatter) {
  config <- attr(formatter, "config")$backend_config
  receiver(function(event) {
    formatted <- attr(formatter, "format_func")(event)
    DBI::dbAppendTable(config$conn, config$table, data.frame(log = formatted))
  })
}
```

### → Standalone receiver (for simple cases)
**Use when**: Not using formatter/handler pattern
**Template**: .claude/templates/custom-receiver.R
**Steps**:
1. Create constructor function
2. Return `receiver(function(event) {...})`
3. Add limits support if desired

**Example**:
```r
to_http <- function(url, lower = LOWEST, upper = HIGHEST) {
  recv <- receiver(function(event) {
    if (event$level_number < as.numeric(lower) ||
        event$level_number > as.numeric(upper)) {
      return(invisible(NULL))
    }
    httr::POST(url, body = jsonlite::toJSON(event, auto_unbox = TRUE))
  })
  attr(recv, "lower") <- lower
  attr(recv, "upper") <- upper
  recv
}
```

---

## 11. I want to integrate with config management

**Q: What config system?**

### → R's `config` package (YAML-based)
**Pattern**: Create setup function that reads config and builds logger
**Example**:
```r
setup_logger_from_config <- function(env = Sys.getenv("R_CONFIG_ACTIVE", "default")) {
  cfg <- config::get(config = env)

  log <- logger()
  receivers <- list()

  for (recv_cfg in cfg$logging$receivers) {
    if (!is.null(recv_cfg$console)) {
      receivers <- c(receivers, list(to_console()))
    }
    if (!is.null(recv_cfg$file)) {
      receivers <- c(receivers,
                     list(to_text_file(path = recv_cfg$file$path,
                                       max_size = recv_cfg$file$max_size,
                                       max_files = recv_cfg$file$max_files)))
    }
    if (!is.null(recv_cfg$s3)) {
      receivers <- c(receivers,
                     list(to_json() %>%
                            on_s3(bucket = recv_cfg$s3$bucket,
                                  key = recv_cfg$s3$key)))
    }
  }

  log %>%
    with_receivers(!!!receivers) %>%
    with_limits(lower = get(cfg$logging$min_level), upper = HIGHEST)
}

log_this <- setup_logger_from_config()
```
**Reference**: scratch.md "Config Management Integration" section

---

## 12. I need to debug or inspect

**Q: What do you need to inspect?**

### → Logger configuration
```r
log_this <- logger() %>%
  with_receivers(to_console(), to_text_file("app.log")) %>%
  with_limits(lower = WARNING, upper = ERROR)

# Print summary
print(log_this)

# Access config
config <- attr(log_this, "config")
config$limits           # List with lower, upper
config$receivers        # List of receiver functions
config$receiver_labels  # Character vector of labels
config$tags             # Character vector of global tags
```
**File**: R/logger.R:print.logger()

### → Receiver configuration
```r
recv <- to_text("{time} {message}") %>%
  on_local("app.log", max_size = 1000000, max_files = 3)

config <- attr(recv, "config")
config$format_type      # "text"
config$template         # "{time} {message}"
config$backend          # "local"
config$backend_config   # list(path = "app.log", ...)
```

### → Event structure
```r
evt <- NOTE("Test message", user_id = 123)
str(evt)                # Show structure
names(evt)              # List all fields
evt$level_number        # Access field
```
**File**: R/log_events.R:log_event()

---

## Quick Reference: File Locations

| What | Where |
|------|-------|
| Event constructors (NOTE, ERROR, etc.) | R/log_event_levels.R |
| Event factory (log_event) | R/log_events.R |
| Receivers & formatters | R/receivers.R |
| Logger & configuration | R/logger.R |
| Color mapping | R/aaa.R |
| Tests | tests/testthat/test-*.R |
| Templates for extensions | .claude/templates/ |
| Architecture map | .claude/architecture.yml |
| Use case examples | .claude/use-cases.md |
