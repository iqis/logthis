test_that("log_event_level() rejects non-character types.", {
  expect_error(log_event_level(10, 50))
  expect_error(log_event_level(0.5, 50))
  expect_error(log_event_level(TRUE, 50))
})

test_that("log_event_level() rejects nully class name.", {
  expect_error(log_event_level(level_number = 50))
  expect_error(log_event_level("", 50))
  expect_error(log_event_level(NULL, 50))
  expect_error(log_event_level(NA, 50))
})


test_that("log_event_level() rejects non-numeric values passed to `level_number`.", {
  expect_error(log_event_level("TEST", "wow"))
  expect_error(log_event_level("TEST", list()))
})

test_that("log_event_level() rounds `level_number`", {
  expect_warning(log_event_level("TEST", 5.5))

  expect_equal({
    TEST <- log_event_level("TEST", 5.5)
    attr(TEST, "level_number")
  }, structure(6, class = "level_number"))
})

test_that("log_event_level() rejects level_number outside of [0, 100].", {
  expect_error(log_event_level("TEST", -10))
  expect_error(log_event_level("TEST", 130))
})

TEST <- log_event_level("TEST", 50)
test_that("log_event_level() produces correct type.", {
  expect(is.function(TEST))
  expect_s3_class(TEST, "log_event_level")
  expect_equal(attr(TEST, "level_number"),
               structure(50, class = "level_number"))
})


test_that("log event level function produces correct type.", {
  test_event <- TEST("Test this thing.",
                     custom_element = 999)

  expect_equivalent(attributes(test_event)$names,
                    c("message",
                      "time",
                      "level_class",
                      "level_number",
                      "tags",
                      "custom_element"))

  expect_s3_class(test_event,
                  "log_event")

  expect_s3_class(test_event,
                  "TEST")
  expect_equal(test_event$level_class,
               "TEST")
  expect_equal(test_event$level_number,
               structure(50, class = "level_number"))
  expect_s3_class(test_event$time,
                  "POSIXt")
  expect_equal(test_event$custom_element,
               999)
})


test_that("event message supports glue interpolation", {
  user_id <- 123
  amount <- 99.99
  event <- TEST("User {user_id} paid {amount}", user_id = user_id, amount = amount)

  # Message should be interpolated
  expect_equal(event$message, "User 123 paid 99.99")

  # Custom fields should still be attached
  expect_equal(event$user_id, 123)
  expect_equal(event$amount, 99.99)
})


test_that("event message without template syntax not interpolated", {
  # Plain message should pass through unchanged
  event <- TEST("Plain message", user_id = 123)
  expect_equal(event$message, "Plain message")
  expect_equal(event$user_id, 123)
})


test_that("custom fields reject functions", {
  expect_error(
    TEST("Test", bad_field = function() NULL),
    "cannot be a function"
  )
})


test_that("custom fields reject environments", {
  expect_error(
    TEST("Test", bad_field = new.env()),
    "cannot be an environment"
  )
})


test_that("custom fields reject connections", {
  skip_on_cran()
  tmp_file <- tempfile()
  conn <- file(tmp_file, "w")
  expect_error(
    TEST("Test", bad_field = conn),
    "cannot be a connection"
  )
  close(conn)
  unlink(tmp_file)
})


test_that("custom fields reject large strings", {
  large_string <- paste(rep("a", 11000), collapse = "")
  expect_error(
    TEST("Test", large_field = large_string),
    "too large"
  )
})


test_that("custom fields warn about large vectors", {
  large_vector <- 1:1001
  expect_warning(
    TEST("Test", large_field = large_vector),
    "large vector"
  )
})


test_that("custom fields warn about large data.frames", {
  large_df <- data.frame(x = 1:11, y = 1:11)
  expect_warning(
    TEST("Test", large_field = large_df),
    "large data.frame"
  )
})

