# Scope-Based Logging Pattern - Design Guide

**Created:** 2025-10-10
**Status:** Canonical pattern for logthis

---

## Problem

Current examples create too many differently-named loggers:
- `log_app`, `log_db`, `log_api`, `log_user`, `log_req`, `log_gxp`, `log_pipe`, etc.
- Users don't know which logger to use
- Code is harder to refactor (moving code requires renaming loggers)
- Not R-idiomatic (doesn't leverage lexical scoping like Shiny modules)

## Solution

**USE ONE LOGGER NAME: `log_this`**
**CONFIGURE IT IN SCOPES**

Just like Shiny's `ns()` function - flatten hierarchy into tags using R's lexical scoping.

---

## The Pattern

### ❌ WRONG (Multiple logger names)

```r
# Don't do this!
log_app <- logger() %>% with_receivers(to_console())
log_db <- component_logger(log_app, component = "database")
log_api <- component_logger(log_app, component = "api")

database_function <- function() {
  log_db(NOTE("Database event"))  # Which logger? Confusing!
}
```

### ✅ RIGHT (One name, configured in scopes)

```r
# Global logger
log_this <- logger() %>% with_receivers(to_console())

# Configure in function scope
database_function <- function() {
  log_this <- log_this %>% with_tags(component = "database")
  log_this(NOTE("Database event"))  # Always log_this!
}

api_function <- function() {
  log_this <- log_this %>% with_tags(component = "api")
  log_this(NOTE("API event"))  # Always log_this!
}

# Global log_this unchanged
log_this(NOTE("App event"))
```

---

## Benefits

1. **One name everywhere** - No cognitive load, always `log_this`
2. **Scope-based** - Uses R's lexical scoping naturally
3. **No global mutation** - Parent loggers never modified
4. **Easy to refactor** - Move code without renaming loggers
5. **R-idiomatic** - Like Shiny modules with `ns()`

---

## Common Patterns

### Module/Component Logging

```r
# In R/database.R
log_this <- logger() %>% with_receivers(to_console())

db_connect <- function() {
  log_this <- log_this %>% with_tags(component = "database", operation = "connect")
  log_this(NOTE("Connecting to database"))
}

db_query <- function(sql) {
  log_this <- log_this %>% with_tags(component = "database", operation = "query")
  log_this(NOTE("Executing query"))
}
```

### Shiny App Logging

```r
# Global
log_this <- logger() %>% with_receivers(to_console())

ui <- fluidPage(...)

server <- function(input, output, session) {
  # Configure for this session
  log_this <- log_this %>%
    with_tags(
      user_id = session$user,
      session_id = session$token
    )

  observeEvent(input$submit, {
    log_this(NOTE("Form submitted"))  # Auto-tagged with user info
  })

  # Module scope
  my_module_server <- function(id) {
    moduleServer(id, function(input, output, session) {
      log_this <- log_this %>% with_tags(module = id)
      log_this(NOTE("Module initialized"))
    })
  }
}
```

### GxP Pipeline Logging

```r
# Global
log_this <- create_gxp_logger(
  study_id = "STUDY-001",
  system_name = "Data Pipeline",
  audit_path = "audit.jsonl"
)

# In pipeline function
process_dm <- function(raw_data) {
  log_this <- log_this %>%
    with_tags(
      dataset = "DM",
      operation = "derivation",
      user_id = Sys.getenv("USER")
    )

  log_this(NOTE("Starting DM derivation"))

  result <- raw_data %>%
    filter(!is.na(USUBJID))  # tidylog automatically logs this

  log_this(NOTE("DM derivation complete"))
  result
}
```

### API Request Logging

```r
# Global
log_this <- logger() %>% with_receivers(to_console())

#* @get /users/:id
function(req, res, id) {
  log_this <- log_this %>%
    with_tags(
      request_id = req$id,
      endpoint = req$PATH_INFO,
      method = req$REQUEST_METHOD
    )

  log_this(NOTE("Processing request"))
  # ... handle request ...
  log_this(NOTE("Request complete"))
}
```

---

## Helper Functions Usage

Helpers should be used to **configure** `log_this`, not create new loggers:

### ❌ WRONG

```r
log_user <- user_logger(log_app, user_id = "analyst")
log_user(NOTE("Event"))
```

### ✅ RIGHT

```r
my_function <- function(user_id) {
  log_this <- user_logger(log_this, user_id = user_id)
  log_this(NOTE("Event"))
}
```

---

## Exception: Test Loggers

The only time to use different names is in tests:

```r
test_that("logger works", {
  log_capture <- logger() %>% with_receivers(to_itself())
  result <- log_capture(NOTE("test"))
  expect_equal(result$message, "test")
})
```

---

## Migration Checklist

Files to update:

- [ ] README.md - Main examples section
- [ ] README.md - Tag-based hierarchy section
- [ ] README.md - GxP validation examples
- [ ] README.md - Tidylog examples
- [ ] README.md - Use cases section
- [ ] R/validation-helpers.R - Example code
- [ ] R/tidylog-integration.R - Example code
- [ ] R/logger-helpers.R - Example code
- [ ] vignettes/gxp-validation.Rmd
- [ ] vignettes/getting-started.Rmd
- [ ] vignettes/patterns.Rmd
- [ ] examples/middleware/*.R

---

## Pattern Summary

**ONE RULE:**
- Package exports `log_this` (void logger)
- Users create/configure their own `log_this`
- In scopes, configure `log_this` locally
- Never create `log_app`, `log_db`, `log_api`, etc.
