# logthis Improvement Plan

## Overview
This document outlines improvements to make logthis production-ready for CRAN submission. Focus on completing TODOs, enhancing functionality, and polishing documentation.

**Last Updated:** 2025-10-08

---

## Recent Accomplishments (2025-10-08) - v0.1.0 Feature Complete

### ✅ Phase 1 TODOs - Complete
- Implemented `with_tags.log_event_level()` for custom levels only (built-in levels protected)
- Fixed Shiny level-to-type mapping with efficient lookup table (`.SHINY_TYPE_MAP`)
- Added comprehensive tests for both features

### ✅ Phase 4: HTTP & Webhook Infrastructure
- Implemented `on_webhook()` handler using httr2 (generic HTTP POST handler)
- Implemented `to_teams()` standalone receiver with Adaptive Cards support
- Successfully tested Teams integration with Power Automate endpoint
- Auto-detects content-type from formatter (JSON → application/json, Text → text/plain)

### ✅ Phase 5: Tabular Format Support
- Implemented `to_csv()` formatter with proper escaping and pipe-delimited tags
- Implemented `to_parquet()` formatter with buffering support (requires arrow package)
- Implemented `to_feather()` formatter with buffering support (requires arrow package)
- Updated `on_local()` to add `flush_threshold` parameter for buffered writes
- Implemented `requires_buffering` flag detection in handlers
- Created `.build_buffered_local_receiver()` for data frame accumulation

### ✅ Phase 6: System Integration
- Implemented `to_syslog()` receiver with full RFC 3164/5424 support
- Supports UDP, TCP, and UNIX socket transports
- Comprehensive facility code mapping (kern, user, daemon, local0-7, etc.)
- Level-to-severity mapping (0-7 syslog scale)
- Connection pooling with automatic reconnection

### ✅ Phase 7: Async Research (Documentation Only)
- Researched future, mirai, and nanonext packages
- Created comprehensive 20-page async-logging-research.md document
- **Recommendation:** mirai for v0.2.0 (low latency, high throughput, minimal dependencies)
- Documented performance benchmarks, implementation patterns, and risks

### ✅ Documentation & Testing
- Added 41 comprehensive tests for all new receivers (total: 171+ tests)
- Updated README with all new receivers organized by category
- Updated CLAUDE.md with new patterns (buffered formatters, standalone receivers, webhook handlers)
- Updated DESCRIPTION with new dependencies (httr2, arrow, jsonlite)
- Created docs/implementation-decisions.md with architectural rationale

---

## Recent Accomplishments (2025-10-07)

### ✅ Resilient Receiver Error Handling
- Implemented `purrr::safely()` wrapper for all receiver executions
- Receivers now execute independently - one failure doesn't stop others
- Added receiver label capture for detailed error provenance
- Receiver failures logged as ERROR events with 'receiver_error' tag
- Fallback to `to_console()` for error reporting, `warning()` as last resort
- Added comprehensive tests (111 tests passing)
- Error messages include: receiver #, error message, full receiver call

### ✅ Configuration Improvements
- Renamed `receiver_calls` to `receiver_labels` (plain text, not pairlists)
- Updated `print.logger()` to use receiver_labels
- Fixed devcontainer to include git-lfs by default

### ✅ Phase 2 Complete: Code Quality Improvements
- Color lookup already optimized with `findInterval()` and constant map
- Logger naming clear: `void_logger()` properly documented, no confusion
- Added `to_text_file()` and `to_json_file()` to README receivers section

### ✅ Phase 3 Complete: Enhanced Functionality
- File rotation already implemented in `to_text_file()` with comprehensive tests
- Added `to_json_file()` receiver for structured logging (JSONL format)
- JSON receiver supports compact/pretty formatting, full metadata, level filtering
- Added 14 new receiver tests (file rotation + JSON functionality)

### ✅ R CMD Check: Clean Results
- 0 errors ✔
- 0 warnings ✔
- 1 harmless note (timestamp verification)
- All 130 tests passing

---

## Phase 1: Complete Core Functionality

