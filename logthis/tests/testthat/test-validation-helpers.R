test_that("validate_with_audit validates inputs correctly", {
  skip_if_not_installed("validate")
  skip_if_not_installed("digest")

  # Create test data
  test_data <- data.frame(
    id = 1:5,
    age = c(25, 35, 45, 55, 65),
    weight = c(70, 80, 90, 100, 110)
  )

  # Create rules
  rules <- validate::validator(
    age_valid = age >= 18 & age <= 100,
    weight_positive = weight > 0
  )

  # Create logger that captures events
  log_capture <- logger() %>% with_receivers(to_itself())

  # Validate
  result <- validate_with_audit(
    data = test_data,
    rules = rules,
    logger = log_capture,
    user_id = "test_user",
    reason = "test validation"
  )

  # Check result
  expect_s3_class(result, "validation")
})


test_that("validate_with_audit logs all validation events", {
  skip_if_not_installed("validate")
  skip_if_not_installed("digest")

  test_data <- data.frame(
    id = 1:3,
    age = c(25, 150, 45),  # One invalid age
    weight = c(70, 80, 90)
  )

  rules <- validate::validator(
    age_valid = age >= 18 & age <= 100,
    weight_positive = weight > 0
  )

  # Capture events
  events <- list()
  capture_receiver <- receiver(function(event) {
    events <<- append(events, list(event))
    invisible(NULL)
  })

  log_capture <- logger() %>% with_receivers(capture_receiver)

  result <- validate_with_audit(
    data = test_data,
    rules = rules,
    logger = log_capture,
    user_id = "test_user"
  )

  # Should have: validation start, 2 rule results, validation complete
  expect_gte(length(events), 4)

  # Check that validation start event exists
  start_event <- events[[1]]
  expect_equal(start_event$message, "Validation started")
  expect_equal(start_event$user_id, "test_user")
  expect_equal(start_event$n_records, 3)
  expect_equal(start_event$n_rules, 2)
})


test_that("validate_with_audit requires validate package", {
  # Temporarily make validate unavailable
  if (requireNamespace("validate", quietly = TRUE)) {
    skip("validate package is installed")
  }

  log_capture <- logger() %>% with_receivers(to_itself())

  expect_error(
    validate_with_audit(
      data = data.frame(x = 1),
      rules = NULL,
      logger = log_capture
    ),
    "Package 'validate' is required"
  )
})


test_that("compare_datasets_with_audit detects differences", {
  skip_if_not_installed("arsenal")
  skip_if_not_installed("digest")

  old_data <- data.frame(
    id = 1:3,
    value = c("A", "B", "C")
  )

  new_data <- data.frame(
    id = 1:3,
    value = c("A", "X", "C")  # Changed value
  )

  events <- list()
  capture_receiver <- receiver(function(event) {
    events <<- append(events, list(event))
    invisible(NULL)
  })

  log_capture <- logger() %>% with_receivers(capture_receiver)

  result <- compare_datasets_with_audit(
    old_data = old_data,
    new_data = new_data,
    logger = log_capture,
    user_id = "test_user",
    reason = "test comparison"
  )

  # Should have: comparison start, difference(s), comparison complete
  expect_gte(length(events), 3)

  # Check for discrepancy event
  discrepancy_events <- Filter(
    function(e) grepl("discrepancy", e$message, ignore.case = TRUE),
    events
  )
  expect_gte(length(discrepancy_events), 1)
})


test_that("compare_datasets_with_audit handles identical datasets", {
  skip_if_not_installed("arsenal")
  skip_if_not_installed("digest")

  test_data <- data.frame(
    id = 1:3,
    value = c("A", "B", "C")
  )

  events <- list()
  capture_receiver <- receiver(function(event) {
    events <<- append(events, list(event))
    invisible(NULL)
  })

  log_capture <- logger() %>% with_receivers(capture_receiver)

  result <- compare_datasets_with_audit(
    old_data = test_data,
    new_data = test_data,
    logger = log_capture,
    user_id = "test_user"
  )

  # Should have: comparison start, comparison complete (no differences)
  expect_gte(length(events), 2)

  # Check completion event shows no differences
  complete_event <- events[[length(events)]]
  expect_equal(complete_event$n_differences, 0)
  expect_equal(complete_event$match_rate, 1)
})


