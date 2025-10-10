library(testthat)

# ============================================================================
# Edge Case Tests: Empty Messages, Long Messages, Unicode, Concurrent Logging
# ============================================================================

test_that("logger handles empty messages", {
  log_capture <- logger() %>% with_receivers(to_identity())

  # Empty string
  result <- log_capture(NOTE(""))
  expect_equal(result$message, "")
  expect_equal(result$level_class, "NOTE")

  # Whitespace only
  result2 <- log_capture(WARNING("   "))
  expect_equal(result2$message, "   ")
  expect_equal(result2$level_class, "WARNING")

  # NULL message is stored as NULL (not coerced)
  result3 <- log_capture(ERROR(NULL))
  expect_null(result3$message)
})

test_that("logger handles very long messages", {
  log_capture <- logger() %>% with_receivers(to_identity())

  # 10K character message
  long_msg <- paste(rep("A", 10000), collapse = "")
  result <- log_capture(NOTE(long_msg))
  expect_equal(nchar(result$message), 10000)
  expect_equal(result$level_class, "NOTE")

  # 100K character message
  very_long_msg <- paste(rep("B", 100000), collapse = "")
  result2 <- log_capture(WARNING(very_long_msg))
  expect_equal(nchar(result2$message), 100000)
  expect_equal(result2$level_class, "WARNING")
})

test_that("logger handles Unicode and special characters", {
  log_capture <- logger() %>% with_receivers(to_identity())

  # Emoji
  result1 <- log_capture(NOTE("Hello 🌍 World 🎉"))
  expect_equal(result1$message, "Hello 🌍 World 🎉")

  # Chinese characters
  result2 <- log_capture(WARNING("测试消息"))
  expect_equal(result2$message, "测试消息")

  # Arabic
  result3 <- log_capture(ERROR("اختبار"))
  expect_equal(result3$message, "اختبار")

  # Mixed scripts
  result4 <- log_capture(NOTE("Test тест 测试 🔥"))
  expect_equal(result4$message, "Test тест 测试 🔥")

  # Special characters
  result5 <- log_capture(NOTE("Symbols: !@#$%^&*()[]{}|\\<>?/~`"))
  expect_equal(result5$message, "Symbols: !@#$%^&*()[]{}|\\<>?/~`")

  # Newlines and tabs
  result6 <- log_capture(NOTE("Line1\nLine2\tTabbed"))
  expect_equal(result6$message, "Line1\nLine2\tTabbed")
})

test_that("logger handles concurrent logging (sequential test)", {
  # Note: True concurrent testing requires parallel package,
  # but we can test that the logger doesn't break with rapid sequential calls

  log_capture <- logger() %>% with_receivers(to_identity())

  # Rapid sequential calls
  results <- lapply(1:100, function(i) {
    log_capture(NOTE(paste("Message", i)))
  })

  # All messages should be captured
  expect_length(results, 100)

  # All should have correct structure
  for (i in 1:100) {
    expect_equal(results[[i]]$level_class, "NOTE")
    expect_equal(results[[i]]$message, paste("Message", i))
  }
})

test_that("logger handles custom fields with edge case values", {
  log_capture <- logger() %>% with_receivers(to_identity())

  # NA values
  result1 <- log_capture(NOTE("Test", na_field = NA))
  expect_true(is.na(result1$na_field))

  # NULL values
  result2 <- log_capture(NOTE("Test", null_field = NULL))
  expect_null(result2$null_field)

  # Very large numeric values
  result3 <- log_capture(NOTE("Test", big_num = .Machine$double.xmax))
  expect_equal(result3$big_num, .Machine$double.xmax)

  # Very small numeric values
  result4 <- log_capture(NOTE("Test", small_num = .Machine$double.xmin))
  expect_equal(result4$small_num, .Machine$double.xmin)

  # Lists as custom fields
  result5 <- log_capture(NOTE("Test", list_field = list(a = 1, b = 2)))
  expect_equal(result5$list_field, list(a = 1, b = 2))
})

test_that("tags handle edge cases", {
  log_capture <- logger() %>% with_receivers(to_identity())

  # Empty tags
  result1 <- log_capture(NOTE("Test") %>% with_tags())
  expect_null(result1$tags)

  # Unicode in tags
  result2 <- log_capture(NOTE("Test") %>% with_tags("测试", "🔥"))
  expect_equal(result2$tags, c("测试", "🔥"))

  # Very long tag names
  long_tag <- paste(rep("tag", 100), collapse = "_")
  result3 <- log_capture(NOTE("Test") %>% with_tags(long_tag))
  expect_equal(result3$tags, long_tag)

  # Special characters in tags
  result4 <- log_capture(NOTE("Test") %>% with_tags("tag-with-dash", "tag_with_underscore", "tag.with.dot"))
  expect_equal(result4$tags, c("tag-with-dash", "tag_with_underscore", "tag.with.dot"))
})

