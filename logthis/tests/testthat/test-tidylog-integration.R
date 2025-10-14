test_that("parse_tidylog_message extracts operation and details", {
  msg1 <- "filter: removed 18 rows (56%), 14 rows remaining"
  result1 <- logthis:::parse_tidylog_message(msg1)

  expect_equal(result1$operation, "filter")
  expect_equal(result1$details, "removed 18 rows (56%), 14 rows remaining")

  msg2 <- "mutate: new variable 'efficiency' (double) with 14 unique values"
  result2 <- logthis:::parse_tidylog_message(msg2)

  expect_equal(result2$operation, "mutate")
  expect_true(grepl("new variable", result2$details))
}
)


test_that("log_tidyverse requires tidylog package", {
  if (requireNamespace("tidylog", quietly = TRUE)) {
    skip("tidylog package is installed")
  }

  expect_error(
    log_tidyverse(),
    "Package 'tidylog' is required"
  )
})


test_that("log_tidyverse creates custom output function", {
  skip_if_not_installed("tidylog")

  # Capture events
  events <- list()
  capture_receiver <- receiver(function(event) {
    events <<- append(events, list(event))
    invisible(NULL)
  })

  log_test <- logger() %>% with_receivers(capture_receiver)

  # Enable tidylog with logthis
  log_tidyverse(
    logger = log_test,
    user_id = "test_user",
    pipeline_id = "test_pipeline"
  )

  # Check that tidylog.display option is set
  display_opts <- getOption("tidylog.display")
  expect_type(display_opts, "list")
  expect_true("message" %in% names(display_opts))
})


test_that("track_transformation logs transformation details", {
  skip_if_not_installed("digest")

  before <- data.frame(x = 1:10, y = letters[1:10])
  after <- data.frame(x = 1:5, y = letters[1:5])

  events <- list()
  capture_receiver <- receiver(function(event) {
    events <<- append(events, list(event))
    invisible(NULL)
  })

  log_test <- logger() %>% with_receivers(capture_receiver)

  result <- track_transformation(
    data_before = before,
    data_after = after,
    operation_name = "subset_top_5",
    logger = log_test,
    user_id = "analyst",
    criteria = "top 5 rows"
  )

  # Function returns data_after (invisibly per documentation)
  expect_equal(result, after)
  expect_length(events, 1)

  event <- events[[1]]
  expect_equal(event$operation, "subset_top_5")
  expect_equal(event$rows_before, 10)
  expect_equal(event$rows_after, 5)
  expect_equal(event$rows_removed, 5)
  expect_equal(event$user_id, "analyst")
  expect_equal(event$criteria, "top 5 rows")
  expect_true(!is.null(event$input_hash))
  expect_true(!is.null(event$output_hash))
})


test_that("disable_tidylog resets options", {
  skip_if_not_installed("tidylog")

  # Enable tidylog
  log_tidyverse(logger = logger() %>% with_receivers(to_void()))

  # Verify it's enabled
  expect_type(getOption("tidylog.display"), "list")

  # Disable
  disable_tidylog()

  # Verify it's disabled
  expect_null(getOption("tidylog.display"))
})


test_that("with_pipeline_audit tracks pipeline execution", {
  skip_if_not_installed("digest")
  skip_if_not_installed("dplyr")

  events <- list()
  capture_receiver <- receiver(function(event) {
    events <<- append(events, list(event))
    invisible(NULL)
  })

  log_test <- logger() %>% with_receivers(capture_receiver)

  # Simple pipeline without tidylog
  options(tidylog.display = NULL)  # Disable tidylog

  test_data <- data.frame(x = 1:10, y = 1:10)

  result <- with_pipeline_audit(
    data = test_data,
    pipeline_expr = ~ dplyr::filter(., x > 5),
    logger = log_test,
    pipeline_name = "test_filter",
    user_id = "tester"
  )

  # Should have start and end events
  expect_gte(length(events), 2)

  # Check start event
  start_event <- events[[1]]
  expect_true(grepl("started", start_event$message, ignore.case = TRUE))
  expect_equal(start_event$pipeline_name, "test_filter")
  expect_equal(start_event$input_rows, 10)

  # Check end event
  end_event <- events[[length(events)]]
  expect_true(grepl("completed", end_event$message, ignore.case = TRUE))
  expect_equal(end_event$output_rows, 5)
  expect_equal(end_event$rows_changed, -5)
})