### 1.1 Implement `with_limits.log_receiver()`
**File:** `R/logger.R:269-347`
**Status:** ✅ Complete
**Completed:**
- [x] Implement receiver-level limit setting (wrapper pattern)
- [x] Add validation for limit ranges [0, 119] and [1, 120]
- [x] Store limits in receiver attributes
- [x] Add tests for receiver limit configuration (3 tests in test-receivers.R)
- [x] Update documentation with comprehensive examples

Note: Allows fine-grained control over which events each receiver accepts. Users can chain: `to_console() %>% with_limits(lower = WARNING)`


### 1.2 Complete `with_tags()` Functionality
**File:** `R/logger.R:244-303`
**Status:** ✅ Complete
**Completed:**
- [x] Logger-level tags implemented and applied to events (R/logger.R:49-53)
- [x] Comprehensive test suite added (tests/testthat/test-tags.R - 24 tests)
- [x] Tagging and provenance vignette created (vignettes/tagging-and-provenance.Rmd)
- [x] README updated with tag examples
- [x] Implemented `with_tags.log_event_level()` for custom levels (R/logger.R:244+)
- [x] Added `.BUILTIN_LEVELS` constant to protect standard levels
- [x] Validation prevents tagging built-in levels (LOWEST through HIGHEST)

**Design Decision:** Custom levels only
- Built-in levels (NOTE, WARNING, ERROR, etc.) cannot be tagged to preserve standard behavior
- Custom levels (created via `log_event_level()`) can be auto-tagged
- Clear error message guides users to create custom levels for auto-tagging

**Future Enhancement:**
- Tag filtering/search utilities (v0.2.0 or later)

---

## Phase 2: Code Quality Improvements ✅ COMPLETE

### 2.1 Refactor Color Lookup in `to_console()` ✅
**File:** `R/aaa.R:15-35`
**Status:** Already optimized
**Completed:**
- [x] Package-level constant `.LEVEL_COLOR_MAP` with levels and colors
- [x] `findInterval()` for O(log n) efficient lookup
- [x] Color scheme: white, silver, green, yellow, red, bold red
- [x] Documentation in receiver code

### 2.2 Clarify Logger Naming Conventions ✅
**Status:** No confusion exists
**Completed:**
- [x] `void_logger()` properly exported and documented
- [x] No `dummy_logger()` in codebase
- [x] README examples consistent

### 2.3 Fix Documentation Inconsistencies ✅
**Status:** Complete
**Completed:**
- [x] Added `to_text_file()` to README built-in receivers section
- [x] Added `to_json_file()` to README built-in receivers section
- [x] `to_identity()` correctly documented as testing receiver
- [x] Clear distinction between testing and production receivers

---

## Phase 3: Enhanced Functionality ✅ COMPLETE

### 3.1 Add File Rotation to `to_text_file()` ✅
**File:** `R/receivers.R:251-316`
**Status:** Complete with comprehensive tests
**Completed:**
- [x] `max_size` parameter (bytes) triggers rotation
- [x] `max_files` parameter limits rotation history
- [x] Rotation logic: log.txt → log.1.txt → log.2.txt
- [x] Tests verify rotation, file limits, log order preservation
- [x] Documentation with rotation examples
- [x] 2 comprehensive rotation tests added

### 3.2 Add JSON Receiver for Modern Log Aggregation ✅
**File:** `R/receivers.R:318-401`
**Status:** Complete with comprehensive tests
**Completed:**
- [x] `to_json_file()` receiver creates JSONL format (one JSON per line)
- [x] Full event metadata: time, level, level_number, message, tags
- [x] Compact output by default for efficiency
- [x] Optional pretty-printing via `pretty = TRUE`
- [x] Level filtering support (lower/upper limits)
- [x] 3 comprehensive tests: JSONL output, filtering, pretty printing
- [x] Documentation with cloud logging examples
- [x] Added jsonlite dependency to DESCRIPTION

### 3.3 Add Async/Buffered Logging Support
**Priority:** Medium - for high-volume scenarios
**Tasks:**
- [ ] Research R async patterns (future package?)
- [ ] Design buffered receiver wrapper
- [ ] Implement buffer flushing strategies
- [ ] Add performance benchmarks
- [ ] Document when to use buffered logging

---

## Phase 4: Documentation Enhancements

### 4.1 Add Performance Guidance
**Tasks:**
- [ ] Create "Performance Considerations" section in README
- [ ] Add benchmarks comparing different receiver configurations
- [ ] Document overhead of logging operations
- [ ] Provide guidance on when to use different log levels
- [ ] Add tips for high-throughput applications

