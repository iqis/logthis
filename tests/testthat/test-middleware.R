library(testthat)

# ============================================================================
# Middleware Constructor Tests
# ============================================================================

test_that("middleware() creates middleware function", {
  mw <- middleware(function(event) {
    event$custom_field <- "added"
    event
  })

  expect_s3_class(mw, "log_middleware")
  expect_s3_class(mw, "function")
  expect_true(is.function(mw))
})

test_that("middleware() validates input", {
  expect_error(
    middleware("not a function"),
    "`transform_fn` must be a function"
  )

  expect_error(
    middleware(123),
    "`transform_fn` must be a function"
  )

  expect_error(
    middleware(NULL),
    "`transform_fn` must be a function"
  )
})

test_that("middleware() creates working transformation function", {
  mw <- middleware(function(event) {
    event$message <- paste0(event$message, " [transformed]")
    event
  })

  event <- NOTE("test message")
  result <- mw(event)

  expect_equal(result$message, "test message [transformed]")
})

# ============================================================================
# with_middleware() Tests
# ============================================================================

test_that("with_middleware() adds middleware to logger", {
  log_capture <- logger() %>%
    with_middleware(
      middleware(function(event) {
        event$mw1 <- TRUE
        event
      })
    ) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("test"))

  expect_true(result$mw1)
})

test_that("with_middleware() accepts plain functions (not wrapped)", {
  log_capture <- logger() %>%
    with_middleware(
      function(event) {  # Plain function, not middleware()
        event$plain_fn <- TRUE
        event
      }
    ) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("test"))

  expect_true(result$plain_fn)
})

test_that("with_middleware() validates function arguments", {
  expect_error(
    logger() %>% with_middleware("not a function"),
    "`with_middleware\\(\\)` requires function arguments"
  )

  expect_error(
    logger() %>% with_middleware(123),
    "`with_middleware\\(\\)` requires function arguments"
  )

  expect_error(
    logger() %>% with_middleware(NULL),
    "`with_middleware\\(\\)` requires function arguments"
  )
})

test_that("with_middleware() accepts multiple middleware", {
  log_capture <- logger() %>%
    with_middleware(
      middleware(function(event) {
        event$mw1 <- "first"
        event
      }),
      middleware(function(event) {
        event$mw2 <- "second"
        event
      }),
      middleware(function(event) {
        event$mw3 <- "third"
        event
      })
    ) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("test"))

  expect_equal(result$mw1, "first")
  expect_equal(result$mw2, "second")
  expect_equal(result$mw3, "third")
})

# ============================================================================
# Middleware Execution Order Tests
# ============================================================================

test_that("middleware executes in correct order", {
  log_capture <- logger() %>%
    with_middleware(
      middleware(function(event) {
        event$order <- c(event$order, "first")
        event
      }),
      middleware(function(event) {
        event$order <- c(event$order, "second")
        event
      }),
      middleware(function(event) {
        event$order <- c(event$order, "third")
        event
      })
    ) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("test", order = character(0)))

  expect_equal(result$order, c("first", "second", "third"))
})

test_that("middleware runs BEFORE logger-level filtering", {
  # Middleware that escalates DEBUG to WARNING
  escalate_mw <- middleware(function(event) {
    if (event$level_class == "DEBUG") {
      event$level_class <- "WARNING"
      event$level_number <- attr(WARNING, "level_number")
      event$escalated <- TRUE
    }
    event
  })

  # Logger filters for WARNING and above
  log_capture <- logger() %>%
    with_middleware(escalate_mw) %>%
    with_limits(lower = WARNING) %>%
    with_receivers(to_identity())

  # Send DEBUG event
  result <- log_capture(DEBUG("test message"))

  # Should be escalated to WARNING and pass through filter
  expect_equal(result$level_class, "WARNING")
  expect_true(result$escalated)
})

test_that("middleware can modify events before logger tags are added", {
  # Middleware adds a tag
  add_tag_mw <- middleware(function(event) {
    event$tags <- c(event$tags, "middleware_tag")
    event
  })

  # Logger also adds a tag
  log_capture <- logger() %>%
    with_middleware(add_tag_mw) %>%
    with_tags("logger_tag") %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("test") %>% with_tags("event_tag"))

  # Should have all three tags
  expect_true("event_tag" %in% result$tags)
  expect_true("middleware_tag" %in% result$tags)
  expect_true("logger_tag" %in% result$tags)
})

