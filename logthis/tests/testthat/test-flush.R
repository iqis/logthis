library(testthat)

# =============================================================================
# Named Receivers Tests
# =============================================================================

test_that("with_receivers() supports named receivers", {
  log_this <- logger() %>%
    with_receivers(
      console = to_console(),
      audit = to_identity()
    )

  config <- attr(log_this, "config")
  expect_equal(config$receiver_names, c("console", "audit"))
})

test_that("with_receivers() auto-names unnamed receivers", {
  log_this <- logger() %>%
    with_receivers(to_console(), to_identity())

  config <- attr(log_this, "config")
  expect_equal(config$receiver_names, c("receiver_1", "receiver_2"))
})

test_that("with_receivers() handles mixed named/unnamed", {
  log_this <- logger() %>%
    with_receivers(
      console = to_console(),
      to_identity()
    )

  config <- attr(log_this, "config")
  expect_equal(config$receiver_names, c("console", "receiver_2"))
})

test_that("with_receivers() handles name collisions on append", {
  log_this <- logger() %>%
    with_receivers(console = to_console())

  # Add another receiver with same name (should get _2 suffix)
  log_this <- log_this %>%
    with_receivers(console = to_identity())

  config <- attr(log_this, "config")
  expect_equal(config$receiver_names, c("console", "console_2"))
})

test_that("with_receivers() resets names when append=FALSE", {
  log_this <- logger() %>%
    with_receivers(console = to_console(), audit = to_identity())

  # Replace with new receivers
  log_this <- log_this %>%
    with_receivers(new_recv = to_console(), append = FALSE)

  config <- attr(log_this, "config")
  expect_equal(config$receiver_names, "new_recv")
  expect_equal(length(config$receivers), 1)
})

# =============================================================================
# get_receiver() Tests
# =============================================================================

test_that("get_receiver() retrieves by name", {
  log_this <- logger() %>%
    with_receivers(console = to_console(), audit = to_identity())

  recv <- get_receiver(log_this, "console")
  expect_s3_class(recv, "log_receiver")
})

test_that("get_receiver() retrieves by index", {
  log_this <- logger() %>%
    with_receivers(to_console(), to_identity())

  recv <- get_receiver(log_this, 1)
  expect_s3_class(recv, "log_receiver")

  recv2 <- get_receiver(log_this, 2)
  expect_s3_class(recv2, "log_receiver")
})

test_that("get_receiver() errors on invalid name", {
  log_this <- logger() %>%
    with_receivers(console = to_console())

  expect_error(
    get_receiver(log_this, "nonexistent"),
    "not found"
  )
})

test_that("get_receiver() errors on out of bounds index", {
  log_this <- logger() %>%
    with_receivers(to_console())

  expect_error(
    get_receiver(log_this, 5),
    "out of bounds"
  )

  expect_error(
    get_receiver(log_this, 0),
    "out of bounds"
  )
})

# =============================================================================
# flush() Tests
# =============================================================================

test_that("flush() succeeds with no receivers", {
  log_this <- logger()

  # Should not error
  expect_silent(flush(log_this))
})

test_that("flush() succeeds with non-buffered receivers", {
  log_this <- logger() %>%
    with_receivers(console = to_console(), audit = to_identity())

  # Should not error (these receivers don't have flush functions)
  expect_silent(flush(log_this))
})

test_that("flush() errors when targeting non-existent receiver by name", {
  log_this <- logger() %>%
    with_receivers(console = to_console())

  expect_error(
    flush(log_this, receivers = "nonexistent"),
    "not found"
  )
})

test_that("flush() errors when targeting out of bounds index", {
  log_this <- logger() %>%
    with_receivers(to_console())

  expect_error(
    flush(log_this, receivers = 5),
    "out of bounds"
  )
})

test_that("flush() errors when logger has no named receivers but name provided", {
  log_this <- logger() %>%
    with_receivers(to_console())  # Auto-named "receiver_1"

  # Can flush by auto-generated name
  expect_silent(flush(log_this, receivers = "receiver_1"))
})

# =============================================================================
# buffer_status() Tests
# =============================================================================

test_that("buffer_status() returns NULL for logger with no receivers", {
  log_this <- logger()

  expect_null(buffer_status(log_this))
})

test_that("buffer_status() returns named vector for non-buffered receivers", {
  log_this <- logger() %>%
    with_receivers(console = to_console(), audit = to_identity())

  status <- buffer_status(log_this)

  expect_true(is.numeric(status))
  expect_equal(names(status), c("console", "audit"))
  expect_true(all(is.na(status)))  # Non-buffered receivers return NA
})

# =============================================================================
# Integration with print.logger()
# =============================================================================

test_that("print.logger() shows receiver names", {
  log_this <- logger() %>%
    with_receivers(
      console = to_console(),
      audit = to_identity()
    )

  output <- capture.output(print(log_this))

  expect_true(any(grepl("\\[console\\]", output)))
  expect_true(any(grepl("\\[audit\\]", output)))
})

test_that("print.logger() falls back to indices when no names", {
  # Create logger with old config structure (no receiver_names)
  log_this <- logger()
  config <- attr(log_this, "config")
  config$receivers <- list(to_console())
  config$receiver_labels <- list("to_console()")
  config$receiver_names <- NULL  # Simulate old logger
  attr(log_this, "config") <- config

  output <- capture.output(print(log_this))

  expect_true(any(grepl("\\[1\\]", output)))
})
