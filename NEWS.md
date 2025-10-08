# logthis 0.1.0.9000

## New Features

### Core Functionality
* Implemented `with_tags.log_event_level()` for auto-tagging custom event levels
  - Only custom levels can be tagged (built-in levels protected)
  - Adds `.BUILTIN_LEVELS` constant to prevent modification of standard levels
* Fixed Shiny level-to-type mapping with efficient lookup table (`.SHINY_TYPE_MAP`)
  - `get_shiny_type()` helper for mapping log levels to Shiny alert/notification types

### File & Format Receivers
* **CSV logging**: `to_csv()` formatter with proper field escaping
  - Supports custom separator, quote character, and headers
  - Tags stored as pipe-delimited strings
* **Parquet logging**: `to_parquet()` formatter for columnar storage
  - Requires `arrow` package
  - Buffered writes with configurable `flush_threshold`
  - Tags and custom fields stored as list columns
* **Feather logging**: `to_feather()` formatter for fast read/write
  - Requires `arrow` package
  - Similar buffering support as Parquet

### HTTP & Webhook Integration
* **Generic webhook**: `on_webhook()` handler for HTTP POST to any endpoint
  - Uses `httr2` for modern HTTP client
  - Auto-detects content-type from formatter (JSON/text)
  - Retry logic with configurable timeout and max attempts
* **Microsoft Teams**: `to_teams()` standalone receiver with Adaptive Cards
  - Full support for Power Automate webhooks
  - Color-coded log levels in card display
  - Metadata displayed as Facts in card body

### System Integration
* **Syslog**: `to_syslog()` receiver with RFC 3164/5424 support
  - Multiple transports: UDP, TCP, UNIX socket
  - Complete facility code mapping (kern, user, daemon, local0-7, etc.)
  - Log level to syslog severity mapping (0-7 scale)
  - Connection pooling with automatic reconnection

### Architecture Improvements
* **Buffered receivers**: New `requires_buffering` flag for columnar formats
  - `.build_buffered_local_receiver()` for data frame accumulation
  - `flush_threshold` parameter in `on_local()` for batch writes
* **Null-coalescing operator**: Added `%||%` for cleaner default value handling

## Documentation
* Created comprehensive 20-page async logging research document
  - Evaluated `future`, `mirai`, and `nanonext` packages
  - Recommendation: `mirai` for v0.2.0 async implementation
  - Performance benchmarks and implementation patterns documented
* Updated README with all new receivers organized by category
* Updated CLAUDE.md with new patterns (buffered formatters, standalone receivers, webhook handlers)
* Created docs/implementation-decisions.md documenting architectural choices
* Added 41 new tests for all receivers (total: 171+ tests passing)

## Breaking Changes

* None - all additions are backward compatible

## Dependencies

### New Suggests
* `httr2` - for webhook and Teams receivers
* `arrow` - for Parquet and Feather formatters
* Removed `httr` (replaced by `httr2`)

## Bug Fixes

* Fixed `level_number` serialization in JSON output (convert S3 class to numeric)
* Fixed Shiny type mapping edge cases with `findInterval()` approach

---

# logthis 0.1.0

* Initial CRAN submission (planned)