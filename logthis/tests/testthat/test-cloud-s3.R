# S3 Cloud Backend Integration Tests
# These tests require LocalStack to be running (./tests/cloud/start-services.sh)
# Tests are automatically skipped if LocalStack is not available

test_that("S3 backend can write and flush events", {
  skip_if_not(cloud_test_config$check_s3(), "LocalStack not running")
  skip_if_not_installed("aws.s3")

  # Setup environment
  cloud_test_config$setup_s3_env()

  # Create S3 receiver
  s3_recv <- to_json() %>%
    on_s3(
      bucket = cloud_test_config$localstack$bucket,
      key_prefix = cloud_test_config$generate_test_key("s3-test"),
      region = cloud_test_config$localstack$region,
      flush_threshold = 3
    )

  # Convert to receiver
  s3_recv <- logthis:::.formatter_to_receiver(s3_recv)

  # Write events (should buffer)
  s3_recv(NOTE("Event 1"))
  s3_recv(NOTE("Event 2"))

  # Buffer should have 2 events
  expect_equal(attr(s3_recv, "get_buffer_size")(), 2)

  # Third event should trigger auto-flush
  s3_recv(NOTE("Event 3"))

  # Buffer should be empty after flush
  expect_equal(attr(s3_recv, "get_buffer_size")(), 0)

  # Verify object was created in S3
  objects <- aws.s3::get_bucket(
    bucket = cloud_test_config$localstack$bucket,
    region = cloud_test_config$localstack$region,
    base_url = cloud_test_config$localstack$endpoint
  )

  expect_true(length(objects) > 0)

  # Clean up
  cloud_test_config$cleanup_s3_objects("s3-test")
})

test_that("S3 backend creates time-partitioned keys", {
  skip_if_not(cloud_test_config$check_s3(), "LocalStack not running")
  skip_if_not_installed("aws.s3")

  cloud_test_config$setup_s3_env()

  key_prefix <- cloud_test_config$generate_test_key("s3-partition")

  s3_recv <- to_text() %>%
    on_s3(
      bucket = cloud_test_config$localstack$bucket,
      key_prefix = key_prefix,
      region = cloud_test_config$localstack$region,
      flush_threshold = 2
    )

  s3_recv <- logthis:::.formatter_to_receiver(s3_recv)

  # Write and flush
  s3_recv(WARNING("Test 1"))
  s3_recv(WARNING("Test 2"))  # Auto-flush

  # Check that key contains timestamp
  objects <- aws.s3::get_bucket(
    bucket = cloud_test_config$localstack$bucket,
    prefix = key_prefix,
    region = cloud_test_config$localstack$region,
    base_url = cloud_test_config$localstack$endpoint
  )

  expect_true(length(objects) > 0)

  # Key should match pattern: prefix-YYYYMMDD-HHMMSS.log
  key <- objects[[1]]$Key
  expect_true(grepl(paste0(key_prefix, "-\\d{8}-\\d{6}\\.log"), key))

  # Clean up
  cloud_test_config$cleanup_s3_objects(key_prefix)
})

test_that("S3 backend manual flush works", {
  skip_if_not(cloud_test_config$check_s3(), "LocalStack not running")
  skip_if_not_installed("aws.s3")

  cloud_test_config$setup_s3_env()

  key_prefix <- cloud_test_config$generate_test_key("s3-manual")

  s3_recv <- to_json() %>%
    on_s3(
      bucket = cloud_test_config$localstack$bucket,
      key_prefix = key_prefix,
      region = cloud_test_config$localstack$region,
      flush_threshold = 100  # High threshold to prevent auto-flush
    )

  s3_recv <- logthis:::.formatter_to_receiver(s3_recv)

  # Write events without auto-flush
  s3_recv(ERROR("Manual flush test 1"))
  s3_recv(ERROR("Manual flush test 2"))

  # Buffer should have events
  expect_equal(attr(s3_recv, "get_buffer_size")(), 2)

  # Manual flush
  flush_fn <- attr(s3_recv, "flush")
  flush_fn()

  # Buffer should be empty
  expect_equal(attr(s3_recv, "get_buffer_size")(), 0)

  # Verify objects were created
  objects <- aws.s3::get_bucket(
    bucket = cloud_test_config$localstack$bucket,
    prefix = key_prefix,
    region = cloud_test_config$localstack$region,
    base_url = cloud_test_config$localstack$endpoint
  )

  expect_true(length(objects) > 0)

  # Clean up
  cloud_test_config$cleanup_s3_objects(key_prefix)
})

test_that("S3 backend works with logger flush()", {
  skip_if_not(cloud_test_config$check_s3(), "LocalStack not running")
  skip_if_not_installed("aws.s3")

  cloud_test_config$setup_s3_env()

  key_prefix <- cloud_test_config$generate_test_key("s3-logger-flush")

  # Create logger with S3 receiver
  log_test <- logger() %>%
    with_receivers(
      s3 = to_json() %>%
        on_s3(
          bucket = cloud_test_config$localstack$bucket,
          key_prefix = key_prefix,
          region = cloud_test_config$localstack$region,
          flush_threshold = 100
        )
    )

  # Log some events
  log_test(NOTE("Event 1"))
  log_test(WARNING("Event 2"))

  # Check buffer status
  status <- buffer_status(log_test)
  expect_equal(status["s3"], 2)

  # Flush via logger
  flush(log_test)

  # Buffer should be empty
  status <- buffer_status(log_test)
  expect_equal(status["s3"], 0)

  # Verify objects
  objects <- aws.s3::get_bucket(
    bucket = cloud_test_config$localstack$bucket,
    prefix = key_prefix,
    region = cloud_test_config$localstack$region,
    base_url = cloud_test_config$localstack$endpoint
  )

  expect_true(length(objects) > 0)

  # Clean up
  cloud_test_config$cleanup_s3_objects(key_prefix)
})

test_that("S3 backend respects level filtering", {
  skip_if_not(cloud_test_config$check_s3(), "LocalStack not running")
  skip_if_not_installed("aws.s3")

  cloud_test_config$setup_s3_env()

  key_prefix <- cloud_test_config$generate_test_key("s3-filter")

  s3_recv <- to_text() %>%
    on_s3(
      bucket = cloud_test_config$localstack$bucket,
      key_prefix = key_prefix,
      region = cloud_test_config$localstack$region,
      flush_threshold = 2
    ) %>%
    with_limits(lower = WARNING)

  s3_recv <- logthis:::.formatter_to_receiver(s3_recv)

  # Below limit - should be filtered
  s3_recv(NOTE("Should be filtered"))
  expect_equal(attr(s3_recv, "get_buffer_size")(), 0)

  # Above limit - should be buffered
  s3_recv(WARNING("Should pass"))
  s3_recv(ERROR("Should also pass"))  # Auto-flush

  # Verify objects created
  objects <- aws.s3::get_bucket(
    bucket = cloud_test_config$localstack$bucket,
    prefix = key_prefix,
    region = cloud_test_config$localstack$region,
    base_url = cloud_test_config$localstack$endpoint
  )

  expect_true(length(objects) > 0)

  # Verify content contains only WARNING and ERROR
  content <- rawToChar(aws.s3::get_object(
    object = objects[[1]]$Key,
    bucket = cloud_test_config$localstack$bucket,
    region = cloud_test_config$localstack$region,
    base_url = cloud_test_config$localstack$endpoint
  ))

  expect_false(grepl("Should be filtered", content))
  expect_true(grepl("Should pass", content))
  expect_true(grepl("Should also pass", content))

  # Clean up
  cloud_test_config$cleanup_s3_objects(key_prefix)
})
