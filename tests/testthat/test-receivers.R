library(testthat)
library(purrr)

test_that("all receivers generate the correct type", {
  list(to_identity,
       to_void,
       to_zero,
       to_one,
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

# # verify output
# test_that("...", {
#   expect_output(to_console()(test_event()),
#                 "sth")
# })