test_that("with_pipeline_audit handles errors gracefully", {
  skip_if_not_installed("digest")

  events <- list()
  capture_receiver <- receiver(function(event) {
    events <<- append(events, list(event))
    invisible(NULL)
  })

  log_test <- logger() %>% with_receivers(capture_receiver)

  test_data <- data.frame(x = 1:10)

  expect_error(
    with_pipeline_audit(
      data = test_data,
      pipeline_expr = ~ stop("Intentional error"),
      logger = log_test,
      pipeline_name = "failing_pipeline",
      user_id = "tester"
    ),
    "Intentional error"
  )

  # Should have logged the error
  error_events <- Filter(function(e) e$level_class == "ERROR", events)
  expect_gte(length(error_events), 1)

  error_event <- error_events[[1]]
  expect_true(grepl("failed", error_event$message, ignore.case = TRUE))
  expect_equal(error_event$pipeline_name, "failing_pipeline")
})


test_that("with_pipeline_audit validates output when function provided", {
  skip_if_not_installed("digest")

  events <- list()
  capture_receiver <- receiver(function(event) {
    events <<- append(events, list(event))
    invisible(NULL)
  })

  log_test <- logger() %>% with_receivers(capture_receiver)

  test_data <- data.frame(x = 1:10)

  # Validation that fails
  expect_error(
    with_pipeline_audit(
      data = test_data,
      pipeline_expr = ~ .,
      logger = log_test,
      pipeline_name = "validation_test",
      user_id = "tester",
      validate_output = function(data) {
        stop("Validation failed!")
      }
    ),
    "Validation failed"
  )

  # Should have logged validation error
  error_events <- Filter(function(e) e$level_class == "ERROR", events)
  expect_gte(length(error_events), 1)
})


test_that("get_pipeline_summary extracts pipeline information", {
  skip_if_not_installed("jsonlite")
  skip_if_not_installed("dplyr")
  skip_if_not_installed("digest")

  temp_file <- tempfile(fileext = ".jsonl")

  log_test <- logger() %>%
    with_receivers(to_json() %>% on_local(path = temp_file))

  # Log some pipeline events
  log_test(
    NOTE(
      "Pipeline started: test_pipeline",
      pipeline_name = "test_pipeline",
      user_id = "analyst",
      operation = "start"
    )
  )

  log_test(
    NOTE(
      "Transformation: filter",
      pipeline_name = "test_pipeline",
      user_id = "analyst",
      operation = "filter"
    )
  )

  log_test(
    NOTE(
      "Pipeline completed: test_pipeline",
      pipeline_name = "test_pipeline",
      user_id = "analyst",
      operation = "complete"
    )
  )

  # Get summary
  summary <- get_pipeline_summary(temp_file, pipeline_name = "test_pipeline")

  expect_s3_class(summary, "data.frame")
  expect_equal(nrow(summary), 1)
  expect_equal(summary$pipeline_name[1], "test_pipeline")
  expect_equal(summary$user_id[1], "analyst")
  expect_gte(summary$n_operations[1], 3)

  # Clean up
  unlink(temp_file)
})


test_that("track_transformation requires digest package", {
  if (requireNamespace("digest", quietly = TRUE)) {
    skip("digest package is installed")
  }

  expect_error(
    track_transformation(
      data_before = data.frame(x = 1),
      data_after = data.frame(x = 1),
      operation_name = "test",
      logger = logger() %>% with_receivers(to_void())
    ),
    "Package 'digest' is required"
  )
})


test_that("with_pipeline_audit accepts formula syntax", {
  skip_if_not_installed("digest")
  skip_if_not_installed("dplyr")

  log_test <- logger() %>% with_receivers(to_void())

  test_data <- data.frame(x = 1:10)

  # Formula syntax
  result <- with_pipeline_audit(
    data = test_data,
    pipeline_expr = ~ dplyr::filter(., x > 5),
    logger = log_test,
    pipeline_name = "formula_test"
  )

  expect_equal(nrow(result), 5)
})
