# Implementation Decisions Log

**Project:** logthis v0.1.0 Enhanced Receiver Expansion
**Started:** 2025-10-08
**Status:** In Progress

This document tracks architectural and design decisions made during the implementation of new receivers, formatters, and async logging support.

---

## Table of Contents

1. [Phase 1: Core TODOs](#phase-1-core-todos)
2. [Phase 2: HTTP Infrastructure](#phase-2-http-infrastructure)
3. [Phase 3: Tabular Formats](#phase-3-tabular-formats)
4. [Phase 4: System Integration](#phase-4-system-integration)
5. [Phase 5: Async Research](#phase-5-async-research)

---

## Phase 1: Core TODOs

### Decision 1.1: `with_tags.log_event_level()` Implementation Pattern

**Date:** 2025-10-08
**Status:** ✅ IMPLEMENTED
**Updated:** 2025-10-08 (Custom levels only restriction)

**Context:**
Need to implement auto-tagging for event levels (e.g., `AUDIT() %>% with_tags("security")` so all AUDIT events get "security" tag automatically).

**Decision:**
Follow existing `with_tags.logger()` pattern (R/logger.R:375-398) with **RESTRICTION: Custom levels only**:
- Store tags in `log_event_level` attributes
- Combine with event-level tags when creating events
- Tag priority: event-level → event_level constructor → logger-level
- **Reject built-in levels**: Cannot tag LOWEST, TRACE, DEBUG, NOTE, MESSAGE, WARNING, ERROR, CRITICAL, HIGHEST

**Built-in Levels (Protected):**
- LOWEST (0), TRACE (10), DEBUG (20), NOTE (30), MESSAGE (40)
- WARNING (60), ERROR (80), CRITICAL (90), HIGHEST (100)

**Custom Level Usage (Allowed):**
```r
# Create custom level
AUDIT <- log_event_level("AUDIT", 70)

# Add tags to custom level (ALLOWED)
AUDIT <- AUDIT %>% with_tags("security", "compliance")

# Now all AUDIT events auto-tagged
log_this(AUDIT("User accessed sensitive data"))
# -> tags: ["security", "compliance"]

# Try to tag built-in level (REJECTED)
WARNING <- WARNING %>% with_tags("my-tag")
# Error: Cannot add tags to built-in level 'WARNING'
```

**Validation:**
Check `attr(x, "level_class")` against `.BUILTIN_LEVELS` constant:
```r
.BUILTIN_LEVELS <- c("LOWEST", "TRACE", "DEBUG", "NOTE", "MESSAGE",
                     "WARNING", "ERROR", "CRITICAL", "HIGHEST")
```

**Rationale:**
- Built-in levels are standardized - tagging them would cause unexpected behavior
- Custom levels are user-defined and may need domain-specific auto-tagging (AUDIT, SECURITY, BUSINESS, etc.)
- Prevents users from accidentally modifying standard level behavior
- Clear separation: built-in = universal, custom = domain-specific

**Documentation Emphasis:**
- Roxygen examples show ONLY custom levels
- Error message explicitly states "built-in level" restriction
- README section on custom levels highlights tagging capability

**Alternatives Considered:**
- Allow all levels: Violates principle of least surprise, built-in levels should behave consistently
- Global tag registry: Too much state, harder to reason about
- Function wrapping: Would break event level equality checks

---

### Decision 1.2: Shiny Level-to-Type Mapping

**Date:** 2025-10-08
**Status:** ✅ IMPLEMENTED

**Context:**
`to_shinyalert()` and `to_notif()` currently hardcode `type = "error"`. Need proper level mapping.

**Decision:**
Create package-level constant `.SHINY_TYPE_MAP` in R/aaa.R with helper function:
```r
.SHINY_TYPE_MAP <- list(
  shinyalert = list(
    levels = c(0, 20, 30, 40, 60, 80),
    types = c("info", "info", "success", "info", "warning", "error")
  ),
  notif = list(
    levels = c(0, 20, 30, 40, 60, 80),
    types = c("default", "default", "message", "message", "warning", "error")
  )
)

get_shiny_type <- function(level_number, receiver_type)
# Returns appropriate type using findInterval()
```

**Implementation Details:**
- `shinyalert` types: info (0-19, 20-29, 40-59), success (30-39), warning (60-79), error (80+)
- `notif` types: default (0-29), message (30-59), warning (60-79), error (80+)
- NOTE (30-39) maps to "success" for shinyalert (positive feedback) and "message" for notif
- Uses `findInterval()` for O(log n) efficient lookup (same pattern as color map)

**Rationale:**
- Follows existing `.LEVEL_COLOR_MAP` pattern
- Centralizes mapping logic
- Easy to adjust thresholds
- Different mappings for different UX contexts (modal vs inline)

**Alternatives Considered:**
- Per-receiver config: Too flexible, users would have to repeat config
- Dynamic calculation: Overhead for every event
- Same mapping for both: Different UX contexts need different visual priorities

---

## Phase 2: HTTP Infrastructure

### Decision 2.1: Webhook Handler Architecture

**Date:** 2025-10-08
**Status:** ✅ IMPLEMENTED

**Context:**
Need generic HTTP handler that works with any formatter (text, JSON, CSV, etc.).

**Decision:**
Implement `on_webhook()` as backend handler (like `on_local()`, `on_s3()`):
```r
to_json() %>% on_webhook(url, method = "POST", headers = NULL, auth = NULL)
to_text() %>% on_webhook(url, method = "POST")
```

**Implementation Details:**
- Use `httr2` package (modern, active development, better than `httr`)
- Register as backend: `.register_backend("webhook", .build_webhook_receiver)`
- Support retry with exponential backoff (httr2::req_retry)
- Support authentication: Bearer token, Basic auth, custom headers
- No buffering by default (sync writes), optional buffering via `buffer = TRUE`

**Rationale:**
- Consistent with existing formatter/handler pattern
- `httr2` has better API than `httr` (request building, retries, auth)
- Flexibility: any formatter + any webhook endpoint

**Alternatives Considered:**
- `httr` package: Older, more complex API
- `curl` package: Too low-level, would need to implement retries/auth ourselves
- Standalone receiver: Less composable, duplicates formatting code

---

### Decision 2.2: Teams Receiver - Standalone vs Formatter+Handler

**Date:** 2025-10-08
**Status:** ✅ IMPLEMENTED

**Context:**
Microsoft Teams requires MessageCard JSON format with specific structure. Two options:
1. `to_teams()` formatter + `on_webhook()`
2. `to_teams()` complete receiver

**Decision:**
Implement `to_teams()` as **complete receiver** (not formatter+handler).

**Signature:**
```r
to_teams(webhook_url, title = "Application Logs", theme_color = NULL,
         lower = WARNING, upper = HIGHEST, ...)
```

**Rationale:**
- MessageCard format is tightly coupled to Teams API
- No use case for "Teams format to local file" or "Teams format to S3"
- Simpler user API: one function call instead of two
- Level→color mapping is intrinsic to Teams visual design
- Still reuses `httr2` internally for HTTP POST

**MessageCard Structure:**
```json
{
  "@type": "MessageCard",
  "@context": "https://schema.org/extensions",
  "summary": "{title}",
  "themeColor": "ff0000",
  "sections": [{
    "activityTitle": "[ERROR:80] Application error occurred",
    "facts": [
      {"name": "Timestamp", "value": "2025-10-08 14:32:10"},
      {"name": "Level", "value": "ERROR (80)"},
      {"name": "Tags", "value": "api, database"}
    ],
    "text": "Failed to connect to database: timeout"
  }]
}
```

**Level→Color Mapping:**
- CRITICAL/ERROR (80-100): `#DC143C` (crimson)
- WARNING (60-79): `#FFA500` (orange)
- MESSAGE/NOTE (30-59): `#4682B4` (steel blue)
- DEBUG/TRACE (0-29): `#808080` (gray)

**Alternatives Considered:**
- Formatter approach: Overengineered, no real use case
- Slack-style webhook: Different format, will implement separately if needed

---

## Phase 3: Tabular Formats

### Decision 3.1: CSV Formatter - Schema and Escaping

**Date:** 2025-10-08
**Status:** ✅ IMPLEMENTED

**Context:**
CSV formatter needs to handle tags (list), custom fields (variable types), and escaping.

**Decision:**
Implement `to_csv()` as formatter with these specs:

**Signature:**
```r
to_csv(separator = ",", quote = "\"", headers = TRUE, na_string = "NA")
```

**Schema (column order):**
1. time (ISO 8601 string)
2. level (string)
3. level_number (integer)
4. message (string, quoted if contains separator/newline)
5. tags (pipe-delimited: "tag1|tag2|tag3", or empty string)
6. Custom fields (appended dynamically, names in header row)

**Escaping Rules:**
- Use `utils::write.table()` logic: quote strings with separator/quotes/newlines
- Escape quotes with double-quotes: `"He said ""hello"""`
- Tags: collapse with `|` separator (no quoting within tag list)

**Rationale:**
- Standard CSV format, readable by Excel/Pandas/R
- Pipe-delimited tags avoid nested quoting complexity
- Custom fields support exploratory data logging
- `headers = TRUE` writes header row on first event (track with closure state)

**Alternatives Considered:**
- JSON-encoded tags: Harder to read in Excel
- Separate tag columns: Unpredictable schema width
- `jsonlite::stream_out`: Not true CSV, harder to parse

---

### Decision 3.2: Parquet/Feather - Buffering Architecture

**Date:** 2025-10-08
**Status:** Pending Implementation

**Context:**
Parquet and Feather are columnar formats - writing row-by-row is extremely inefficient. Need buffering.

**Decision:**
Implement as **formatters** with special `requires_buffering = TRUE` flag:

**Formatter Side:**
```r
to_parquet(compression = "snappy", row_group_size = 10000)
to_feather(compression = "lz4")
```
- Formatters set `config$requires_buffering = TRUE`
- Formatters return *data frame row* (not string)
- Config stores format-specific options

**Handler Side:**
- Handlers detect `requires_buffering` flag
- Build receiver with buffer (reuse S3/Azure pattern)
- Accumulate rows in data frame
- Flush when threshold reached or manually triggered
- Use Arrow dataset API for appending to existing files

**Arrow Schema:**
```r
schema(
  time = timestamp(unit = "ms", timezone = "UTC"),
  level = utf8(),
  level_number = int32(),
  message = utf8(),
  tags = list_of(utf8()),  # Arrow list column
  # Custom fields added dynamically with inferred types
)
```

**Rationale:**
- Separates format (what) from storage (where)
- Reuses proven buffering pattern from S3/Azure
- Arrow handles schema evolution gracefully
- List column for tags preserves structure

**Alternatives Considered:**
- Standalone receivers: Violates formatter/handler separation
- String-based formatting: Impossible for columnar formats
- Always write full file: Inefficient, doesn't support append

---

### Decision 3.3: Handler Buffering Detection

**Date:** 2025-10-08
**Status:** ✅ IMPLEMENTED

**Context:**
Handlers (on_local, on_s3, on_azure) need to detect if formatter requires buffering.

**Decision:**
Modify `.build_local_receiver()` to check `config$requires_buffering` and dispatch:

```r
.build_local_receiver <- function(formatter, config) {
  if (isTRUE(config$requires_buffering)) {
    return(.build_buffered_local_receiver(formatter, config))
  }
  # Standard line-by-line receiver for text/JSON/CSV
}
```

**Implementation Details:**

**`.build_buffered_local_receiver()` (R/receivers.R:1106-1229):**
- Accumulates events as data frame rows (not strings)
- Uses `%||%` operator for default flush_threshold (1000 events)
- Flush logic:
  - **Parquet**: Uses `arrow::write_parquet()`, reads existing file for append
  - **Feather**: Uses `arrow::write_feather()`, reads existing file for append
  - Applies compression at write time
- Exposes `flush()` and `get_buffer_size()` attributes
- Fallback to `rbind()` if `dplyr::bind_rows()` unavailable

**on_local() Update:**
- Added `flush_threshold = 1000` parameter
- Ignored for line-based formats (text/JSON/CSV)
- Used for buffered formats (Parquet/Feather)

**S3/Azure Buffering:**
- Already have buffering built-in (for text/JSON)
- **TODO**: Verify they handle data frame rows from Parquet/Feather formatters
- May need similar dispatcher pattern if they expect strings only

**Rationale:**
- Clean separation: line-based vs batch-based
- Reuses existing backend registry
- Backward compatible with existing formatters
- Data frame accumulation is natural for columnar formats

**Alternatives Considered:**
- Always buffer: Overhead for simple text logging
- Separate handler functions: Duplicates code, confusing API
- Single unified buffer: Complex type handling (string vs data frame)

---

## Phase 4: System Integration

### Decision 4.1: Syslog Implementation - Protocol and Transport

**Date:** 2025-10-08
**Status:** ✅ IMPLEMENTED

**Context:**
Syslog has two protocols (RFC 3164 old, RFC 5424 new) and multiple transports (local socket, UDP, TCP, TLS).

**Decision:**
Implement `to_syslog()` as **complete receiver** supporting both protocols:

**Signature:**
```r
to_syslog(host = "localhost", port = 514, protocol = c("rfc3164", "rfc5424"),
          transport = c("udp", "tcp", "unix"), facility = "user",
          app_name = "R", lower = LOWEST, upper = HIGHEST)
```

**Protocol Formats:**

**RFC 3164 (BSD syslog, default for compatibility):**
```
<priority>timestamp hostname app_name[pid]: message
<134>Oct  8 14:32:10 myhost R[12345]: Application started
```

**RFC 5424 (modern):**
```
<priority>version timestamp hostname app_name pid msgid structured-data message
<134>1 2025-10-08T14:32:10.123Z myhost R 12345 - - Application started
```

**Transport:**
- `unix`: Connect to `/dev/log` socket (Linux/Mac)
- `udp`: UDP socket to host:port (fast, no delivery guarantee)
- `tcp`: TCP socket to host:port (reliable, ordered)
- No TLS initially (v0.2.0 feature)

**Level→Severity Mapping:**
```r
.SYSLOG_SEVERITY_MAP <- c(
  # logthis level ranges → syslog severity (0-7)
  7,  # 0-9:   LOWEST, TRACE     → debug (7)
  7,  # 10-19: TRACE             → debug (7)
  7,  # 20-39: DEBUG             → debug (7)
  6,  # 40-49: NOTE, MESSAGE     → info (6)
  5,  # 50-59: MESSAGE           → notice (5)
  4,  # 60-79: WARNING           → warning (4)
  3,  # 80-89: ERROR             → error (3)
  2,  # 90-99: CRITICAL          → critical (2)
  0   # 100:   HIGHEST           → emergency (0)
)
```

**Facility Options:**
- "user" (default, facility 1)
- "local0" through "local7" (facilities 16-23, for custom use)
- "daemon", "mail", "syslog", etc.

**Implementation:**
- Use raw sockets (`socketConnection()` from base R)
- No external dependencies for basic UDP/Unix socket
- Format message per RFC spec
- Calculate priority: `(facility * 8) + severity`

**Rationale:**
- RFC 3164 default (wider compatibility with old syslog daemons)
- UDP default (standard syslog transport, fire-and-forget)
- Complete receiver (no use case for "syslog format to file")
- No external packages needed for basic functionality

**Alternatives Considered:**
- `rsyslog` package: Doesn't exist, would need to create
- Only RFC 5424: Breaks compatibility with older systems
- Only local socket: Doesn't work for remote logging
- Formatter approach: Syslog needs network handling, not just formatting

---

## Phase 5: Async Research

### Decision 5.1: Async Package Evaluation Criteria

**Date:** 2025-10-08
**Status:** Pending Research

**Context:**
Need to choose async backend for high-throughput logging. Three contenders: `future`, `mirai`, `nanonext`.

**Evaluation Criteria:**

1. **Latency Overhead**: Time to queue a log event
2. **Throughput**: Events/second sustainable rate
3. **Memory Efficiency**: RAM per queued event
4. **API Simplicity**: Learning curve for users
5. **Maturity**: CRAN history, issue tracker health
6. **Maintenance**: Active development, bus factor
7. **Dependencies**: Dependency tree size
8. **Integration**: Ease of integration with existing receivers

**Test Scenarios:**
- Scenario A: High-frequency logging (10,000 events/sec)
- Scenario B: Bursty traffic (1,000 events in 100ms, then idle)
- Scenario C: Long-running process (1M events over 1 hour)
- Scenario D: Multiple concurrent loggers (10 loggers × 1,000 events/sec)

**Benchmark Metrics:**
- Mean/median/p95/p99 latency
- Memory high-water mark
- CPU utilization
- Event loss rate (if any)

**Expected Outcome:**
Document in `docs/async-logging-research.md` with recommendation for v0.2.0 implementation.

---

## Decision 5.2: Async API Design (Tentative)

**Date:** 2025-10-08
**Status:** Pending Research

**Context:**
Need to design user-facing API for async logging. Must be backward compatible.

**Proposed Design (subject to change after research):**

**Option A: Async Wrapper (PREFERRED)**
```r
# Wrap any receiver with async behavior
async_recv <- to_console() %>% with_async(backend = "mirai", buffer_size = 1000)
log_this <- logger() %>% with_receivers(async_recv)

# Flush on demand
attr(async_recv, "flush")()

# Get queue stats
attr(async_recv, "queue_size")()
```

**Option B: Logger-Level Async**
```r
# All receivers become async
log_this <- logger() %>%
  with_async(backend = "mirai", buffer_size = 1000) %>%
  with_receivers(to_console(), to_text_file("app.log"))
```

**Option C: Receiver Parameter**
```r
# Per-receiver opt-in
to_console(async = TRUE, buffer_size = 1000)
to_text_file("app.log", async = TRUE)
```

**Rationale for Option A:**
- Most flexible: mix async and sync receivers
- Backward compatible: existing code unchanged
- Follows existing pattern (`with_*` modifiers)
- Clean separation of concerns

**Implementation Sketch (Option A):**
```r
with_async <- function(receiver, backend = "mirai", buffer_size = 1000, flush_interval = NULL) {
  # Create async task queue
  queue <- backend_create_queue(backend, buffer_size)

  # Wrap receiver in async dispatcher
  async_recv <- receiver(function(event) {
    queue_push(queue, event)

    # Async worker dequeues and calls original receiver
    if (queue_size(queue) >= buffer_size || flush_interval_reached()) {
      queue_flush_async(queue, receiver)
    }

    invisible(NULL)
  })

  # Attach management functions
  attr(async_recv, "flush") <- function() queue_flush_sync(queue, receiver)
  attr(async_recv, "queue_size") <- function() queue_size(queue)

  async_recv
}
```

**Open Questions:**
- Error handling: If async worker fails, how to notify?
- Shutdown: How to ensure queue drains on process exit?
- Backpressure: What if queue fills up? Drop events or block?

**To Be Finalized:** After benchmarking all three packages in Phase 5.

---

## Summary of Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Event level tagging | Follow `with_tags.logger()` pattern | Consistency, functional style |
| Shiny type mapping | Package-level constant | Follows `.LEVEL_COLOR_MAP` pattern |
| Webhook handler | `on_webhook()` using `httr2` | Composable, modern HTTP client |
| Teams receiver | Standalone `to_teams()` | No use case for Teams format elsewhere |
| CSV formatter | Standard CSV with pipe-delimited tags | Excel compatibility, simple schema |
| Parquet/Feather | Formatters with `requires_buffering` flag | Separates format from storage, reuses buffering pattern |
| Handler buffering | Detect flag, dispatch to buffered builders | Clean separation, backward compatible |
| Syslog receiver | Standalone with RFC 3164/5424 support | Protocol needs network handling, no external deps |
| Async package | TBD (research first) | Need benchmarks before committing |
| Async API | Option A (wrapper) preferred | Most flexible, backward compatible |

---

## Notes for Future Development

- Consider `to_slack()` receiver (similar to Teams but different webhook format)
- Consider `to_discord()` receiver (gaming/developer communities)
- TLS support for syslog (RFC 5425) in v0.2.0
- Async shutdown hooks for clean queue draining
- Receiver middleware pattern for cross-cutting concerns (rate limiting, sampling, etc.)

---

**Last Updated:** 2025-10-08
**Next Review:** After Phase 1 completion