test_that("esign_validation logs electronic signature", {
  skip_if_not_installed("digest")

  validation_result <- list(summary = "test validation")

  events <- list()
  capture_receiver <- receiver(function(event) {
    events <<- append(events, list(event))
    invisible(NULL)
  })

  log_capture <- logger() %>% with_receivers(capture_receiver)

  result <- esign_validation(
    validation_object = validation_result,
    logger = log_capture,
    user_id = "reviewer",
    password_hash = digest::digest("password"),
    meaning = "Approved"
  )

  expect_true(result)
  expect_length(events, 1)

  sig_event <- events[[1]]
  expect_equal(sig_event$message, "Electronic signature applied")
  expect_equal(sig_event$user_id, "reviewer")
  expect_equal(sig_event$meaning, "Approved")
  expect_true(!is.null(sig_event$validation_hash))
  expect_true(!is.null(sig_event$signed_at))
})


test_that("esign_validation verifies credentials when provided", {
  skip_if_not_installed("digest")

  validation_result <- list(summary = "test")

  # Create a verification function that always fails
  verify_fail <- function(user_id, password_hash) {
    return(FALSE)
  }

  events <- list()
  capture_receiver <- receiver(function(event) {
    events <<- append(events, list(event))
    invisible(NULL)
  })

  log_capture <- logger() %>% with_receivers(capture_receiver)

  expect_error(
    esign_validation(
      validation_object = validation_result,
      logger = log_capture,
      user_id = "reviewer",
      password_hash = "wrong",
      meaning = "Approved",
      verify_credentials = verify_fail
    ),
    "Invalid credentials"
  )

  # Should have logged an error event
  expect_gte(length(events), 1)
  error_event <- events[[1]]
  expect_equal(error_event$level_class, "ERROR")
  expect_true(grepl("invalid credentials", error_event$message, ignore.case = TRUE))
})


test_that("pointblank helper requires pointblank package", {
  if (requireNamespace("pointblank", quietly = TRUE)) {
    skip("pointblank package is installed")
  }

  log_capture <- logger() %>% with_receivers(to_itself())

  expect_error(
    create_agent_with_audit(
      tbl = data.frame(x = 1),
      logger = log_capture
    ),
    "Package 'pointblank' is required"
  )
})


test_that("NULL coalescing operator works", {
  # Test the internal %||% operator
  expect_equal(NULL %||% "default", "default")
  expect_equal("value" %||% "default", "value")
  expect_equal(NA %||% "default", NA)
  expect_equal(0 %||% "default", 0)
  expect_equal("" %||% "default", "")
})


test_that("validate_with_audit handles study_id and dataset_name", {
  skip_if_not_installed("validate")
  skip_if_not_installed("digest")

  test_data <- data.frame(age = c(25, 35))
  rules <- validate::validator(age_valid = age >= 18)

  events <- list()
  capture_receiver <- receiver(function(event) {
    events <<- append(events, list(event))
    invisible(NULL)
  })

  log_capture <- logger() %>% with_receivers(capture_receiver)

  validate_with_audit(
    data = test_data,
    rules = rules,
    logger = log_capture,
    user_id = "test_user",
    study_id = "STUDY-XYZ",
    dataset_name = "demographics"
  )

  # Check that study_id and dataset_name are in events
  start_event <- events[[1]]
  expect_equal(start_event$study_id, "STUDY-XYZ")
  expect_equal(start_event$dataset_name, "demographics")
})


test_that("validation helpers work with digest package", {
  skip_if_not_installed("digest")

  test_data <- data.frame(x = 1:3)

  # Test that hashing works
  hash1 <- digest::digest(test_data)
  expect_type(hash1, "character")
  expect_true(nchar(hash1) > 0)

  # Same data should produce same hash
  hash2 <- digest::digest(test_data)
  expect_equal(hash1, hash2)
})