# ============================================================================
# Short-Circuiting Tests (Middleware Returning NULL)
# ============================================================================

test_that("middleware can drop events by returning NULL", {
  drop_mw <- middleware(function(event) {
    NULL  # Always drop
  })

  log_capture <- logger() %>%
    with_middleware(drop_mw) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("test"))

  # Logger returns NULL when event is dropped
  expect_null(result)
})

test_that("middleware can conditionally drop events", {
  # Drop DEBUG events, keep others
  drop_debug_mw <- middleware(function(event) {
    if (event$level_class == "DEBUG") {
      return(NULL)
    }
    event
  })

  log_capture <- logger() %>%
    with_middleware(drop_debug_mw) %>%
    with_receivers(to_identity())

  # DEBUG should be dropped
  result_debug <- log_capture(DEBUG("test"))
  expect_null(result_debug)

  # WARNING should pass through
  result_warning <- log_capture(WARNING("test"))
  expect_equal(result_warning$level_class, "WARNING")
})

test_that("middleware chain stops on first NULL", {
  log_capture <- logger() %>%
    with_middleware(
      middleware(function(event) {
        event$mw1 <- TRUE
        event
      }),
      middleware(function(event) {
        NULL  # Drop here
      }),
      middleware(function(event) {
        event$mw3 <- TRUE  # Should never run
        event
      })
    ) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("test"))

  expect_null(result)
})

# ============================================================================
# Middleware Chaining Tests
# ============================================================================

test_that("middleware can be chained with multiple with_middleware() calls", {
  log_capture <- logger() %>%
    with_middleware(
      middleware(function(event) {
        event$mw1 <- TRUE
        event
      })
    ) %>%
    with_middleware(
      middleware(function(event) {
        event$mw2 <- TRUE
        event
      })
    ) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("test"))

  expect_true(result$mw1)
  expect_true(result$mw2)
})

test_that("middleware accumulates across with_middleware() calls", {
  base_logger <- logger() %>%
    with_middleware(
      middleware(function(event) {
        event$base <- TRUE
        event
      })
    )

  extended_logger <- base_logger %>%
    with_middleware(
      middleware(function(event) {
        event$extended <- TRUE
        event
      })
    ) %>%
    with_receivers(to_identity())

  result <- extended_logger(NOTE("test"))

  expect_true(result$base)
  expect_true(result$extended)
})

# ============================================================================
# Real-World Middleware Examples Tests
# ============================================================================

test_that("PII redaction middleware works", {
  redact_ssn <- middleware(function(event) {
    event$message <- gsub(
      "\\b\\d{3}-\\d{2}-\\d{4}\\b",
      "***-**-****",
      event$message
    )
    event
  })

  log_capture <- logger() %>%
    with_middleware(redact_ssn) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("SSN: 123-45-6789"))

  expect_equal(result$message, "SSN: ***-**-****")
})

test_that("context enrichment middleware works", {
  add_context <- middleware(function(event) {
    event$hostname <- Sys.info()[["nodename"]]
    event$pid <- Sys.getpid()
    event
  })

  log_capture <- logger() %>%
    with_middleware(add_context) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("test"))

  expect_true(!is.null(result$hostname))
  expect_true(!is.null(result$pid))
  expect_equal(result$pid, Sys.getpid())
})

test_that("duration calculation middleware works", {
  add_duration <- middleware(function(event) {
    if (!is.null(event$start_time)) {
      event$duration_ms <- as.numeric(Sys.time() - event$start_time) * 1000
      event$start_time <- NULL
    }
    event
  })

  log_capture <- logger() %>%
    with_middleware(add_duration) %>%
    with_receivers(to_identity())

  start_time <- Sys.time()
  Sys.sleep(0.1)  # 100ms
  result <- log_capture(NOTE("test", start_time = start_time))

  expect_true(!is.null(result$duration_ms))
  expect_true(result$duration_ms >= 100)  # At least 100ms
  expect_null(result$start_time)  # Should be removed
})

