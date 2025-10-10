test_that("alert_panel creates correct HTML structure", {
  ui <- alert_panel("test_alerts")

  # Should be a shiny.tag object
  expect_s3_class(ui, "shiny.tag")

  # Should have correct ID
  expect_match(as.character(ui), 'id="test_alerts_container"', fixed = TRUE)

  # Should contain uiOutput
  expect_match(as.character(ui), "test_alerts", fixed = TRUE)

  # Should contain JavaScript for config
  expect_match(as.character(ui), "Shiny.setInputValue", fixed = TRUE)
  expect_match(as.character(ui), "test_alerts_config", fixed = TRUE)
})

test_that("alert_panel respects configuration options", {
  ui <- alert_panel(
    "alerts",
    max_alerts = 5,
    dismissible = TRUE,
    auto_dismiss_ms = 3000,
    position = "bottom",
    max_height = "400px"
  )

  ui_str <- as.character(ui)

  # Check max_height style
  expect_match(ui_str, "max-height: 400px", fixed = TRUE)

  # Check config in JavaScript
  expect_match(ui_str, '"max_alerts":5', fixed = TRUE)
  expect_match(ui_str, '"dismissible":true', fixed = TRUE)
  expect_match(ui_str, '"auto_dismiss_ms":3000', fixed = TRUE)
  expect_match(ui_str, '"position":"bottom"', fixed = TRUE)
})

test_that("alert_panel validates inputs", {
  # Invalid output_id
  expect_error(
    alert_panel(c("id1", "id2")),
    "single character string"
  )

  expect_error(
    alert_panel(123),
    "single character string"
  )

  # Invalid position
  expect_error(
    alert_panel("test", position = "middle"),
    "'arg' should be one of"
  )
})

test_that("alert_panel optional parameters work", {
  # NULL auto_dismiss_ms
  ui1 <- alert_panel("test", auto_dismiss_ms = NULL)
  expect_match(as.character(ui1), '"auto_dismiss_ms":null', fixed = TRUE)

  # NULL max_height (no style)
  ui2 <- alert_panel("test", max_height = NULL)
  ui_str <- as.character(ui2)
  # Should not have max-height style when NULL
  expect_true(!grepl("max-height", ui_str, fixed = TRUE) ||
               grepl("max-height: null", ui_str, fixed = TRUE))
})
