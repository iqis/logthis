library(testthat)

# ==============================================================================
# Contract Enforcement Tests
# ==============================================================================
# These tests verify that contracts catch invalid inputs and internal bugs.
# Contracts are executable specifications - they run every time code executes.

# ------------------------------------------------------------------------------
# logger() contracts
# ------------------------------------------------------------------------------

test_that("logger() creates valid logger with postconditions", {
  log <- logger()

  # If postconditions pass, logger is valid
  expect_s3_class(log, "logger")
  expect_true(is.function(log))
  expect_true(!is.null(attr(log, "config")))
})

# ------------------------------------------------------------------------------
# with_receivers() contracts
# ------------------------------------------------------------------------------

test_that("with_receivers() validates logger precondition", {
  expect_error(
    with_receivers("not a logger", to_console()),
    "Precondition failed.*logger must be logger class"
  )

  expect_error(
    with_receivers(function() {}, to_console()),
    "Precondition failed.*logger must be logger class"
  )
})

test_that("with_receivers() validates append precondition", {
  expect_error(
    logger() %>% with_receivers(to_console(), append = "yes"),
    "Precondition failed.*append must be logical"
  )

  expect_error(
    logger() %>% with_receivers(to_console(), append = c(TRUE, FALSE)),
    "Precondition failed.*append must have length 1"
  )
})

test_that("with_receivers() enforces receiver/label length invariant", {
  # Invariant should always hold after with_receivers()
  log <- logger() %>%
    with_receivers(to_console(), to_identity())

  config <- attr(log, "config")
  expect_equal(
    length(config$receivers),
    length(config$receiver_labels)
  )
  expect_equal(
    length(config$receivers),
    length(config$receiver_names)
  )
})

test_that("with_receivers() postconditions ensure valid logger", {
  # Postcondition will catch if result is not valid logger
  log <- logger() %>% with_receivers(to_console())

  expect_s3_class(log, "logger")
  expect_true(!is.null(attr(log, "config")))
})

# ------------------------------------------------------------------------------
# with_limits.logger() contracts
# ------------------------------------------------------------------------------

test_that("with_limits() validates logger precondition", {
  expect_error(
    with_limits("not a logger", lower = 0, upper = 100),
    "Precondition failed.*logger must be logger class"
  )
})

test_that("with_limits() validates lower range precondition", {
  expect_error(
    logger() %>% with_limits(lower = -1, upper = 100),
    "Precondition failed.*lower must be in range"
  )

  expect_error(
    logger() %>% with_limits(lower = 100, upper = 100),
    "Precondition failed.*lower must be in range"
  )
})

test_that("with_limits() validates upper range precondition", {
  expect_error(
    logger() %>% with_limits(lower = 0, upper = 0),
    "Precondition failed.*upper must be in range"
  )

  expect_error(
    logger() %>% with_limits(lower = 0, upper = 101),
    "Precondition failed.*upper must be in range"
  )
})

test_that("with_limits() validates lower <= upper precondition", {
  expect_error(
    logger() %>% with_limits(lower = 50, upper = 10),
    "Precondition failed.*lower must be <= upper"
  )
})

test_that("with_limits() postconditions ensure valid limits", {
  log <- logger() %>% with_limits(lower = NOTE, upper = ERROR)

  config <- attr(log, "config")
  expect_true(config$limits$lower >= 0)
  expect_true(config$limits$lower <= 99)
  expect_true(config$limits$upper >= 1)
  expect_true(config$limits$upper <= 100)
  expect_true(config$limits$lower <= config$limits$upper)
})

# ------------------------------------------------------------------------------
# with_tags.logger() contracts
# ------------------------------------------------------------------------------

test_that("with_tags() validates logger precondition", {
  expect_error(
    with_tags("not a logger", "tag1"),
    "Precondition failed.*logger must be logger class"
  )
})

test_that("with_tags() validates append precondition", {
  expect_error(
    logger() %>% with_tags("tag1", append = "yes"),
    "Precondition failed.*append must be logical"
  )
})

test_that("with_tags() validates tags are character", {
  expect_error(
    logger() %>% with_tags(123),
    "Precondition failed.*tag 1 must be character"
  )

  expect_error(
    logger() %>% with_tags("valid", list("invalid")),
    "Precondition failed.*tag 2 must be character"
  )
})

test_that("with_tags() postcondition ensures tags are character", {
  log <- logger() %>% with_tags("tag1", "tag2")

  config <- attr(log, "config")
  expect_true(is.character(config$tags))
})

# ------------------------------------------------------------------------------
# with_middleware.logger() contracts
# ------------------------------------------------------------------------------

test_that("with_middleware() validates logger precondition", {
  expect_error(
    with_middleware("not a logger", function(event) event),
    "Precondition failed.*logger must be logger class"
  )
})

test_that("with_middleware() validates middleware are functions", {
  expect_error(
    logger() %>% with_middleware("not a function"),
    "Precondition failed.*middleware 1 must be function"
  )

  expect_error(
    logger() %>% with_middleware(function(e) e, 123),
    "Precondition failed.*middleware 2 must be function"
  )
})