test_that("sampling middleware works", {
  # Sample 50% of events
  sample_mw <- middleware(function(event) {
    if (runif(1) > 0.5) {
      return(NULL)
    }
    event$sampled <- TRUE
    event
  })

  log_capture <- logger() %>%
    with_middleware(sample_mw) %>%
    with_receivers(to_identity())

  # Send 100 events, expect ~50 to pass
  results <- replicate(100, {
    log_capture(NOTE("test"))
  }, simplify = FALSE)

  non_null_count <- sum(!sapply(results, is.null))

  # Should be roughly 50 (allow wide margin for randomness)
  expect_true(non_null_count >= 30 && non_null_count <= 70)
})

test_that("level-based sampling works", {
  sample_by_level <- middleware(function(event) {
    # Drop all DEBUG
    if (event$level_class == "DEBUG") {
      return(NULL)
    }

    # Keep 50% of NOTE
    if (event$level_class == "NOTE" && runif(1) > 0.5) {
      return(NULL)
    }

    # Keep all WARNING and above
    event
  })

  log_capture <- logger() %>%
    with_middleware(sample_by_level) %>%
    with_receivers(to_identity())

  # DEBUG should always be dropped
  result_debug <- log_capture(DEBUG("test"))
  expect_null(result_debug)

  # WARNING should always pass
  result_warning <- log_capture(WARNING("test"))
  expect_equal(result_warning$level_class, "WARNING")

  # NOTE should be sampled (~50%)
  note_results <- replicate(100, {
    log_capture(NOTE("test"))
  }, simplify = FALSE)

  note_count <- sum(!sapply(note_results, is.null))
  expect_true(note_count >= 30 && note_count <= 70)
})

# ============================================================================
# Middleware with Logger Configuration Tests
# ============================================================================

test_that("middleware works with logger limits", {
  log_capture <- logger() %>%
    with_middleware(
      middleware(function(event) {
        event$mw_applied <- TRUE
        event
      })
    ) %>%
    with_limits(lower = WARNING) %>%
    with_receivers(to_identity())

  # DEBUG should be filtered by logger (middleware still ran)
  result_debug <- log_capture(DEBUG("test"))
  expect_equal(result_debug$level_class, "DEBUG")
  expect_true(result_debug$mw_applied)  # Middleware ran before filter

  # WARNING should pass through
  result_warning <- log_capture(WARNING("test"))
  expect_equal(result_warning$level_class, "WARNING")
  expect_true(result_warning$mw_applied)
})

test_that("middleware works with logger tags", {
  log_capture <- logger() %>%
    with_middleware(
      middleware(function(event) {
        event$middleware_ran <- TRUE
        event
      })
    ) %>%
    with_tags("logger_tag") %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("test"))

  expect_true(result$middleware_ran)
  expect_true("logger_tag" %in% result$tags)
})

test_that("middleware works with multiple receivers", {
  events1 <- list()
  events2 <- list()

  recv1 <- receiver(function(event) {
    events1 <<- c(events1, list(event))
    invisible(NULL)
  })

  recv2 <- receiver(function(event) {
    events2 <<- c(events2, list(event))
    invisible(NULL)
  })

  log_multi <- logger() %>%
    with_middleware(
      middleware(function(event) {
        event$enriched <- TRUE
        event
      })
    ) %>%
    with_receivers(recv1, recv2)

  log_multi(NOTE("test"))

  # Both receivers should get enriched event
  expect_length(events1, 1)
  expect_length(events2, 1)
  expect_true(events1[[1]]$enriched)
  expect_true(events2[[1]]$enriched)
})

# ============================================================================
# Edge Cases and Error Handling Tests
# ============================================================================

test_that("middleware handles NULL message", {
  add_context <- middleware(function(event) {
    event$context <- "added"
    event
  })

  log_capture <- logger() %>%
    with_middleware(add_context) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE(NULL))

  expect_null(result$message)
  expect_equal(result$context, "added")
})

test_that("middleware handles empty message", {
  add_context <- middleware(function(event) {
    event$context <- "added"
    event
  })

  log_capture <- logger() %>%
    with_middleware(add_context) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE(""))

  expect_equal(result$message, "")
  expect_equal(result$context, "added")
})

test_that("middleware handles events with many custom fields", {
  add_field <- middleware(function(event) {
    event$middleware_field <- "added"
    event
  })

  log_capture <- logger() %>%
    with_middleware(add_field) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE(
    "test",
    field1 = 1,
    field2 = "two",
    field3 = list(a = 1, b = 2),
    field4 = TRUE,
    field5 = NULL
  ))

  expect_equal(result$field1, 1)
  expect_equal(result$field2, "two")
  expect_equal(result$field3, list(a = 1, b = 2))
  expect_equal(result$field4, TRUE)
  expect_null(result$field5)
  expect_equal(result$middleware_field, "added")
})

