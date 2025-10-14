test_that("get_shiny_type maps levels correctly for shinyalert", {
  # LOWEST-TRACE (0-19) -> info
  expect_equal(get_shiny_type(0, "shinyalert"), "info")
  expect_equal(get_shiny_type(10, "shinyalert"), "info")
  expect_equal(get_shiny_type(19, "shinyalert"), "info")

  # DEBUG (20-29) -> info
  expect_equal(get_shiny_type(20, "shinyalert"), "info")
  expect_equal(get_shiny_type(29, "shinyalert"), "info")

  # NOTE (30-39) -> success
  expect_equal(get_shiny_type(30, "shinyalert"), "success")
  expect_equal(get_shiny_type(39, "shinyalert"), "success")

  # MESSAGE (40-59) -> info
  expect_equal(get_shiny_type(40, "shinyalert"), "info")
  expect_equal(get_shiny_type(50, "shinyalert"), "info")
  expect_equal(get_shiny_type(59, "shinyalert"), "info")

  # WARNING (60-79) -> warning
  expect_equal(get_shiny_type(60, "shinyalert"), "warning")
  expect_equal(get_shiny_type(70, "shinyalert"), "warning")
  expect_equal(get_shiny_type(79, "shinyalert"), "warning")

  # ERROR-HIGHEST (80+) -> error
  expect_equal(get_shiny_type(80, "shinyalert"), "error")
  expect_equal(get_shiny_type(90, "shinyalert"), "error")
  expect_equal(get_shiny_type(100, "shinyalert"), "error")
})

test_that("get_shiny_type maps levels correctly for notif", {
  # LOWEST-TRACE (0-19) -> default
  expect_equal(get_shiny_type(0, "notif"), "default")
  expect_equal(get_shiny_type(10, "notif"), "default")
  expect_equal(get_shiny_type(19, "notif"), "default")

  # DEBUG (20-29) -> default
  expect_equal(get_shiny_type(20, "notif"), "default")
  expect_equal(get_shiny_type(29, "notif"), "default")

  # NOTE (30-39) -> message
  expect_equal(get_shiny_type(30, "notif"), "message")
  expect_equal(get_shiny_type(39, "notif"), "message")

  # MESSAGE (40-59) -> message
  expect_equal(get_shiny_type(40, "notif"), "message")
  expect_equal(get_shiny_type(50, "notif"), "message")
  expect_equal(get_shiny_type(59, "notif"), "message")

  # WARNING (60-79) -> warning
  expect_equal(get_shiny_type(60, "notif"), "warning")
  expect_equal(get_shiny_type(70, "notif"), "warning")
  expect_equal(get_shiny_type(79, "notif"), "warning")

  # ERROR-HIGHEST (80+) -> error
  expect_equal(get_shiny_type(80, "notif"), "error")
  expect_equal(get_shiny_type(90, "notif"), "error")
  expect_equal(get_shiny_type(100, "notif"), "error")
})

test_that("receivers are created with correct class", {
  expect_s3_class(to_shinyalert(), "log_receiver")
  expect_s3_class(to_notif(), "log_receiver")
  expect_s3_class(to_sweetalert(), "log_receiver")
  expect_s3_class(to_show_toast(), "log_receiver")
  expect_s3_class(to_toastr(), "log_receiver")
  expect_s3_class(to_js_console(), "log_receiver")
  expect_s3_class(to_alert_panel("test_id"), "log_receiver")
})

test_that("receivers respect level filtering", {
  # Create a receiver that only accepts WARNING and above
  recv <- to_shinyalert(lower = logthis::WARNING(), upper = logthis::HIGHEST())

  # Test that it's a function
  expect_type(recv, "closure")
  expect_s3_class(recv, "log_receiver")
})