# ============================================================================
# Integration Tests: Multi-Receiver Scenarios
# ============================================================================

test_that("multiple receivers process events independently", {
  # Capture events with different receivers
  events1 <- list()
  events2 <- list()
  events3 <- list()

  recv1 <- receiver(function(event) {
    events1 <<- c(events1, list(event))
    invisible(NULL)
  })

  recv2 <- receiver(function(event) {
    events2 <<- c(events2, list(event))
    invisible(NULL)
  })

  recv3 <- receiver(function(event) {
    events3 <<- c(events3, list(event))
    invisible(NULL)
  })

  log_multi <- logger() %>% with_receivers(recv1, recv2, recv3)

  log_multi(NOTE("Test message"))

  # All receivers should have captured the event
  expect_length(events1, 1)
  expect_length(events2, 1)
  expect_length(events3, 1)

  # All should have same content
  expect_equal(events1[[1]]$message, "Test message")
  expect_equal(events2[[1]]$message, "Test message")
  expect_equal(events3[[1]]$message, "Test message")
})

test_that("receivers with different level filters work correctly", {
  debug_events <- list()
  note_events <- list()
  error_events <- list()

  recv_debug <- receiver(function(event) {
    if (event$level_number >= attr(DEBUG, "level_number") &&
        event$level_number <= attr(DEBUG, "level_number")) {
      debug_events <<- c(debug_events, list(event))
    }
    invisible(NULL)
  })

  recv_note <- receiver(function(event) {
    if (event$level_number >= attr(NOTE, "level_number") &&
        event$level_number <= attr(WARNING, "level_number")) {
      note_events <<- c(note_events, list(event))
    }
    invisible(NULL)
  })

  recv_error <- receiver(function(event) {
    if (event$level_number >= attr(ERROR, "level_number")) {
      error_events <<- c(error_events, list(event))
    }
    invisible(NULL)
  })

  log_multi <- logger() %>% with_receivers(recv_debug, recv_note, recv_error)

  # Send events at different levels
  log_multi(DEBUG("Debug message"))
  log_multi(NOTE("Note message"))
  log_multi(WARNING("Warning message"))
  log_multi(ERROR("Error message"))

  # Verify filtering
  expect_length(debug_events, 1)  # Only DEBUG
  expect_length(note_events, 2)   # NOTE and WARNING
  expect_length(error_events, 1)  # Only ERROR
})

test_that("logger chaining works with multiple receivers", {
  events_console <- list()
  events_file <- list()

  recv_console <- receiver(function(event) {
    events_console <<- c(events_console, list(event))
    invisible(NULL)
  })

  recv_file <- receiver(function(event) {
    events_file <<- c(events_file, list(event))
    invisible(NULL)
  })

  log_console <- logger() %>% with_receivers(recv_console)
  log_file <- logger() %>% with_receivers(recv_file)

  # Chain loggers
  WARNING("Chained message") %>% log_console() %>% log_file()

  # Both should have received the event
  expect_length(events_console, 1)
  expect_length(events_file, 1)

  expect_equal(events_console[[1]]$message, "Chained message")
  expect_equal(events_file[[1]]$message, "Chained message")
})

test_that("receiver error handling doesn't stop other receivers", {
  successful_events <- list()

  # Receiver that always fails
  failing_recv <- receiver(function(event) {
    stop("Intentional failure")
  })

  # Receiver that succeeds
  success_recv <- receiver(function(event) {
    successful_events <<- c(successful_events, list(event))
    invisible(NULL)
  })

  log_multi <- logger() %>% with_receivers(failing_recv, success_recv)

  # Should not throw error (logger handles receiver failures gracefully)
  # Note: Logger may output error messages to console, so we don't use expect_silent
  expect_no_error(log_multi(NOTE("Test message")))

  # Successful receiver should still have processed event
  expect_length(successful_events, 1)
  expect_equal(successful_events[[1]]$message, "Test message")
})

test_that("scope-based masking works correctly", {
  parent_events <- list()
  child_events <- list()

  parent_recv <- receiver(function(event) {
    parent_events <<- c(parent_events, list(event))
    invisible(NULL)
  })

  child_recv <- receiver(function(event) {
    child_events <<- c(child_events, list(event))
    invisible(NULL)
  })

  # Parent logger
  log_this <- logger() %>% with_receivers(parent_recv)

  # Parent scope
  log_this(NOTE("Parent message"))

  # Child scope
  child_function <- function() {
    log_this <- log_this %>% with_receivers(child_recv)
    log_this(WARNING("Child message"))
  }
  child_function()

  # Back in parent scope
  log_this(ERROR("Another parent message"))

  # Verify parent received all messages
  expect_length(parent_events, 3)

  # Verify child only received its message
  expect_length(child_events, 1)
  expect_equal(child_events[[1]]$message, "Child message")
})

