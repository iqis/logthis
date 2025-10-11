# Tag Chaining in logthis - Order Preservation

**Date:** 2025-10-10

## How Tag Chaining Works

Tags in logthis work like Shiny's `ns()` function - they're chained/appended in order.

### Mechanism

When you chain `with_tags()` calls:

```r
log_this <- logger() %>% with_receivers(to_console())
log_this <- log_this %>% with_tags(component = "database")
log_this <- log_this %>% with_tags(subcomponent = "connection")
log_this <- log_this %>% with_tags(operation = "query")
```

Internally (R/logger.R:698-702):
```r
config <- attr(logger, "config")
if (append) {
  config$tags <- c(config$tags, tags)  # Appends to existing!
} else {
  config$tags <- tags
}
```

### Order Preservation

**Order IS preserved** because tags are stored as a **named character vector** and new tags are **appended to the end** via `c(config$tags, tags)`.

Example:
```r
log_this <- logger() %>% with_receivers(to_console())

# First call
log_this <- log_this %>% with_tags(component = "database")
# config$tags = c(component = "database")

# Second call
log_this <- log_this %>% with_tags(subcomponent = "connection")
# config$tags = c(component = "database", subcomponent = "connection")

# Third call
log_this <- log_this %>% with_tags(operation = "query")
# config$tags = c(component = "database", subcomponent = "connection", operation = "query")

# When logged, event gets ALL tags in ORDER
log_this(NOTE("Executing query"))
# event$component = "database"
# event$subcomponent = "connection"
# event$operation = "query"
```

### Exactly Like Shiny's ns()

Just as Shiny's `ns()` builds namespaces hierarchically:
```r
# Shiny modules
ns <- NS("module1")
ns("widget")  # "module1-widget"

nested_ns <- NS(ns("submodule"))
nested_ns("input")  # "module1-submodule-input"
```

logthis tags build hierarchical context:
```r
# logthis scope-based tagging
log_this <- log_this %>% with_tags(module = "module1")
# Nested scope adds more tags
log_this <- log_this %>% with_tags(submodule = "submodule", widget = "input")
# All tags preserved in order: module, submodule, widget
```

### Tag Combination from Multiple Sources

When an event is logged, tags are combined from THREE sources **in order** (R/logger.R:84-87):

1. **Event-level tags** (innermost)
2. **Event level constructor tags** (via `with_tags.log_event_level()` for custom levels)
3. **Logger-level tags** (outermost)

```r
# Create custom level with auto-tags
AUDIT <- log_event_level("AUDIT", 70) %>% with_tags(audit = "true")

# Logger with tags
log_this <- logger() %>%
  with_receivers(to_console()) %>%
  with_tags(component = "database", subcomponent = "connection")

# Event with tags
event <- AUDIT("User accessed data") %>% with_tags(user = "analyst")

# Final event has ALL tags combined:
log_this(event)
# event$user = "analyst"          (from event)
# event$audit = "true"             (from level)
# event$component = "database"     (from logger)
# event$subcomponent = "connection" (from logger)
```

## Scope-Based Pattern Leverages This

The scope-based logging pattern works BECAUSE of tag chaining:

```r
# Global logger
log_this <- logger() %>% with_receivers(to_console())

# Function scope - adds tags
database_function <- function() {
  log_this <- log_this %>% with_tags(component = "database")

  # Nested scope - adds more tags
  connection_handler <- function() {
    log_this <- log_this %>% with_tags(operation = "connect")
    log_this(NOTE("Connecting to database"))
    # Tags: component="database", operation="connect"
  }

  connection_handler()
}
```

## Key Insight

**Tag chaining + lexical scoping = Shiny-style namespacing WITHOUT hierarchy**

- No need for `getLogger("app.db.connection")` like Python
- Just configure `log_this` in scopes with `with_tags()`
- Order preserved, context accumulated naturally
- R-idiomatic (leverages lexical scoping)