test_that("middleware with no middleware functions works", {
  log_capture <- logger() %>%
    with_middleware() %>%  # No middleware
    with_receivers(to_identity())

  result <- log_capture(NOTE("test"))

  expect_equal(result$message, "test")
})

test_that("middleware handles Unicode in messages", {
  add_context <- middleware(function(event) {
    event$context <- "added"
    event
  })

  log_capture <- logger() %>%
    with_middleware(add_context) %>%
    with_receivers(to_identity())

  result <- log_capture(NOTE("Hello 🌍 测试 тест"))

  expect_equal(result$message, "Hello 🌍 测试 тест")
  expect_equal(result$context, "added")
})

# ============================================================================
# Scope-Based Masking with Middleware Tests
# ============================================================================

test_that("middleware respects scope-based masking", {
  # Parent logger with middleware
  parent_mw <- middleware(function(event) {
    event$parent_mw <- TRUE
    event
  })

  log_parent <- logger() %>%
    with_middleware(parent_mw) %>%
    with_receivers(to_identity())

  # Test parent
  result_parent <- log_parent(NOTE("parent"))
  expect_true(result_parent$parent_mw)

  # Child logger adds more middleware (doesn't affect parent)
  child_mw <- middleware(function(event) {
    event$child_mw <- TRUE
    event
  })

  log_child <- log_parent %>%
    with_middleware(child_mw)

  # Child has both
  result_child <- log_child(NOTE("child"))
  expect_true(result_child$parent_mw)
  expect_true(result_child$child_mw)

  # Parent still only has parent middleware
  result_parent2 <- log_parent(NOTE("parent again"))
  expect_true(result_parent2$parent_mw)
  expect_null(result_parent2$child_mw)
})

# ============================================================================
# Middleware with Logger Chaining Tests
# ============================================================================

test_that("middleware works with logger chaining", {
  events1 <- list()
  events2 <- list()

  recv1 <- receiver(function(event) {
    events1 <<- c(events1, list(event))
    invisible(NULL)
  })

  recv2 <- receiver(function(event) {
    events2 <<- c(events2, list(event))
    invisible(NULL)
  })

  log1 <- logger() %>%
    with_middleware(
      middleware(function(event) {
        event$log1_mw <- TRUE
        event
      })
    ) %>%
    with_receivers(recv1)

  log2 <- logger() %>%
    with_middleware(
      middleware(function(event) {
        event$log2_mw <- TRUE
        event
      })
    ) %>%
    with_receivers(recv2)

  # Chain loggers
  NOTE("test") %>% log1() %>% log2()

  # First logger's receiver gets first middleware
  expect_length(events1, 1)
  expect_true(events1[[1]]$log1_mw)
  expect_null(events1[[1]]$log2_mw)  # Second middleware not applied yet

  # Second logger's receiver gets BOTH middleware (chaining accumulates)
  expect_length(events2, 1)
  expect_true(events2[[1]]$log1_mw)  # First middleware already applied
  expect_true(events2[[1]]$log2_mw)  # Second middleware also applied
})

# ============================================================================
# Performance-Related Middleware Tests
# ============================================================================

test_that("rate limiting middleware works", {
  # Simple rate limiter: allow 5 events, then drop
  event_count <- 0

  rate_limit_mw <- middleware(function(event) {
    event_count <<- event_count + 1
    if (event_count > 5) {
      return(NULL)
    }
    event
  })

  log_capture <- logger() %>%
    with_middleware(rate_limit_mw) %>%
    with_receivers(to_identity())

  # First 5 should pass
  for (i in 1:5) {
    result <- log_capture(NOTE(paste("event", i)))
    expect_equal(result$message, paste("event", i))
  }

  # 6th and beyond should be dropped
  result6 <- log_capture(NOTE("event 6"))
  expect_null(result6)

  result7 <- log_capture(NOTE("event 7"))
  expect_null(result7)
})

