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
  }, 6)
})

test_that("log_event_level() rejects level_number outside of [0, 120].", {
  expect_error(log_event_level("TEST", -10))
  expect_error(log_event_level("TEST", 130))
})

TEST <- log_event_level("TEST", 50)
test_that("log_event_level() produces correct type.", {
  expect(is.function(TEST))
  expect_s3_class(TEST, "log_event_level")
  expect_equal(attr(TEST, "level_number"),
               50)
})


test_that("log event level function produces correct type.", {
  test_event <- TEST("Test this thing.",
                     custom_element = 999)

  expect_equivalent(attributes(test_event)$names,
                    c("message",
                      "time",
                      "level_class",
                      "level_number",
                      "custom_element"))

  expect_s3_class(test_event,
                  "log_event")

  expect_s3_class(test_event,
                  "TEST")
  expect_equal(test_event$level_class,
               "TEST")
  expect_equal(test_event$level_number,
               50)
  expect_s3_class(test_event$time,
                  "POSIXt")
  expect_equal(test_event$custom_element,
               999)
})

