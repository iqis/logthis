library(testthat)

test_that("with_tags.log_event adds tags to individual events", {
  event <- NOTE("Test message")
  tagged_event <- event %>% with_tags("tag1", "tag2")

  expect_equal(tagged_event$tags, c("tag1", "tag2"))
  expect_equal(tagged_event$message, "Test message")
})

test_that("with_tags.log_event appends tags by default", {
  event <- NOTE("Test") %>% with_tags("tag1")
  event <- event %>% with_tags("tag2")

  expect_equal(event$tags, c("tag1", "tag2"))
})

test_that("with_tags.log_event can replace tags", {
  event <- NOTE("Test") %>% with_tags("tag1")
  event <- event %>% with_tags("tag2", append = FALSE)

  expect_equal(event$tags, "tag2")
})

test_that("with_tags.log_event_level creates auto-tagged events (custom levels only)", {
  # Create a custom level
  AUDIT <- log_event_level("AUDIT", 70)

  # Tag the custom level
  TAGGED_AUDIT <- AUDIT %>% with_tags("security", "compliance")

  # Events from this level should automatically have tags
  event <- TAGGED_AUDIT("User accessed sensitive data")

  expect_equal(event$tags, c("security", "compliance"))
  expect_equal(event$message, "User accessed sensitive data")
  expect_equal(event$level_class, "AUDIT")
})

test_that("with_tags.log_event_level appends tags (custom levels)", {
  CUSTOM <- log_event_level("CUSTOM", 50)
  TAGGED1 <- CUSTOM %>% with_tags("tag1")
  TAGGED2 <- TAGGED1 %>% with_tags("tag2")

  event <- TAGGED2("Test")
  expect_equal(event$tags, c("tag1", "tag2"))
})

test_that("with_tags.log_event_level can replace tags (custom levels)", {
  CUSTOM <- log_event_level("CUSTOM", 50)
  TAGGED1 <- CUSTOM %>% with_tags("tag1")
  TAGGED2 <- TAGGED1 %>% with_tags("tag2", append = FALSE)

  event <- TAGGED2("Test")
  expect_equal(event$tags, "tag2")
})

test_that("with_tags.log_event_level rejects built-in levels", {
  # All built-in levels should be rejected
  expect_error(
    LOWEST %>% with_tags("tag"),
    "Cannot add tags to built-in level 'LOWEST'"
  )

  expect_error(
    TRACE %>% with_tags("tag"),
    "Cannot add tags to built-in level 'TRACE'"
  )

  expect_error(
    DEBUG %>% with_tags("tag"),
    "Cannot add tags to built-in level 'DEBUG'"
  )

  expect_error(
    NOTE %>% with_tags("tag"),
    "Cannot add tags to built-in level 'NOTE'"
  )

  expect_error(
    MESSAGE %>% with_tags("tag"),
    "Cannot add tags to built-in level 'MESSAGE'"
  )

  expect_error(
    WARNING %>% with_tags("tag"),
    "Cannot add tags to built-in level 'WARNING'"
  )

  expect_error(
    ERROR %>% with_tags("tag"),
    "Cannot add tags to built-in level 'ERROR'"
  )

  expect_error(
    CRITICAL %>% with_tags("tag"),
    "Cannot add tags to built-in level 'CRITICAL'"
  )

  expect_error(
    HIGHEST %>% with_tags("tag"),
    "Cannot add tags to built-in level 'HIGHEST'"
  )
})

test_that("with_tags.logger applies tags to all events", {
  # Create a logger with tags
  log_capture <- logger() %>%
    with_receivers(to_identity()) %>%
    with_tags("production", "api")

  # Create events
  event1 <- NOTE("First event")
  event2 <- WARNING("Second event")

  # Pass through logger
  result1 <- log_capture(event1)
  result2 <- log_capture(event2)

  # Both should have logger tags
  expect_true("production" %in% result1$tags)
  expect_true("api" %in% result1$tags)
  expect_true("production" %in% result2$tags)
  expect_true("api" %in% result2$tags)
})

test_that("with_tags.logger appends tags", {
  log_capture <- logger() %>%
    with_receivers(to_identity()) %>%
    with_tags("tag1") %>%
    with_tags("tag2")

  event <- NOTE("Test")
  result <- log_capture(event)

  expect_true("tag1" %in% result$tags)
  expect_true("tag2" %in% result$tags)
})

test_that("with_tags.logger can replace tags", {
  log_capture <- logger() %>%
    with_receivers(to_identity()) %>%
    with_tags("tag1") %>%
    with_tags("tag2", append = FALSE)

  event <- NOTE("Test")
  result <- log_capture(event)

  expect_equal(result$tags, c("tag2"))  # Event tags + logger tag
})

test_that("tag hierarchy works: event + level + logger", {
  # Create custom level with tags
  BUSINESS <- log_event_level("BUSINESS", 50)
  TAGGED_LEVEL <- BUSINESS %>% with_tags("level_tag")

  # Create logger with tags
  log_capture <- logger() %>%
    with_receivers(to_identity()) %>%
    with_tags("logger_tag")

  # Create event from tagged level with its own tags
  event <- TAGGED_LEVEL("Test") %>% with_tags("event_tag")

  # Pass through logger
  result <- log_capture(event)

  # Should have all tags
  expect_true("event_tag" %in% result$tags)
  expect_true("level_tag" %in% result$tags)
  expect_true("logger_tag" %in% result$tags)
  expect_equal(length(result$tags), 3)
})

test_that("with_tags validates tag types", {
  # Test with custom level (built-in levels can't be tagged)
  CUSTOM <- log_event_level("CUSTOM", 50)
  expect_error(
    CUSTOM %>% with_tags("valid", 123),
    "Tags must be character strings"
  )

  expect_error(
    logger() %>% with_tags("valid", NULL),
    "Argument `...` \\(tags\\) must be of type 'character'"
  )
})

test_that("logger with no tags doesn't modify event tags", {
  log_capture <- logger() %>% with_receivers(to_identity())

  event <- NOTE("Test") %>% with_tags("original")
  result <- log_capture(event)

  expect_equal(result$tags, "original")
})

test_that("empty event tags work correctly with logger tags", {
  log_capture <- logger() %>%
    with_receivers(to_identity()) %>%
    with_tags("logger_tag")

  # Event with no tags
  event <- NOTE("Test")
  result <- log_capture(event)

  # Should have logger tag plus empty event tags
  expect_true("logger_tag" %in% result$tags)
})
