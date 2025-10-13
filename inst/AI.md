# AI Assistant Guide for logthis

**Purpose**: Navigational index and decision trees for AI-assisted development
**Philosophy**: Code is truth. This doc is a map to that truth.

**Last Updated**: 2025-10-13

---

## Essential Links

- **Comprehensive Guide**: [`notes/CLAUDE.md`](../notes/CLAUDE.md) - Complete architecture, patterns, gotchas
- **Function Contracts**: [`inst/contracts.md`](contracts.md) - Auto-generated from code (single source of truth)
- **Examples**: [`vignettes/`](../logthis/vignettes/) - Usage patterns in context
- **Tests**: [`tests/testthat/`](../logthis/tests/testthat/) - Executable specifications

---

## Quick Start: Understanding logthis in 3 Minutes

### Core Pattern
```r
log_this <- logger() %>%                          # Create logger
  with_receivers(to_console()) %>%                # Add output
  with_limits(lower = NOTE, upper = HIGHEST)      # Filter events

log_this(NOTE("Hello, AI!"))                      # Log event
```

### Key Insight
Everything is **functional** and **composable** via `%>%`:
- Loggers are closures (not objects)
- `with_*()` functions return NEW loggers (immutable)
- Receivers are functions wrapped for safety
- Contracts are executable code (not comments)

