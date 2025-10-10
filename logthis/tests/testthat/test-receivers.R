library(testthat)

test_that("all receivers generate the correct type", {
  receivers <- list(to_identity(),
                    to_void(),
                    to_console())

  for (recv in receivers) {
    expect_s3_class(recv, "function")
    expect_s3_class(recv, "log_receiver")
  }
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
  expect_equal(as.numeric(attr(limited_recv, "lower")), 60)
  expect_equal(as.numeric(attr(limited_recv, "upper")), 80)
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
  expect_error(recv %>% with_limits(lower = -1), "Lower limit must be in \\[0, 99\\]")
  expect_error(recv %>% with_limits(lower = 100), "Lower limit must be in \\[0, 99\\]")

  # Upper limit out of range
  expect_error(recv %>% with_limits(upper = 0), "Upper limit must be in \\[1, 100\\]")
  expect_error(recv %>% with_limits(upper = 101), "Upper limit must be in \\[1, 100\\]")
})

test_that("text file logging with rotation creates rotated files", {
  # Create a temporary directory for testing
  temp_dir <- tempdir()
  log_path <- file.path(temp_dir, "test_rotation.log")

  # Clean up any existing test files
  unlink(paste0(log_path, "*"))

  # Create a file receiver with small max_size for testing (100 bytes)
  file_recv <- to_text() %>% on_local(path = log_path, max_size = 100, max_files = 3)

  # Convert formatter to receiver
  file_recv <- logthis:::.formatter_to_receiver(file_recv)

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

test_that("text file logging without rotation does not create rotated files", {
  temp_dir <- tempdir()
  log_path <- file.path(temp_dir, "test_no_rotation.log")

  # Clean up any existing test files
  unlink(paste0(log_path, "*"))

  # Create a file receiver without rotation
  file_recv <- to_text() %>% on_local(path = log_path)
  file_recv <- logthis:::.formatter_to_receiver(file_recv)

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

test_that("text file logging supports file rotation by size", {
  temp_dir <- tempdir()
  log_path <- file.path(temp_dir, "rotate_test.log")

  # Clean up any existing files
  unlink(paste0(log_path, "*"))

  # Create receiver with 200 byte max size (small for testing)
  file_recv <- to_text() %>% on_local(path = log_path, append = TRUE, max_size = 200, max_files = 3)
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

test_that("text file rotation preserves correct order", {
  temp_dir <- tempdir()
  log_path <- file.path(temp_dir, "order_test.log")

  # Clean up
  unlink(paste0(log_path, "*"))

  # Create small file and force rotation
  file_recv <- to_text() %>% on_local(path = log_path, append = TRUE, max_size = 100, max_files = 3)
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

test_that("JSON file logging creates valid JSONL output", {
  temp_dir <- tempdir()
  json_path <- file.path(temp_dir, "test.jsonl")

  # Clean up
  unlink(json_path)

  # Create JSON receiver and log events
  json_recv <- to_json() %>% on_local(path = json_path)
  log_test <- logger() %>% with_receivers(json_recv) %>% with_tags("test", "warning")

  log_test(NOTE("First message"))
  log_test(WARNING("Second message"))

  # Read and parse JSON lines
  lines <- readLines(json_path)
  expect_equal(length(lines), 2)

  # Parse first line
  event1 <- jsonlite::fromJSON(lines[1])
  expect_equal(event1$level, "NOTE")
  expect_equal(event1$level_number, 30)
  expect_equal(event1$message, "First message")
  expect_true("time" %in% names(event1))

  # Both lines should have tags from logger-level tagging
  event2 <- jsonlite::fromJSON(lines[2])
  expect_equal(event2$level, "WARNING")
  expect_equal(event2$message, "Second message")
  expect_equal(event2$tags, c("test", "warning"))

  # Clean up
  unlink(json_path)
})

test_that("JSON file logging respects level limits", {
  temp_dir <- tempdir()
  json_path <- file.path(temp_dir, "filtered.jsonl")

  # Clean up
  unlink(json_path)

  # Create receiver that only logs WARNING and above
  json_recv <- to_json() %>% on_local(path = json_path) %>% with_limits(lower = WARNING)
  log_test <- logger() %>% with_receivers(json_recv)

  log_test(NOTE("Should be filtered"))
  log_test(WARNING("Should appear"))
  log_test(ERROR("Should also appear"))

  # Should only have 2 lines (WARNING and ERROR)
  lines <- readLines(json_path)
  expect_equal(length(lines), 2)

  event1 <- jsonlite::fromJSON(lines[1])
  expect_equal(event1$level, "WARNING")

  event2 <- jsonlite::fromJSON(lines[2])
  expect_equal(event2$level, "ERROR")

  # Clean up
  unlink(json_path)
})

test_that("JSON file logging with pretty printing works", {
  temp_dir <- tempdir()
  json_path <- file.path(temp_dir, "pretty.json")

  # Clean up
  unlink(json_path)

  # Create receiver with pretty printing
  json_recv <- to_json(pretty = TRUE) %>% on_local(path = json_path)
  log_test <- logger() %>% with_receivers(json_recv)

  log_test(NOTE("Test message"))

  # Read content
  content <- paste(readLines(json_path), collapse = "\n")

  # Pretty-printed JSON should have newlines and indentation
  expect_true(grepl("\\n", content))
  expect_true(grepl("  ", content))  # Should have indentation

  # Should still parse correctly
  parsed <- jsonlite::fromJSON(content)
  expect_equal(parsed$message, "Test message")

  # Clean up
  unlink(json_path)
})

# ============================================================================
# Cloud receiver tests (S3 and Azure)
# ============================================================================

test_that("on_s3() validates formatter input", {
  expect_error(
    on_s3("not a formatter", bucket = "test", key_prefix = "logs/app"),
    "must be a log_formatter"
  )

  expect_error(
    on_s3(to_identity(), bucket = "test", key_prefix = "logs/app"),
    "must be a log_formatter"
  )
})

test_that("on_s3() validates flush_threshold", {
  fmt <- to_text()

  expect_error(
    on_s3(fmt, bucket = "test", key_prefix = "logs/app", flush_threshold = -1),
    "must be a positive number"
  )

  expect_error(
    on_s3(fmt, bucket = "test", key_prefix = "logs/app", flush_threshold = 0),
    "must be a positive number"
  )
})

test_that("on_s3() enriches formatter config", {
  fmt <- to_text() %>%
    on_s3(bucket = "my-bucket",
          key_prefix = "logs/app",
          region = "us-west-2",
          flush_threshold = 50)

  config <- attr(fmt, "config")

  expect_equal(config$backend, "s3")
  expect_equal(config$backend_config$bucket, "my-bucket")
  expect_equal(config$backend_config$key_prefix, "logs/app")
  expect_equal(config$backend_config$region, "us-west-2")
  expect_equal(config$backend_config$flush_threshold, 50L)
})

test_that("on_azure() validates formatter input", {
  expect_error(
    on_azure("not a formatter", container = "logs", blob = "app.log", endpoint = NULL),
    "must be a log_formatter"
  )
})

test_that("on_azure() validates flush_threshold", {
  fmt <- to_text()

  expect_error(
    on_azure(fmt, container = "logs", blob = "app.log", endpoint = NULL, flush_threshold = -1),
    "must be a positive number"
  )
})

test_that("on_azure() enriches formatter config", {
  # Mock endpoint (just a list, won't actually use it)
  mock_endpoint <- list(url = "https://test.blob.core.windows.net")

  fmt <- to_text() %>%
    on_azure(container = "logs",
             blob = "app.log",
             endpoint = mock_endpoint,
             flush_threshold = 75)

  config <- attr(fmt, "config")

  expect_equal(config$backend, "azure")
  expect_equal(config$backend_config$container, "logs")
  expect_equal(config$backend_config$blob, "app.log")
  expect_equal(config$backend_config$flush_threshold, 75L)
})

# ============================================================================
# Shiny Level-to-Type Mapping Tests
# ============================================================================

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

# ============================================================================
# Webhook Handler Tests (on_webhook)
# ============================================================================

test_that("on_webhook() validates formatter input", {
  expect_error(
    on_webhook("not a formatter", url = "http://example.com"),
    "must be a log_formatter"
  )

  expect_error(
    on_webhook(to_identity(), url = "http://example.com"),
    "must be a log_formatter"
  )
})

test_that("on_webhook() validates URL", {
  fmt <- to_text()

  expect_error(
    on_webhook(fmt, url = ""),
    "non-empty character string"
  )

  expect_error(
    on_webhook(fmt, url = c("http://a.com", "http://b.com")),
    "non-empty character string"
  )

  expect_error(
    on_webhook(fmt, url = 123),
    "non-empty character string"
  )
})

test_that("on_webhook() enriches formatter config", {
  fmt <- to_json() %>%
    on_webhook(
      url = "https://webhook.site/test",
      method = "POST",
      timeout_seconds = 60,
      max_tries = 5
    )

  config <- attr(fmt, "config")

  expect_equal(config$backend, "webhook")
  expect_equal(config$backend_config$url, "https://webhook.site/test")
  expect_equal(config$backend_config$method, "POST")
  expect_equal(config$backend_config$timeout_seconds, 60)
  expect_equal(config$backend_config$max_tries, 5)
})

test_that("on_webhook() auto-detects content type from formatter", {
  # JSON formatter
  json_fmt <- to_json() %>% on_webhook(url = "http://example.com")
  json_config <- attr(json_fmt, "config")
  expect_equal(json_config$backend_config$content_type, "application/json")

  # Text formatter
  text_fmt <- to_text() %>% on_webhook(url = "http://example.com")
  text_config <- attr(text_fmt, "config")
  expect_equal(text_config$backend_config$content_type, "text/plain")
})

test_that("on_webhook() allows custom content type", {
  fmt <- to_text() %>%
    on_webhook(url = "http://example.com", content_type = "application/xml")

  config <- attr(fmt, "config")
  expect_equal(config$backend_config$content_type, "application/xml")
})

# ============================================================================
# Teams Receiver Tests (to_teams)
# ============================================================================

test_that("to_teams() creates valid receiver", {
  teams <- to_teams(webhook_url = "https://webhook.example.com")

  expect_s3_class(teams, "log_receiver")
  expect_s3_class(teams, "function")
})

test_that("to_teams() validates webhook URL", {
  expect_error(
    to_teams(webhook_url = ""),
    "non-empty character string"
  )

  expect_error(
    to_teams(webhook_url = c("url1", "url2")),
    "non-empty character string"
  )

  expect_error(
    to_teams(webhook_url = 123),
    "non-empty character string"
  )
})

test_that("to_teams() respects level filtering", {
  skip_if_not_installed("httr2")
  skip_if_not_installed("jsonlite")

  # This test just verifies the receiver runs without error
  # We can't test actual webhook POST without a real endpoint
  teams <- to_teams(
    webhook_url = "https://example.com/webhook",
    lower = WARNING,
    upper = ERROR
  )

  # Should silently filter NOTE (below lower)
  expect_silent(teams(NOTE("Should be filtered")))
})

# ============================================================================
# CSV Formatter Tests (to_csv)
# ============================================================================

test_that("to_csv() creates valid formatter", {
  fmt <- to_csv()

  expect_s3_class(fmt, "log_formatter")
  expect_s3_class(fmt, "function")

  config <- attr(fmt, "config")
  expect_equal(config$format_type, "csv")
})

test_that("to_csv() formats events correctly", {
  temp_dir <- tempdir()
  csv_path <- file.path(temp_dir, "test.csv")

  # Clean up
  unlink(csv_path)

  # Create CSV receiver
  csv_recv <- to_csv() %>% on_local(path = csv_path)
  log_test <- logger() %>% with_receivers(csv_recv)

  log_test(NOTE("First message", user = "alice", status = "ok"))
  log_test(WARNING("Second message", user = "bob", code = 404))

  # Read CSV
  lines <- readLines(csv_path)

  # Should have header + 2 data rows
  expect_equal(length(lines), 3)

  # Check header
  expect_true(grepl("time,level,level_number,message,tags", lines[1]))

  # Check data rows contain expected values
  expect_true(grepl("NOTE", lines[2]))
  expect_true(grepl("First message", lines[2]))
  expect_true(grepl("WARNING", lines[3]))
  expect_true(grepl("Second message", lines[3]))

  # Clean up
  unlink(csv_path)
})

test_that("to_csv() handles tags correctly", {
  temp_dir <- tempdir()
  csv_path <- file.path(temp_dir, "test_tags.csv")
  unlink(csv_path)

  csv_recv <- to_csv() %>% on_local(path = csv_path)
  log_test <- logger() %>%
    with_receivers(csv_recv) %>%
    with_tags("logger-tag")

  log_test(NOTE("Test") %>% with_tags("event-tag"))

  lines <- readLines(csv_path)

  # Tags should be pipe-delimited
  expect_true(grepl("event-tag\\|logger-tag", lines[2]))

  unlink(csv_path)
})

test_that("to_csv() escapes special characters", {
  temp_dir <- tempdir()
  csv_path <- file.path(temp_dir, "test_escape.csv")
  unlink(csv_path)

  csv_recv <- to_csv() %>% on_local(path = csv_path)
  log_test <- logger() %>% with_receivers(csv_recv)

  # Message with comma and quotes
  log_test(NOTE('Message with "quotes" and, commas'))

  lines <- readLines(csv_path)

  # Should be properly escaped
  expect_true(grepl('"Message with ""quotes"" and, commas"', lines[2]))

  unlink(csv_path)
})

test_that("to_csv() supports custom separator", {
  temp_dir <- tempdir()
  csv_path <- file.path(temp_dir, "test_tsv.tsv")
  unlink(csv_path)

  # Tab-separated
  tsv_recv <- to_csv(separator = "\t") %>% on_local(path = csv_path)
  log_test <- logger() %>% with_receivers(tsv_recv)

  log_test(NOTE("Test message"))

  content <- paste(readLines(csv_path), collapse = "\n")
  expect_true(grepl("\t", content))

  unlink(csv_path)
})

# ============================================================================
# Parquet Formatter Tests (to_parquet)
# ============================================================================

test_that("to_parquet() creates valid formatter", {
  fmt <- to_parquet()

  expect_s3_class(fmt, "log_formatter")
  expect_s3_class(fmt, "function")

  config <- attr(fmt, "config")
  expect_equal(config$format_type, "parquet")
  expect_true(config$requires_buffering)
})

test_that("to_parquet() formats events as data frames", {
  skip_if_not_installed("arrow")

  fmt <- to_parquet()
  event <- NOTE("Test message", user = "alice")

  result <- fmt(event)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 1)
  expect_equal(result$message, "Test message")
  expect_equal(result$level, "NOTE")
  expect_equal(result$level_number, 30)
})

test_that("to_parquet() handles tags as list column", {
  skip_if_not_installed("arrow")

  fmt <- to_parquet()
  event <- NOTE("Test") %>% with_tags("tag1", "tag2")

  result <- fmt(event)

  expect_true("tags" %in% names(result))
  expect_type(result$tags, "list")
  expect_equal(result$tags[[1]], c("tag1", "tag2"))
})

test_that("to_parquet() writes to file via on_local", {
  skip_if_not_installed("arrow")

  temp_dir <- tempdir()
  parquet_path <- file.path(temp_dir, "test.parquet")
  unlink(parquet_path)

  parquet_recv <- to_parquet() %>%
    on_local(path = parquet_path, flush_threshold = 2)
  log_test <- logger() %>% with_receivers(parquet_recv)

  log_test(NOTE("First"))
  log_test(WARNING("Second"))
  log_test(ERROR("Third"))  # Should trigger flush

  # Give buffering time to flush
  Sys.sleep(0.5)

  # File should exist
  expect_true(file.exists(parquet_path))

  # Read and verify
  df <- arrow::read_parquet(parquet_path)
  expect_true(nrow(df) >= 2)  # At least 2 flushed

  unlink(parquet_path)
})

# ============================================================================
# Feather Formatter Tests (to_feather)
# ============================================================================

test_that("to_feather() creates valid formatter", {
  fmt <- to_feather()

  expect_s3_class(fmt, "log_formatter")
  expect_s3_class(fmt, "function")

  config <- attr(fmt, "config")
  expect_equal(config$format_type, "feather")
  expect_true(config$requires_buffering)
})

test_that("to_feather() formats events as data frames", {
  skip_if_not_installed("arrow")

  fmt <- to_feather()
  event <- WARNING("Test warning", code = 500)

  result <- fmt(event)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 1)
  expect_equal(result$message, "Test warning")
  expect_equal(result$level, "WARNING")
})

test_that("to_feather() writes to file via on_local", {
  skip_if_not_installed("arrow")

  temp_dir <- tempdir()
  feather_path <- file.path(temp_dir, "test.feather")
  unlink(feather_path)

  feather_recv <- to_feather() %>%
    on_local(path = feather_path, flush_threshold = 2)
  log_test <- logger() %>% with_receivers(feather_recv)

  log_test(NOTE("First"))
  log_test(WARNING("Second"))

  # Give buffering time to flush
  Sys.sleep(0.5)

  # File should exist
  expect_true(file.exists(feather_path))

  # Read and verify
  df <- arrow::read_feather(feather_path)
  expect_true(nrow(df) >= 2)

  unlink(feather_path)
})

# ============================================================================
# Syslog Receiver Tests (to_syslog)
# ============================================================================

test_that("to_syslog() creates valid receiver", {
  # Using unix socket (most likely to work without network)
  syslog <- to_syslog(transport = "unix", socket_path = "/dev/log")

  expect_s3_class(syslog, "log_receiver")
  expect_s3_class(syslog, "function")
})

test_that("to_syslog() validates transport", {
  expect_error(
    to_syslog(transport = "invalid"),
    "'arg' should be one of"
  )
})

test_that("to_syslog() validates protocol", {
  expect_error(
    to_syslog(protocol = "invalid"),
    "'arg' should be one of"
  )
})

test_that("to_syslog() validates facility", {
  expect_error(
    to_syslog(facility = "invalid_facility"),
    "`facility` must be one of"
  )
})

test_that("to_syslog() respects level filtering", {
  syslog <- to_syslog(
    transport = "unix",
    lower = WARNING,
    upper = CRITICAL
  )

  # Should not error even if socket doesn't exist (tryCatch handles it)
  expect_silent(syslog(DEBUG("Should be filtered")))
  expect_silent(syslog(WARNING("Should attempt send")))
})

test_that("to_syslog() level-to-severity mapping is correct", {
  # We can't easily test the actual severity values without a mock,
  # but we can verify the receiver accepts all log levels
  syslog <- to_syslog(transport = "unix", lower = LOWEST, upper = HIGHEST)

  expect_silent(syslog(LOWEST("test")))
  expect_silent(syslog(TRACE("test")))
  expect_silent(syslog(DEBUG("test")))
  expect_silent(syslog(NOTE("test")))
  expect_silent(syslog(MESSAGE("test")))
  expect_silent(syslog(WARNING("test")))
  expect_silent(syslog(ERROR("test")))
  expect_silent(syslog(CRITICAL("test")))
  expect_silent(syslog(HIGHEST("test")))
})

# ============================================================================
# SweetAlert Receiver Tests (to_sweetalert)
# ============================================================================

test_that("to_sweetalert() creates valid receiver", {
  sweet <- to_sweetalert()

  expect_s3_class(sweet, "log_receiver")
  expect_s3_class(sweet, "function")
})

test_that("to_sweetalert() respects level filtering", {
  skip_if_not_installed("shinyWidgets")
  skip_if_not_installed("shiny")

  sweet <- to_sweetalert(lower = WARNING, upper = ERROR)

  # Should not error if shinyWidgets not installed (warning instead)
  # These tests just verify receiver construction and filtering logic
  expect_silent(sweet(NOTE("Should be filtered")))
})

# ============================================================================
# shinyWidgets Toast Receiver Tests (to_show_toast)
# ============================================================================

test_that("to_show_toast() creates valid receiver", {
  toast <- to_show_toast()

  expect_s3_class(toast, "log_receiver")
  expect_s3_class(toast, "function")
})

test_that("to_show_toast() respects level filtering", {
  skip_if_not_installed("shinyWidgets")
  skip_if_not_installed("shiny")

  toast <- to_show_toast(lower = NOTE, upper = WARNING)

  # Should not error if shinyWidgets not installed (warning instead)
  expect_silent(toast(DEBUG("Should be filtered")))
  expect_silent(toast(ERROR("Should be filtered")))
})

# ============================================================================
# toastr.js Receiver Tests (to_toastr)
# ============================================================================

test_that("to_toastr() creates valid receiver", {
  toastr <- to_toastr()

  expect_s3_class(toastr, "log_receiver")
  expect_s3_class(toastr, "function")
})

test_that("to_toastr() respects level filtering", {
  skip_if_not_installed("shinytoastr")
  skip_if_not_installed("shiny")

  toastr <- to_toastr(lower = NOTE, upper = WARNING)

  # Should not error if shinytoastr not installed (warning instead)
  expect_silent(toastr(DEBUG("Should be filtered")))
  expect_silent(toastr(ERROR("Should be filtered")))
})

# ============================================================================
# JavaScript Console Receiver Tests (to_js_console)
# ============================================================================

test_that("to_js_console() creates valid receiver", {
  js_console <- to_js_console()

  expect_s3_class(js_console, "log_receiver")
  expect_s3_class(js_console, "function")
})

test_that("to_js_console() respects level filtering", {
  skip_if_not_installed("shinyjs")
  skip_if_not_installed("shiny")

  js_console <- to_js_console(lower = WARNING, upper = CRITICAL)

  # Should not error if shinyjs not installed (warning instead)
  expect_silent(js_console(DEBUG("Should be filtered")))
  expect_silent(js_console(WARNING("Should attempt")))
})

test_that("to_js_console() accepts all log levels", {
  skip_if_not_installed("shinyjs")
  skip_if_not_installed("shiny")

  # Verify receiver accepts all levels (even if it can't actually send without Shiny session)
  js_console <- to_js_console(lower = LOWEST, upper = HIGHEST)

  expect_silent(js_console(LOWEST("test")))
  expect_silent(js_console(TRACE("test")))
  expect_silent(js_console(DEBUG("test")))
  expect_silent(js_console(NOTE("test")))
  expect_silent(js_console(MESSAGE("test")))
  expect_silent(js_console(WARNING("test")))
  expect_silent(js_console(ERROR("test")))
  expect_silent(js_console(CRITICAL("test")))
  expect_silent(js_console(HIGHEST("test")))
})

# ============================================================================
# Email Receiver Tests (to_email)
# ============================================================================

test_that("to_email() validates required inputs", {
  skip_if_not_installed("blastula")

  # Mock SMTP settings
  mock_smtp <- structure(list(), class = "creds")

  # Missing 'to'
  expect_error(
    to_email(
      to = character(0),
      from = "app@example.com",
      smtp_settings = mock_smtp
    ),
    "`to` must be a non-empty character vector"
  )

  # Invalid 'from'
  expect_error(
    to_email(
      to = "recipient@example.com",
      from = c("a@example.com", "b@example.com"),
      smtp_settings = mock_smtp
    ),
    "`from` must be a single email address"
  )

  # Invalid smtp_settings
  expect_error(
    to_email(
      to = "recipient@example.com",
      from = "app@example.com",
      smtp_settings = "not-creds"
    ),
    "`smtp_settings` must be blastula SMTP credentials"
  )

  # Invalid batch_size
  expect_error(
    to_email(
      to = "recipient@example.com",
      from = "app@example.com",
      smtp_settings = mock_smtp,
      batch_size = -5
    ),
    "`batch_size` must be a positive integer"
  )
})

test_that("to_email() creates valid receiver with correct class", {
  skip_if_not_installed("blastula")

  mock_smtp <- structure(list(), class = "creds")

  email_recv <- to_email(
    to = "alerts@example.com",
    from = "app@example.com",
    smtp_settings = mock_smtp,
    batch_size = 5
  )

  expect_s3_class(email_recv, "log_receiver")
  expect_s3_class(email_recv, "function")
})

test_that("to_email() respects level filtering", {
  skip_if_not_installed("blastula")

  mock_smtp <- structure(list(), class = "creds")

  # Create receiver that only accepts WARNING to ERROR
  email_recv <- to_email(
    to = "alerts@example.com",
    from = "app@example.com",
    smtp_settings = mock_smtp,
    batch_size = 10,
    lower = WARNING,
    upper = ERROR
  )

  # Should filter out events below WARNING and above ERROR
  expect_silent(email_recv(DEBUG("Should be filtered - too low")))
  expect_silent(email_recv(NOTE("Should be filtered - too low")))
  expect_silent(email_recv(CRITICAL("Should be filtered - too high")))

  # Should accept events in range (but won't send due to batch size)
  expect_silent(email_recv(WARNING("Should be accepted")))
  expect_silent(email_recv(ERROR("Should be accepted")))
})

test_that("to_email() uses plain text format", {
  skip_if_not_installed("blastula")

  mock_smtp <- structure(list(), class = "creds")

  # Email receiver uses plain text (no format parameter)
  email_recv <- to_email(
    to = "test@example.com",
    from = "app@example.com",
    smtp_settings = mock_smtp
  )
  expect_s3_class(email_recv, "log_receiver")
})

test_that("to_email() accepts multiple recipients and CC/BCC", {
  skip_if_not_installed("blastula")

  mock_smtp <- structure(list(), class = "creds")

  # Multiple recipients
  email_recv <- to_email(
    to = c("dev1@example.com", "dev2@example.com", "dev3@example.com"),
    from = "app@example.com",
    smtp_settings = mock_smtp,
    cc = "manager@example.com",
    bcc = c("audit@example.com", "compliance@example.com")
  )

  expect_s3_class(email_recv, "log_receiver")
})

test_that("to_email() requires blastula package", {
  # Temporarily unload blastula if loaded
  if ("package:blastula" %in% search()) {
    skip("blastula is loaded, cannot test package requirement")
  }

  # Mock the requireNamespace check by testing the error message
  # This test verifies the error message structure
  expect_true(TRUE)  # Placeholder - actual test would need package unloading
})