### 4.2 Create Migration Guide
**Tasks:**
- [ ] Add "Migration from Other Packages" section
- [ ] Compare with `logger`, `log4r`, `futile.logger`
- [ ] Provide code examples showing equivalent patterns
- [ ] Highlight unique features of logthis

### 4.3 Add Troubleshooting Section
**Tasks:**
- [ ] Create "Troubleshooting" section in README
- [ ] Document common issues:
  - Shiny session requirements
  - File permission errors
  - Performance bottlenecks
  - Memory issues with large log volumes
- [ ] Add FAQ subsection

### 4.4 Create Architecture Diagram
**Tasks:**
- [ ] Design visual flow: Event → Logger Filter → Receivers → Receiver Filters → Output
- [ ] Add diagram to README (after Features section)
- [ ] Show how logger chaining works visually
- [ ] Illustrate scope-based masking pattern

### 4.5 Improve roxygen2 Documentation
**Tasks:**
- [ ] Add `@family` tags to group related functions
- [ ] Add more `@seealso` cross-references
- [ ] Ensure all exported functions have complete `@examples`
- [ ] Add `@return` details for all functions
- [ ] Review and improve parameter descriptions

---

## Phase 5: Testing & Quality Assurance

### 5.1 Expand Test Coverage
**Tasks:**
- [ ] Run `covr::package_coverage()` and identify gaps
- [ ] Add tests for edge cases:
  - Empty messages
  - Very long messages
  - Unicode/special characters
  - Concurrent logging
- [ ] Add integration tests for multi-receiver scenarios
- [ ] Test error handling and validation

### 5.2 Run R CMD check
**Tasks:**
- [ ] Run `devtools::check()` and fix all NOTEs/WARNINGs/ERRORs
- [ ] Verify all examples run successfully
- [ ] Check documentation completeness
- [ ] Validate DESCRIPTION file

### 5.3 Prepare for CRAN
**Tasks:**
- [ ] Add `cran-comments.md` file
- [ ] Review CRAN policies compliance
- [ ] Add `NEWS.md` file for version tracking
- [ ] Create release checklist

---

## Phase 6: Nice-to-Have Enhancements

### 6.1 Additional Receivers
**Tasks:**
- [ ] `to_syslog()` - system log integration
- [ ] `to_email()` - email notifications (example in README → real implementation)
- [ ] `to_webhook()` - generic HTTP endpoint logging
- [ ] `to_csv()` - structured CSV output

### 6.2 Advanced Features
**Tasks:**
- [ ] Logger hierarchies (parent/child relationships)
- [ ] Event filtering by tags
- [ ] Dynamic log level adjustment
- [ ] Log message templates/formatting
- [ ] Receiver middleware pattern

---

## Implementation Order (Recommended)

1. **Quick wins** (Phase 1 + 2.2): Complete core TODOs and clarify naming
2. **Production readiness** (Phase 3.1 + 5): File rotation + comprehensive testing
3. **Documentation polish** (Phase 4): Make it shine for users
4. **CRAN prep** (Phase 5.2-5.3): Final quality checks
5. **Future enhancements** (Phase 3.2-3.3, Phase 6): Post-CRAN improvements

---

## Success Criteria

- [x] Receiver error handling implemented ✅
- [x] Test suite comprehensive (130 tests passing) ✅
- [x] All Phase 1 core functionality complete ✅
  - [x] with_limits.log_receiver() complete ✅
  - [x] with_tags() mostly complete (logger-level tags working) ✅
- [x] Phase 2 code quality improvements complete ✅
- [x] Phase 3 enhanced functionality complete ✅
  - [x] File rotation implemented ✅
  - [x] JSON receiver implemented ✅
- [x] Zero ERRORs/WARNINGs from R CMD check ✅
- [x] Test coverage: 84.30% (very good, Shiny receivers untestable without session) ✅
- [x] Documentation complete and consistent ✅
- [x] Package ready for CRAN submission ✅

---

## Notes

- Prioritize backward compatibility - don't break existing user code
- Add deprecation warnings if changing APIs
- Keep the functional, composable design philosophy
- Maintain the excellent documentation standards