**See**: [`R/logger.R:43-127`](../logthis/R/logger.R#L43-L127) for implementation

---

## Architecture at a Glance

```
Event → Logger Middleware → Logger Filter → Apply Logger Tags →
  ├─ Receiver 1 Middleware → Receiver 1 Filter → Output 1
  ├─ Receiver 2 Middleware → Receiver 2 Filter → Output 2
  └─ Receiver N Middleware → Receiver N Filter → Output N
```

**Details**: [`notes/CLAUDE.md#Architecture`](../notes/CLAUDE.md#architecture--key-concepts)

---

## Decision Trees (Where to Look)

### "I want to add a new storage backend"

```
Q: What kind of storage?

├─ Standard format (CSV, JSON, Parquet)?
│  ├─ File: R/receiver-formatters.R
│  ├─ Pattern: Create to_<format>() returning log_formatter
│  ├─ Then: Attach with on_<backend>() handler
│  └─ See: to_json() %>% on_local() pattern
│
├─ Cloud storage (S3, Azure, GCS)?
│  ├─ File: R/receiver-handlers.R
│  ├─ Pattern: Create on_<cloud>() handler
│  ├─ Integrates with formatters: to_json() %>% on_s3()
│  └─ See: on_s3() implementation
│
└─ Protocol-specific (Teams, Slack, Syslog)?
   ├─ File: R/receiver-network.R
   ├─ Pattern: Standalone to_<protocol>() returning log_receiver
   ├─ Format + transport are coupled (can't split)
   └─ See: to_teams(), to_syslog()
```

**Reference**: [`R/receiver-formatters.R`](../logthis/R/receiver-formatters.R), [`R/receiver-handlers.R`](../logthis/R/receiver-handlers.R), [`R/receiver-network.R`](../logthis/R/receiver-network.R)

---

### "I want to add validation to a function"

```
Q: What are you validating?

├─ Function inputs from caller?
│  ├─ Use: require_that() in function body
│  ├─ Failure means: Caller error (bad usage)
│  └─ See: R/contracts.R:require_that()
│
├─ Function outputs/results?
│  ├─ Use: ensure_that() before return
│  ├─ Failure means: Bug in function (report to maintainer)
│  └─ See: R/contracts.R:ensure_that()
│
└─ Object state consistency?
   ├─ Use: check_invariant() at strategic points
   ├─ Failure means: Corruption (serious bug)
   └─ See: R/contracts.R:check_invariant()
```

**Reference**: [`R/contracts.R`](../logthis/R/contracts.R)

---

### "I want to modify event flow"

```
Q: Transform or filter?

├─ Transform events (modify content)?
│  ├─ Where: Before logger filtering?
│  │  ├─ Create: middleware(function(event) { ... })
│  │  ├─ Apply: logger %>% with_middleware(mw)
│  │  └─ See: R/logger.R:with_middleware.logger()
│  │
│  └─ Where: Per-receiver?
│     ├─ Create: middleware(function(event) { ... })
│     ├─ Apply: receiver %>% with_middleware(mw)
│     └─ See: R/logger.R:with_middleware.log_receiver()
│
└─ Filter events (drop by level)?
   ├─ Where: Before all receivers?
   │  ├─ Apply: logger %>% with_limits(lower, upper)
   │  └─ See: R/logger.R:with_limits.logger()
   │
   └─ Where: Per-receiver?
      ├─ Apply: receiver %>% with_limits(lower, upper)
      └─ See: R/logger.R:with_limits.log_receiver()
```

**Reference**: [`R/logger.R`](../logthis/R/logger.R)

---

## Critical Invariants (NEVER Break These)

Source of truth: Code in [`R/contracts.R`](../logthis/R/contracts.R) and [`tests/testthat/test-contracts.R`](../logthis/tests/testthat/test-contracts.R)

### Logger Objects
```r
length(config$receivers) == length(config$receiver_labels)
length(config$receivers) == length(config$receiver_names)
config$limits$lower >= 0 && config$limits$lower <= 99
config$limits$upper >= 1 && config$limits$upper <= 100
config$limits$lower <= config$limits$upper
```

### Event Objects
```r
event$level_number >= 0 && event$level_number <= 100
!is.null(event$time)
!is.null(event$message)
!is.null(event$level_class)
```

### Receiver Functions
- Must return `invisible(NULL)`
- Must not throw (wrapped with `tryCatch`)
- Must check `event$level_number` if has filtering

**Verify**: Run `testthat::test_file("tests/testthat/test-contracts.R")`

---

## Change Impact Matrix

### ⚠️ CRITICAL FILES (Breaking Changes)

| File | Functions | Breaks If Modified | Safe Changes |
|------|-----------|-------------------|--------------|
| **R/logger.R** | `logger()`, `with_receivers()`, `with_limits()`, `with_tags()`, `with_middleware()` | ALL user code, ALL vignettes, 50+ tests | Add optional params (defaults), improve errors, add validation, optimize (same behavior) |
| **R/receiver-core.R** | `receiver()` | ALL receivers (60+ functions), user-defined receivers | Add optional params (defaults), enhance validation |
| **R/log_event_levels.R** | `log_event_level()`, `NOTE()`, `WARNING()`, etc. | All event creation, all filtering logic | Add new levels, improve validation |

### ✅ ISOLATED FILES (Low Risk)

| File | Impact | Safe to Modify |
|------|--------|----------------|
| **R/print-logger.R** | Display only | ✅ YES (doesn't affect behavior) |
| **R/receiver-console.R** | Console output only | ✅ YES (wrapped in safely()) |
| **R/flush.R** | Buffer flushing | ✅ YES (isolated feature) |

**Full matrix**: [`inst/AI.md#change-impact-matrix`](AI.md#change-impact-matrix)

---

## Common Patterns (Copy-Paste Templates)

### Pattern 1: Add a Line-Based Formatter

**File**: `R/receiver-formatters.R`

```r
#' @export
#' @family formatters
to_csv <- function(separator = ",", quote = "\"", headers = TRUE) {
  # Closure state for headers
  headers_written <- FALSE

  fmt_func <- formatter(function(event) {
    # Write headers on first call
    if (!headers_written && headers) {
      headers_written <<- TRUE
      # ... header logic
    }

    # CRITICAL: Convert level_number to numeric (it's an S3 class!)
    fields <- c(
      as.character(event$time),
      event$level_class,
      as.character(as.numeric(event$level_number)),  # Convert S3 to numeric!
      event$message
    )

    paste(fields, collapse = separator)
  })

  # Attach config
  attr(fmt_func, "config") <- list(
    format_type = "csv",
    separator = separator,
    backend = NULL,
    backend_config = list(),
    lower = NULL,
    upper = NULL
  )

  fmt_func
}
```

**See**: [`R/receiver-formatters.R`](../logthis/R/receiver-formatters.R) for complete examples

---

### Pattern 2: Add Contracts to Function

**File**: Any `R/*.R` file

```r
my_function <- function(x, y, append = TRUE) {
  # PRECONDITIONS: Validate inputs
  require_that(
    "x must be numeric" = is.numeric(x),
    "y must be positive" = is.numeric(y) && y > 0,
    "append must be logical" = is.logical(append)
  )

  # ... implementation ...

  result <- do_something(x, y)

  # POSTCONDITIONS: Validate output
  ensure_that(
    "result is not NULL" = !is.null(result),
    "result has expected class" = inherits(result, "expected_class")
  )

  result
}
```

**See**: [`R/contracts.R`](../logthis/R/contracts.R) for contract functions

---

### Pattern 3: Immutable Logger Updates

```r
# GOOD: Return new logger (immutable)
with_receivers <- function(logger, ..., append = TRUE) {
  check_invariant(
    "logger has config" = !is.null(attr(logger, "config"))
  )

  new_config <- modify_config(attr(logger, "config"), ...)
  attr(logger, "config") <- new_config

  check_invariant(
    "receivers match labels" =
      length(new_config$receivers) == length(new_config$receiver_labels)
  )

  logger  # Return (possibly new) logger
}

# BAD: Mutate in place (spooky action at a distance!)
with_receivers_bad <- function(logger, ...) {
  attr(logger, "config")$receivers <- ...  # DON'T DO THIS
  invisible(NULL)
}
```

**See**: [`R/logger.R:188-281`](../logthis/R/logger.R#L188-L281)

---

## File Locations (Quick Reference)

### Core Functionality
- [`R/logger.R`](../logthis/R/logger.R) - Logger creation, `with_*` configuration
- [`R/log_event_levels.R`](../logthis/R/log_event_levels.R) - Event levels (NOTE, WARNING, etc.)
- [`R/receiver-core.R`](../logthis/R/receiver-core.R) - Receiver constructor
- [`R/contracts.R`](../logthis/R/contracts.R) - Contract enforcement system

### Receivers
- [`R/receiver-console.R`](../logthis/R/receiver-console.R) - Console output
- [`R/receiver-formatters.R`](../logthis/R/receiver-formatters.R) - Formatters (text, JSON, CSV, Parquet)
- [`R/receiver-handlers.R`](../logthis/R/receiver-handlers.R) - Handlers (local, S3, Azure, webhook)
- [`R/receiver-network.R`](../logthis/R/receiver-network.R) - Network protocols (Teams, Syslog, email)
- [`R/receiver-async.R`](../logthis/R/receiver-async.R) - Async/deferred logging

### Utilities & Extensions
- [`R/aaa.R`](../logthis/R/aaa.R) - Package-level utils (loaded first)
- [`R/zzz.R`](../logthis/R/zzz.R) - Package hooks (loaded last)
- [`R/validation-helpers.R`](../logthis/R/validation-helpers.R) - GxP validation wrappers
- [`R/tidylog-integration.R`](../logthis/R/tidylog-integration.R) - Tidylog integration

### Display & Buffer Management
- [`R/print-logger.R`](../logthis/R/print-logger.R) - Logger printing
- [`R/flush.R`](../logthis/R/flush.R) - Buffer flushing

### Tests (Executable Specifications)
- [`tests/testthat/test-contracts.R`](../logthis/tests/testthat/test-contracts.R) - Contract verification
- [`tests/testthat/test-logger.R`](../logthis/tests/testthat/test-logger.R) - Logger functionality
- [`tests/testthat/test-receivers.R`](../logthis/tests/testthat/test-receivers.R) - Receiver behavior
- [`tests/testthat/test-log-event-levels.R`](../logthis/tests/testthat/test-log-event-levels.R) - Event levels
- [`tests/testthat/test-tags.R`](../logthis/tests/testthat/test-tags.R) - Tagging system

---

## Common Gotchas (Read Before Modifying)

### Gotcha #1: level_number is S3 Class, Not Numeric

**Problem**: `event$level_number` has class `c("log_event_level_number", "numeric")`

**Breaks**: JSON/CSV serialization, data frames, HTTP payloads

**Fix**: Always convert: `as.numeric(event$level_number)`

**See**: [`notes/CLAUDE.md#8-critical-level_number-serialization`](../notes/CLAUDE.md#8-critical-level_number-serialization)

---

### Gotcha #2: Receiver Functions Must Return invisible(NULL)

**Problem**: Receivers are called for side effects, not values

**Why**: Logger chains events through return values - receivers shouldn't interfere

**See**: [`R/receiver-core.R`](../logthis/R/receiver-core.R)

---

### Gotcha #3: Receivers/Labels Must Always Match Length

**Invariant**: `length(config$receivers) == length(config$receiver_labels)`

**Breaks**: Logger printing, error reporting

**Check**: Use `check_invariant()` in `with_receivers()`

**See**: [`tests/testthat/test-contracts.R`](../logthis/tests/testthat/test-contracts.R)

---

## Workflow for AI Assistants

### Before Modifying Code

1. **Read contracts**: Check [`inst/contracts.md`](contracts.md) for function you're modifying
2. **Check impact**: Consult [Change Impact Matrix](#change-impact-matrix)
3. **Read tests**: Look at [`tests/testthat/test-*.R`](../logthis/tests/testthat/) for expected behavior
4. **Check invariants**: Review [Critical Invariants](#critical-invariants-never-break-these)

### While Modifying Code

1. **Preserve patterns**: Follow [Common Patterns](#common-patterns-copy-paste-templates)
2. **Add contracts**: Use `require_that()`, `ensure_that()`, `check_invariant()`
3. **Update tests**: Add tests to relevant `test-*.R` file
4. **Check cross-refs**: Update [`notes/CLAUDE.md`](../notes/CLAUDE.md) if architecture changes

### After Modifying Code

1. **Run tests**: `devtools::test()` must pass
2. **Check docs**: `devtools::document()` to update roxygen
3. **Regenerate contracts**: `Rscript dev/generate_contract_docs.R`
4. **Verify invariants**: `testthat::test_file("tests/testthat/test-contracts.R")`

---

## When Documentation is Out of Sync

### Source of Truth Hierarchy

1. **Code** (`R/*.R`) - Always correct by definition
2. **Tests** (`tests/testthat/`) - Executable specs
3. **Contracts** (`inst/contracts.md`) - Generated from code (regenerate if stale)
4. **Comprehensive Guide** (`notes/CLAUDE.md`) - Manual curation (update when architecture changes)
5. **This file** (`inst/AI.md`) - Navigation index (update when structure changes)

### If You Find a Discrepancy

1. Trust the code
2. Check tests for actual behavior
3. Update derived docs if needed
4. Regenerate contracts: `Rscript dev/generate_contract_docs.R`

---

## Questions or Issues?

- **Not sure where to look?** Use decision trees above
- **Contract violation?** Check [`inst/contracts.md`](contracts.md)
- **Test failing?** See test file for specification
- **Need more context?** See [`notes/CLAUDE.md`](../notes/CLAUDE.md)
- **Found a bug?** Report at [github.com/iqis/logthis/issues](https://github.com/iqis/logthis/issues)

---

**Remember**: This doc is a **map**. The code is the **territory**. When in doubt, read the code.
