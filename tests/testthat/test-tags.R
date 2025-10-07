library(testthat)
library(purrr)

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

test_that("with_tags.log_event_level creates auto-tagged events", {
  # Create a tagged level
  TAGGED_ERROR <- ERROR %>% with_tags("critical", "alert")

  # Events from this level should automatically have tags
  event <- TAGGED_ERROR("System failure")

  expect_equal(event$tags, c("critical", "alert"))
  expect_equal(event$message, "System failure")
  expect_equal(event$level_class, "ERROR")
})

test_that("with_tags.log_event_level appends tags", {
  TAGGED1 <- ERROR %>% with_tags("tag1")
  TAGGED2 <- TAGGED1 %>% with_tags("tag2")

  event <- TAGGED2("Test")
  expect_equal(event$tags, c("tag1", "tag2"))
})

test_that("with_tags.log_event_level can replace tags", {
  TAGGED1 <- ERROR %>% with_tags("tag1")
  TAGGED2 <- TAGGED1 %>% with_tags("tag2", append = FALSE)

  event <- TAGGED2("Test")
  expect_equal(event$tags, "tag2")
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
  # Create tagged level
  TAGGED_LEVEL <- NOTE %>% with_tags("level_tag")

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
  expect_error(
    ERROR %>% with_tags("valid", 123),
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
