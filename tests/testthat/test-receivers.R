library(testthat)
library(purrr)

test_that("all receivers generate the correct type", {
  list(to_identity,
       to_void,
       to_console) %>%
    map(exec) %>%
    map(~ expect_s3_class(., "function")) %>%
    map(~ expect_s3_class(., "log_receiver"))
})

TEST <- log_event_level("TEST", 50)
test_event <- TEST("Testing things.")

test_that("to_identity()() returns the same object", {
  expect_identical(to_identity()(test_event),
                   test_event)
})


test_that("to_console()() returns NULL", {
  expect_null(to_console()(test_event))
})

test_that("to_console()() rejects wrong types given to `event`", {
  to_console()(test_event)
  expect_error(to_console()(""))
  expect_error(to_console()(NULL))
  expect_error(to_console()(NA))
  expect_error(to_console()(123))
})

test_that("with_limits.log_receiver() creates wrapper with new limits", {
  # Create a receiver with initial limits
  recv <- to_identity()

  # Apply new limits via with_limits
  limited_recv <- recv %>% with_limits(lower = WARNING, upper = ERROR)

  # Should still be a log_receiver
  expect_s3_class(limited_recv, "log_receiver")
  expect_s3_class(limited_recv, "function")

  # Check that limits are stored as attributes (as numeric values)
  expect_equal(as.numeric(attr(limited_recv, "lower")), 80)
  expect_equal(as.numeric(attr(limited_recv, "upper")), 100)
})

test_that("with_limits.log_receiver() filters events correctly", {
  # Create a capturing receiver
  captured <- NULL
  capture_recv <- receiver(function(event) {
    captured <<- event
    invisible(NULL)
  })

  # Apply limits to only accept WARNING and above
  limited_recv <- capture_recv %>% with_limits(lower = WARNING, upper = HIGHEST)

  # Event below limit should not be captured
  captured <- NULL
  limited_recv(NOTE("Should be filtered"))
  expect_null(captured)

  # Event within limits should be captured
  warn_event <- WARNING("Should pass")
  limited_recv(warn_event)
  expect_equal(captured$message, "Should pass")
})

test_that("with_limits.log_receiver() validates limit ranges", {
  recv <- to_identity()

  # Lower limit out of range
  expect_error(recv %>% with_limits(lower = -1), "Lower limit must be in \\[0, 119\\]")
  expect_error(recv %>% with_limits(lower = 120), "Lower limit must be in \\[0, 119\\]")

  # Upper limit out of range
  expect_error(recv %>% with_limits(upper = 0), "Upper limit must be in \\[1, 120\\]")
  expect_error(recv %>% with_limits(upper = 121), "Upper limit must be in \\[1, 120\\]")
})

test_that("to_text_file() with rotation creates rotated files", {
  # Create a temporary directory for testing
  temp_dir <- tempdir()
  log_path <- file.path(temp_dir, "test_rotation.log")

  # Clean up any existing test files
  unlink(paste0(log_path, "*"))

  # Create a file receiver with small max_size for testing (100 bytes)
  file_recv <- to_text_file(path = log_path, max_size = 100, max_files = 3)

  # Write enough events to trigger rotation
  for (i in 1:10) {
    file_recv(NOTE(paste("Test message number", i, "with some extra text to increase size")))
  }

  # Check that rotated files exist
  expect_true(file.exists(log_path))

  # At least one rotation should have occurred
  rotated_files <- list.files(temp_dir, pattern = basename(paste0(log_path, "\\.[0-9]+")), full.names = TRUE)
  expect_true(length(rotated_files) > 0)

  # Clean up
  unlink(log_path)
  unlink(rotated_files)
})

test_that("to_text_file() without rotation does not create rotated files", {
  temp_dir <- tempdir()
  log_path <- file.path(temp_dir, "test_no_rotation.log")

  # Clean up any existing test files
  unlink(paste0(log_path, "*"))

  # Create a file receiver without rotation
  file_recv <- to_text_file(path = log_path)

  # Write some events
  for (i in 1:5) {
    file_recv(NOTE(paste("Test message", i)))
  }

  # Check that no rotated files exist
  rotated_files <- list.files(temp_dir, pattern = basename(paste0(log_path, "\\.[0-9]+")), full.names = TRUE)
  expect_equal(length(rotated_files), 0)

  # Clean up
  unlink(log_path)
})

test_that("logger handles receiver failures gracefully", {
  # Create a failing receiver for testing
  failing_receiver <- function() {
    receiver(function(event) {
      stop("Simulated receiver failure")
    })
  }

  # Logger with failing receiver should still execute other receivers
  captured_output <- capture.output({
    log_test <- logger() %>%
      with_receivers(
        to_console(),
        failing_receiver(),
        to_console()
      )

    log_test(NOTE("This message should appear despite receiver #2 failing"))
  })

  # Should see the original message twice (from receiver #1 and #3)
  note_lines <- grep("\\[NOTE\\].*This message should appear", captured_output)
  expect_equal(length(note_lines), 2)

  # Should see an error message about receiver failure
  error_lines <- grep("\\[ERROR\\].*Receiver #2 failed", captured_output)
  expect_equal(length(error_lines), 1)

  # Error message should include receiver provenance
  expect_true(any(grepl("Receiver: failing_receiver\\(\\)", captured_output)))
})

test_that("receiver labels are captured correctly", {
  log_test <- logger() %>%
    with_receivers(to_console(), to_identity())

  config <- attr(log_test, "config")

  # Should have captured receiver labels
  expect_equal(length(config$receiver_labels), 2)
  expect_equal(config$receiver_labels[[1]], "to_console()")
  expect_equal(config$receiver_labels[[2]], "to_identity()")
})

test_that("to_text_file() supports file rotation by size", {
  temp_dir <- tempdir()
  log_path <- file.path(temp_dir, "rotate_test.log")

  # Clean up any existing files
  unlink(paste0(log_path, "*"))

  # Create receiver with 200 byte max size (small for testing)
  file_recv <- to_text_file(path = log_path, append = TRUE, max_size = 200, max_files = 3)
  log_test <- logger() %>% with_receivers(file_recv)

  # Write enough messages to trigger rotation
  for (i in 1:10) {
    log_test(NOTE(paste("Log message number", i, "with some extra text to fill space")))
  }

  # Should have created rotated files
  expect_true(file.exists(log_path))
  expect_true(file.exists(paste0(log_path, ".1")))

  # Should not have more than max_files
  expect_false(file.exists(paste0(log_path, ".4")))

  # Clean up
  unlink(paste0(log_path, "*"))
})

test_that("to_text_file() rotation preserves correct order", {
  temp_dir <- tempdir()
  log_path <- file.path(temp_dir, "order_test.log")

  # Clean up
  unlink(paste0(log_path, "*"))

  # Create small file and force rotation
  file_recv <- to_text_file(path = log_path, append = TRUE, max_size = 100, max_files = 3)
  log_test <- logger() %>% with_receivers(file_recv)

  # First batch of messages
  log_test(NOTE("First message"))
  log_test(NOTE("Second message with enough text to trigger rotation soon"))
  log_test(NOTE("Third message with enough text to trigger rotation soon"))

  # Check that oldest logs are in .1, newer in main file
  main_content <- readLines(log_path)
  expect_true(any(grepl("Third message", main_content)))

  if (file.exists(paste0(log_path, ".1"))) {
    old_content <- readLines(paste0(log_path, ".1"))
    expect_true(any(grepl("First message|Second message", old_content)))
  }

  # Clean up
  unlink(paste0(log_path, "*"))
})