test_that("escalation middleware works", {
  # Escalate NOTE to WARNING if message contains "urgent"
  escalate_mw <- middleware(function(event) {
    if (event$level_class == "NOTE" && grepl("urgent", event$message, ignore.case = TRUE)) {
      event$level_class <- "WARNING"
      event$level_number <- attr(WARNING, "level_number")
      event$escalated <- TRUE
    }
    event
  })

  log_capture <- logger() %>%
    with_middleware(escalate_mw) %>%
    with_receivers(to_identity())

  # Normal NOTE
  result1 <- log_capture(NOTE("normal message"))
  expect_equal(result1$level_class, "NOTE")
  expect_null(result1$escalated)

  # Urgent NOTE should be escalated
  result2 <- log_capture(NOTE("URGENT: needs attention"))
  expect_equal(result2$level_class, "WARNING")
  expect_true(result2$escalated)
})

# ============================================================================
# Receiver-Level Middleware Tests
# ============================================================================

test_that("with_middleware works on receivers", {
  received_event <- NULL

  add_field_mw <- middleware(function(event) {
    event$receiver_mw <- TRUE
    event
  })

  recv <- receiver(function(event) {
    received_event <<- event  # Capture what receiver sees
    invisible(NULL)
  }) %>% with_middleware(add_field_mw)

  log_capture <- logger() %>% with_receivers(recv)

  log_capture(NOTE("test"))

  # Receiver should have seen the modified event
  expect_true(received_event$receiver_mw)
})

test_that("receiver middleware applies only to specific receiver", {
  events_recv1 <- list()
  events_recv2 <- list()

  # Middleware adds field
  add_marker <- middleware(function(event) {
    event$marked <- TRUE
    event
  })

  recv1 <- receiver(function(event) {
    events_recv1 <<- c(events_recv1, list(event))
    invisible(NULL)
  }) %>% with_middleware(add_marker)

  recv2 <- receiver(function(event) {
    events_recv2 <<- c(events_recv2, list(event))
    invisible(NULL)
  })

  log_multi <- logger() %>% with_receivers(recv1, recv2)

  log_multi(NOTE("test"))

  # Receiver 1 should have marked field
  expect_length(events_recv1, 1)
  expect_true(events_recv1[[1]]$marked)

  # Receiver 2 should NOT have marked field
  expect_length(events_recv2, 1)
  expect_null(events_recv2[[1]]$marked)
})

test_that("receiver middleware can drop events (short-circuit)", {
  events_captured <- list()

  # Middleware drops DEBUG events
  drop_debug <- middleware(function(event) {
    if (event$level_class == "DEBUG") {
      return(NULL)
    }
    event
  })

  recv <- receiver(function(event) {
    events_captured <<- c(events_captured, list(event))
    invisible(NULL)
  }) %>% with_middleware(drop_debug)

  log_capture <- logger() %>% with_receivers(recv)

  # Send DEBUG (should be dropped by receiver middleware)
  log_capture(DEBUG("debug message"))
  expect_length(events_captured, 0)

  # Send WARNING (should pass through)
  log_capture(WARNING("warning message"))
  expect_length(events_captured, 1)
  expect_equal(events_captured[[1]]$level_class, "WARNING")
})

test_that("receiver middleware chains accumulate", {
  received_event <- NULL

  mw1 <- middleware(function(event) {
    event$mw1 <- TRUE
    event
  })

  mw2 <- middleware(function(event) {
    event$mw2 <- TRUE
    event
  })

  recv <- receiver(function(event) {
    received_event <<- event
    invisible(NULL)
  }) %>%
    with_middleware(mw1) %>%
    with_middleware(mw2)

  log_capture <- logger() %>% with_receivers(recv)

  log_capture(NOTE("test"))

  expect_true(received_event$mw1)
  expect_true(received_event$mw2)
})

test_that("receiver middleware executes in order", {
  received_event <- NULL

  recv <- receiver(function(event) {
    received_event <<- event
    invisible(NULL)
  }) %>%
    with_middleware(
      middleware(function(event) {
        event$order <- c(event$order, "first")
        event
      }),
      middleware(function(event) {
        event$order <- c(event$order, "second")
        event
      })
    )

  log_capture <- logger() %>% with_receivers(recv)

  log_capture(NOTE("test", order = character(0)))

  expect_equal(received_event$order, c("first", "second"))
})