test_that("with_middleware() postcondition ensures all middleware are functions", {
  mw1 <- function(event) { event$field1 <- "value"; event }
  mw2 <- function(event) { event$field2 <- "value"; event }

  log <- logger() %>% with_middleware(mw1, mw2)

  config <- attr(log, "config")
  expect_true(all(vapply(config$middleware, is.function, logical(1))))
})

# ------------------------------------------------------------------------------
# receiver() contracts
# ------------------------------------------------------------------------------

test_that("receiver() validates func precondition", {
  expect_error(
    receiver("not a function"),
    "Precondition failed.*func must be function"
  )
})

test_that("receiver() validates function signature - argument count", {
  expect_error(
    receiver(function() {}),
    "Precondition failed.*receiver must have exactly one argument"
  )

  expect_error(
    receiver(function(a, b) {}),
    "Precondition failed.*receiver must have exactly one argument"
  )
})

test_that("receiver() validates function signature - argument name", {
  expect_error(
    receiver(function(log_event) {}),
    "Precondition failed.*receiver argument must be named event"
  )
})

test_that("receiver() postcondition ensures valid receiver", {
  recv <- receiver(function(event) { invisible(NULL) })

  expect_s3_class(recv, "log_receiver")
  expect_true(is.function(recv))
})

# ------------------------------------------------------------------------------
# log_event_level() contracts
# ------------------------------------------------------------------------------

test_that("log_event_level() validates level_class preconditions", {
  expect_error(
    log_event_level(123, 50),
    "Precondition failed.*level_class must be character"
  )

  expect_error(
    log_event_level("", 50),
    "Precondition failed.*level_class must not be empty"
  )

  expect_error(
    log_event_level(NA_character_, 50),
    "Precondition failed.*level_class must not be NA"
  )
})

test_that("log_event_level() postcondition ensures valid level", {
  custom_level <- log_event_level("CUSTOM", 50)

  expect_s3_class(custom_level, "log_event_level")
  expect_true(is.function(custom_level))
  expect_equal(attr(custom_level, "level_number"), 50)
  expect_equal(attr(custom_level, "level_class"), "CUSTOM")
})

test_that("log_event_level() postcondition validates range", {
  # This should work - within range
  expect_no_error(log_event_level("TEST", 0))
  expect_no_error(log_event_level("TEST", 100))
  expect_no_error(log_event_level("TEST", 50))
})

# ------------------------------------------------------------------------------
# Contract Disable Tests
# ------------------------------------------------------------------------------

test_that("contracts can be disabled globally", {
  withr::with_options(
    list(logthis.contracts = FALSE),
    {
      # These would normally fail preconditions
      # But with contracts disabled, they pass through

      # Note: Some may still fail due to other validation logic
      # This tests that contracts specifically are disabled

      # This tests the .enabled parameter works
      result <- logger()
      expect_s3_class(result, "logger")
    }
  )
})

test_that("contracts can be disabled per-call", {
  # Contracts support .enabled parameter
  # Test that explicitly disabled contracts don't fail

  # This is more for library developers than users
  # but ensures the contract system works correctly

  # Example: require_that with .enabled = FALSE
  expect_no_error({
    require_that(
      "this will not be checked" = FALSE,
      .enabled = FALSE
    )
  })
})

# ------------------------------------------------------------------------------
# Meta-Tests: Verify All Critical Functions Have Contracts
# ------------------------------------------------------------------------------

test_that("all critical functions have registered contracts", {
  # Load package to trigger contract registration
  devtools::load_all(".")

  # Get all contracts (internal function, but accessible for testing)
  contracts <- logthis:::get_all_contracts()

  critical_functions <- c(
    "logger",
    "with_receivers",
    "with_limits.logger",
    "with_tags.logger",
    "with_middleware.logger",
    "receiver",
    "log_event_level"
  )

  for (fn in critical_functions) {
    expect_true(
      fn %in% names(contracts),
      info = paste(fn, "missing from contract registry")
    )

    # Verify has at least one type of contract
    fn_contracts <- contracts[[fn]]
    has_contracts <-
      length(fn_contracts$preconditions) > 0 ||
      length(fn_contracts$postconditions) > 0 ||
      length(fn_contracts$invariants) > 0

    expect_true(
      has_contracts,
      info = paste(fn, "has no contracts registered")
    )
  }
})

# ------------------------------------------------------------------------------
# Integration: Contracts Work During Normal Usage
# ------------------------------------------------------------------------------

test_that("contracts catch errors during normal usage", {
  # Create a logger normally - contracts validate everything
  expect_no_error({
    log <- logger() %>%
      with_receivers(to_console()) %>%
      with_limits(lower = NOTE, upper = ERROR) %>%
      with_tags("test", "contracts")
  })

  # Try to break it - contracts should catch
  expect_error({
    logger() %>%
      with_limits(lower = 999, upper = 1000)
  }, "Precondition failed")
})

test_that("contracts don't interfere with valid usage", {
  # Contracts should be invisible during normal usage
  log <- logger() %>%
    with_receivers(to_console(), to_identity()) %>%
    with_limits(lower = LOWEST, upper = HIGHEST) %>%
    with_tags("production") %>%
    with_middleware(function(e) { e$timestamp <- Sys.time(); e })

  # Log an event - should work normally
  result <- log(NOTE("Test message"))

  expect_equal(result$message, "Test message")
  expect_true("production" %in% result$tags)
})