# ============================================================================
# Error Handling and Validation Tests
# ============================================================================

test_that("logger validates limits correctly", {
  # Invalid lower limit (too low)
  expect_error(
    logger() %>% with_limits(lower = -1),
    "Lower limit must be in"
  )

  # Invalid upper limit (too high)
  expect_error(
    logger() %>% with_limits(upper = 101),
    "Upper limit must be in"
  )

  # Invalid: lower > upper
  expect_error(
    logger() %>% with_limits(lower = ERROR, upper = NOTE),
    "Lower limit .* must be less than or equal to upper limit"
  )
})

test_that("receiver validates event structure", {
  recv <- to_console()

  # Not a log_event
  expect_error(recv("not an event"))
  expect_error(recv(NULL))
  expect_error(recv(123))
  expect_error(recv(list(message = "test")))
})

test_that("formatter and handler composition validates inputs", {
  # on_local requires a formatter
  expect_error(
    on_local("not a formatter", path = "test.log"),
    "`formatter` must be a log_formatter"
  )

  # path must be non-NULL
  expect_error(
    to_text() %>% on_local(path = NULL),
    "`path` must be a non-NULL character string"
  )

  # path must be a single string
  expect_error(
    to_text() %>% on_local(path = c("path1", "path2")),
    "`path` must be a single character string"
  )
})

test_that("custom event levels validate level numbers", {
  # Valid custom level
  CUSTOM <- log_event_level("CUSTOM", 55)
  expect_equal(as.numeric(attr(CUSTOM, "level_number")), 55)

  # Invalid level number (too low)
  expect_error(
    log_event_level("TOO_LOW", -5),
    "Level number must be within"
  )

  # Invalid level number (too high)
  expect_error(
    log_event_level("TOO_HIGH", 150),
    "Level number must be within"
  )
})

test_that("tags validation works correctly", {
  # Non-character tags should error
  log_capture <- logger() %>% with_receivers(to_identity())

  # Numeric tags should be rejected
  expect_error(
    log_capture(NOTE("Test") %>% with_tags(123, 456)),
    "Tags must be character strings"
  )

  # Character tags should work
  result <- log_capture(NOTE("Test") %>% with_tags("tag1", "tag2"))
  expect_true(all(is.character(result$tags)))
  expect_equal(result$tags, c("tag1", "tag2"))
})

test_that("receiver count and labeling is correct", {
  log_multi <- logger() %>% with_receivers(
    to_console(),
    to_identity(),
    to_void()
  )

  config <- attr(log_multi, "config")

  # Should have 3 receivers
  expect_length(config$receivers, 3)

  # Should have matching labels
  expect_length(config$receiver_labels, 3)

  # Labels should be character strings
  expect_true(all(sapply(config$receiver_labels, is.character)))
})

test_that("logger validates custom field types correctly", {
  log_capture <- logger() %>% with_receivers(to_identity())

  # Function as custom field should be rejected
  expect_error(
    log_capture(NOTE("Test", func = function(x) x + 1)),
    "Custom field 'func' cannot be a function"
  )

  # Environment as custom field should be rejected
  expect_error(
    log_capture(NOTE("Test", env = new.env())),
    "Custom field 'env' cannot be an environment"
  )

  # Large object should work (memory-intensive but valid)
  large_vec <- rep(1, 10000)
  result <- log_capture(NOTE("Test", big_data = large_vec))
  expect_length(result$big_data, 10000)
})

test_that("level filtering edge cases work correctly", {
  log_capture <- logger() %>% with_receivers(to_identity())

  # Exact boundary - lower limit
  log_exact_lower <- log_capture %>% with_limits(lower = NOTE, upper = ERROR)
  result1 <- log_exact_lower(NOTE("At lower boundary"))
  expect_equal(result1$message, "At lower boundary")  # Should pass (inclusive)

  # Exact boundary - upper limit
  result2 <- log_exact_lower(ERROR("At upper boundary"))
  expect_equal(result2$message, "At upper boundary")  # Should pass (inclusive)

  # Just below lower
  result3 <- log_exact_lower(DEBUG("Below lower"))
  expect_equal(result3$level_class, "DEBUG")  # Returns event, filtered by logger

  # Just above upper
  result4 <- log_exact_lower(CRITICAL("Above upper"))
  expect_equal(result4$level_class, "CRITICAL")  # Returns event, filtered by logger
})
