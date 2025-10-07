# logthis Improvement Plan

## Overview
This document outlines improvements to make logthis production-ready for CRAN submission. Focus on completing TODOs, enhancing functionality, and polishing documentation.

**Last Updated:** 2025-10-07

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
**Status:** 🟡 Partially complete
**Completed:**
- [x] Logger-level tags implemented and applied to events (R/logger.R:49-53)
- [x] Comprehensive test suite added (tests/testthat/test-tags.R - 24 tests)
- [x] Tagging and provenance vignette created (vignettes/tagging-and-provenance.Rmd)
- [x] README updated with tag examples

**Tasks:**
- [ ] Complete `with_tags.log_event_level()` - auto-apply tags to all events of that level
- [ ] Add tag filtering/search utilities (optional enhancement)

---

## Phase 2: Code Quality Improvements

### 2.1 Refactor Color Lookup in `to_console()`
**File:** `R/receivers.R:129-135`
**Current Issue:** Inefficient loop-based lookup
**Tasks:**
- [ ] Create package-level constant for level-to-color mapping
- [ ] Use `findInterval()` or similar for efficient lookup
- [ ] Add tests to verify color mapping correctness
- [ ] Document color scheme in function docs

### 2.2 Clarify Logger Naming Conventions
**Issue:** Confusion between `dummy_logger()` and exported `log_this()`
**Tasks:**
- [ ] Review and clarify purpose of `dummy_logger()` vs void logger
- [ ] Update documentation to explain the distinction
- [ ] Consider deprecating `dummy_logger()` if redundant
- [ ] Ensure consistency in README examples

Note:  dummy_logger() would just be void_logger(), let's use void_logger().


### 2.3 Fix Documentation Inconsistencies
**Issue:** Examples use `to_identity()` as placeholder for file logging
**Tasks:**
- [ ] Replace `to_identity()` placeholders with `to_text_file()` in examples
- [ ] Clarify when to use `to_identity()` (testing) vs `to_text_file()` (production)
- [ ] Update README sections: Logger Chaining, Scope-Based Enhancement

---

## Phase 3: Enhanced Functionality

### 3.1 Add File Rotation to `to_text_file()`
**Priority:** High for production use
**Tasks:**
- [ ] Add `max_size` parameter (bytes) to trigger rotation
- [ ] Add `max_files` parameter to limit rotation history
- [ ] Implement rotation logic (rename log.txt → log.1.txt → log.2.txt, etc.)
- [ ] Add timestamp-based rotation option (daily/hourly)
- [ ] Add tests for rotation behavior
- [ ] Document rotation configuration in README

### 3.2 Add JSON Receiver for Modern Log Aggregation
**Priority:** Medium - useful for cloud deployments
**Tasks:**
- [ ] Create `to_json_file()` receiver
- [ ] Output structured JSON with all event metadata
- [ ] Support custom field mapping
- [ ] Add optional pretty-printing for debugging
- [ ] Add tests for JSON output validation
- [ ] Add example integration with log aggregation systems

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
- [x] Test suite comprehensive (111 tests passing) ✅
- [x] All Phase 1 core functionality complete ✅
  - [x] with_limits.log_receiver() complete ✅
  - [x] with_tags() mostly complete (logger-level tags working) ✅
- [ ] Zero ERRORs/WARNINGs from R CMD check
- [ ] Test coverage ≥ 90%
- [ ] Documentation complete and consistent
- [ ] File rotation implemented
- [ ] Ready for CRAN submission

---

## Notes

- Prioritize backward compatibility - don't break existing user code
- Add deprecation warnings if changing APIs
- Keep the functional, composable design philosophy
- Maintain the excellent documentation standards