test_that("logger middleware runs before receiver middleware", {
  received_event <- NULL

  logger_mw <- middleware(function(event) {
    event$logger_mw <- TRUE
    event
  })

  receiver_mw <- middleware(function(event) {
    event$receiver_mw <- TRUE
    # Verify logger middleware already ran
    event$logger_ran_first <- !is.null(event$logger_mw)
    event
  })

  recv <- receiver(function(event) {
    received_event <<- event
    invisible(NULL)
  }) %>% with_middleware(receiver_mw)

  log_capture <- logger() %>%
    with_middleware(logger_mw) %>%
    with_receivers(recv)

  result <- log_capture(NOTE("test"))

  # Logger's return value has logger middleware applied
  expect_true(result$logger_mw)

  # Receiver saw both logger and receiver middleware
  expect_true(received_event$logger_mw)
  expect_true(received_event$receiver_mw)
  expect_true(received_event$logger_ran_first)
})

test_that("different receivers can have different middleware", {
  events_recv1 <- list()
  events_recv2 <- list()

  redact_full <- middleware(function(event) {
    event$message <- gsub("SECRET", "***", event$message)
    event$redaction <- "full"
    event
  })

  redact_partial <- middleware(function(event) {
    event$message <- gsub("SECRET", "S***T", event$message)
    event$redaction <- "partial"
    event
  })

  recv1 <- receiver(function(event) {
    events_recv1 <<- c(events_recv1, list(event))
    invisible(NULL)
  }) %>% with_middleware(redact_full)

  recv2 <- receiver(function(event) {
    events_recv2 <<- c(events_recv2, list(event))
    invisible(NULL)
  }) %>% with_middleware(redact_partial)

  log_multi <- logger() %>% with_receivers(recv1, recv2)

  log_multi(NOTE("Password: SECRET123"))

  # Receiver 1: full redaction
  expect_equal(events_recv1[[1]]$message, "Password: ***123")
  expect_equal(events_recv1[[1]]$redaction, "full")

  # Receiver 2: partial redaction
  expect_equal(events_recv2[[1]]$message, "Password: S***T123")
  expect_equal(events_recv2[[1]]$redaction, "partial")
})

test_that("receiver middleware validates function arguments", {
  expect_error(
    to_console() %>% with_middleware("not a function"),
    "`with_middleware\\(\\)` requires function arguments"
  )

  expect_error(
    to_console() %>% with_middleware(123),
    "`with_middleware\\(\\)` requires function arguments"
  )
})

test_that("receiver middleware with cost optimization", {
  events_local <- list()
  events_cloud <- list()

  # Sample 50% before cloud (cost optimization)
  sample_half <- middleware(function(event) {
    if (runif(1) > 0.5) {
      return(NULL)
    }
    event$sampled <- TRUE
    event
  })

  recv_local <- receiver(function(event) {
    events_local <<- c(events_local, list(event))
    invisible(NULL)
  })

  recv_cloud <- receiver(function(event) {
    events_cloud <<- c(events_cloud, list(event))
    invisible(NULL)
  }) %>% with_middleware(sample_half)

  log_multi <- logger() %>% with_receivers(recv_local, recv_cloud)

  # Send 100 events
  for (i in 1:100) {
    log_multi(NOTE(paste("Event", i)))
  }

  # Local should have all 100
  expect_equal(length(events_local), 100)

  # Cloud should have ~50 (allow margin for randomness)
  expect_true(length(events_cloud) >= 30 && length(events_cloud) <= 70)

  # All cloud events should be marked as sampled
  expect_true(all(sapply(events_cloud, function(e) isTRUE(e$sampled))))
})

test_that("receiver middleware with differential PII redaction", {
  events_console <- list()
  events_secure <- list()

  # Full redaction for console
  redact_ssn <- middleware(function(event) {
    event$message <- gsub("\\d{3}-\\d{2}-\\d{4}", "***-**-****", event$message)
    event
  })

  recv_console <- receiver(function(event) {
    events_console <<- c(events_console, list(event))
    invisible(NULL)
  }) %>% with_middleware(redact_ssn)

  recv_secure <- receiver(function(event) {
    events_secure <<- c(events_secure, list(event))
    invisible(NULL)
  })
  # No redaction for secure vault

  log_multi <- logger() %>% with_receivers(recv_console, recv_secure)

  log_multi(NOTE("SSN: 123-45-6789"))

  # Console: redacted
  expect_equal(events_console[[1]]$message, "SSN: ***-**-****")

  # Secure: original
  expect_equal(events_secure[[1]]$message, "SSN: 123-45-6789")
})
