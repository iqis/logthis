# Azure Cloud Backend Integration Tests
# These tests require Azurite to be running (./tests/cloud/start-services.sh)
# Tests are automatically skipped if Azurite is not available

test_that("Azure backend can write and flush events", {
  skip_if_not(cloud_test_config$check_azure(), "Azurite not running")
  skip_if_not_installed("AzureStor")

  endpoint <- cloud_test_config$get_azure_endpoint()
  blob_name <- cloud_test_config$generate_test_key("azure-test.log")

  # Create Azure receiver
  azure_recv <- to_json() %>%
    on_azure(
      container = cloud_test_config$azurite$container,
      blob = blob_name,
      endpoint = endpoint,
      flush_threshold = 3
    )

  # Convert to receiver
  azure_recv <- logthis:::.formatter_to_receiver(azure_recv)

  # Write events (should buffer)
  azure_recv(NOTE("Event 1"))
  azure_recv(NOTE("Event 2"))

  # Buffer should have 2 events
  expect_equal(attr(azure_recv, "get_buffer_size")(), 2)

  # Third event should trigger auto-flush
  azure_recv(NOTE("Event 3"))

  # Buffer should be empty after flush
  expect_equal(attr(azure_recv, "get_buffer_size")(), 0)

  # Verify blob was created in Azure
  container <- AzureStor::blob_container(
    endpoint,
    cloud_test_config$azurite$container
  )

  blobs <- AzureStor::list_blobs(container, info = "name")
  expect_true(blob_name %in% blobs$name)

  # Clean up
  cloud_test_config$cleanup_azure_blobs(strsplit(blob_name, "-")[[1]][1])
})

test_that("Azure backend uses append blobs", {
  skip_if_not(cloud_test_config$check_azure(), "Azurite not running")
  skip_if_not_installed("AzureStor")

  endpoint <- cloud_test_config$get_azure_endpoint()
  blob_name <- cloud_test_config$generate_test_key("azure-append.log")

  azure_recv <- to_text() %>%
    on_azure(
      container = cloud_test_config$azurite$container,
      blob = blob_name,
      endpoint = endpoint,
      flush_threshold = 2
    )

  azure_recv <- logthis:::.formatter_to_receiver(azure_recv)

  # First flush
  azure_recv(WARNING("First batch 1"))
  azure_recv(WARNING("First batch 2"))  # Auto-flush

  # Second flush - should append to same blob
  azure_recv(ERROR("Second batch 1"))
  azure_recv(ERROR("Second batch 2"))  # Auto-flush

  # Download blob content
  container <- AzureStor::blob_container(
    endpoint,
    cloud_test_config$azurite$container
  )

  tmp <- tempfile()
  AzureStor::download_blob(container, blob_name, tmp)
  content <- readLines(tmp)
  unlink(tmp)

  # Should contain all 4 events
  expect_true(any(grepl("First batch 1", content)))
  expect_true(any(grepl("First batch 2", content)))
  expect_true(any(grepl("Second batch 1", content)))
  expect_true(any(grepl("Second batch 2", content)))

  # Clean up
  cloud_test_config$cleanup_azure_blobs(strsplit(blob_name, "-")[[1]][1])
})

test_that("Azure backend manual flush works", {
  skip_if_not(cloud_test_config$check_azure(), "Azurite not running")
  skip_if_not_installed("AzureStor")

  endpoint <- cloud_test_config$get_azure_endpoint()
  blob_name <- cloud_test_config$generate_test_key("azure-manual.log")

  azure_recv <- to_json() %>%
    on_azure(
      container = cloud_test_config$azurite$container,
      blob = blob_name,
      endpoint = endpoint,
      flush_threshold = 100  # High threshold to prevent auto-flush
    )

  azure_recv <- logthis:::.formatter_to_receiver(azure_recv)

  # Write events without auto-flush
  azure_recv(ERROR("Manual flush test 1"))
  azure_recv(ERROR("Manual flush test 2"))

  # Buffer should have events
  expect_equal(attr(azure_recv, "get_buffer_size")(), 2)

  # Manual flush
  flush_fn <- attr(azure_recv, "flush")
  flush_fn()

  # Buffer should be empty
  expect_equal(attr(azure_recv, "get_buffer_size")(), 0)

  # Verify blob was created
  container <- AzureStor::blob_container(
    endpoint,
    cloud_test_config$azurite$container
  )

  blobs <- AzureStor::list_blobs(container, info = "name")
  expect_true(blob_name %in% blobs$name)

  # Clean up
  cloud_test_config$cleanup_azure_blobs(strsplit(blob_name, "-")[[1]][1])
})

test_that("Azure backend works with logger flush()", {
  skip_if_not(cloud_test_config$check_azure(), "Azurite not running")
  skip_if_not_installed("AzureStor")

  endpoint <- cloud_test_config$get_azure_endpoint()
  blob_name <- cloud_test_config$generate_test_key("azure-logger.log")

  # Create logger with Azure receiver
  log_test <- logger() %>%
    with_receivers(
      azure = to_json() %>%
        on_azure(
          container = cloud_test_config$azurite$container,
          blob = blob_name,
          endpoint = endpoint,
          flush_threshold = 100
        )
    )

  # Log some events
  log_test(NOTE("Event 1"))
  log_test(WARNING("Event 2"))

  # Check buffer status
  status <- buffer_status(log_test)
  expect_equal(status["azure"], 2)

  # Flush via logger
  flush(log_test)

  # Buffer should be empty
  status <- buffer_status(log_test)
  expect_equal(status["azure"], 0)

  # Verify blob
  container <- AzureStor::blob_container(
    endpoint,
    cloud_test_config$azurite$container
  )

  blobs <- AzureStor::list_blobs(container, info = "name")
  expect_true(blob_name %in% blobs$name)

  # Clean up
  cloud_test_config$cleanup_azure_blobs(strsplit(blob_name, "-")[[1]][1])
})

test_that("Azure backend respects level filtering", {
  skip_if_not(cloud_test_config$check_azure(), "Azurite not running")
  skip_if_not_installed("AzureStor")

  endpoint <- cloud_test_config$get_azure_endpoint()
  blob_name <- cloud_test_config$generate_test_key("azure-filter.log")

  azure_recv <- to_text() %>%
    on_azure(
      container = cloud_test_config$azurite$container,
      blob = blob_name,
      endpoint = endpoint,
      flush_threshold = 2
    ) %>%
    with_limits(lower = WARNING)

  azure_recv <- logthis:::.formatter_to_receiver(azure_recv)

  # Below limit - should be filtered
  azure_recv(NOTE("Should be filtered"))
  expect_equal(attr(azure_recv, "get_buffer_size")(), 0)

  # Above limit - should be buffered
  azure_recv(WARNING("Should pass"))
  azure_recv(ERROR("Should also pass"))  # Auto-flush

  # Download and verify content
  container <- AzureStor::blob_container(
    endpoint,
    cloud_test_config$azurite$container
  )

  tmp <- tempfile()
  AzureStor::download_blob(container, blob_name, tmp)
  content <- paste(readLines(tmp), collapse = "\n")
  unlink(tmp)

  expect_false(grepl("Should be filtered", content))
  expect_true(grepl("Should pass", content))
  expect_true(grepl("Should also pass", content))

  # Clean up
  cloud_test_config$cleanup_azure_blobs(strsplit(blob_name, "-")[[1]][1])
})

test_that("Azure backend handles blob initialization correctly", {
  skip_if_not(cloud_test_config$check_azure(), "Azurite not running")
  skip_if_not_installed("AzureStor")

  endpoint <- cloud_test_config$get_azure_endpoint()
  blob_name <- cloud_test_config$generate_test_key("azure-init.log")

  azure_recv <- to_text() %>%
    on_azure(
      container = cloud_test_config$azurite$container,
      blob = blob_name,
      endpoint = endpoint,
      flush_threshold = 1
    )

  azure_recv <- logthis:::.formatter_to_receiver(azure_recv)

  # First write should create blob
  azure_recv(NOTE("First write"))

  container <- AzureStor::blob_container(
    endpoint,
    cloud_test_config$azurite$container
  )

  blobs <- AzureStor::list_blobs(container, info = "name")
  expect_true(blob_name %in% blobs$name)

  # Second write should append to existing blob
  azure_recv(NOTE("Second write"))

  # Verify both writes are in blob
  tmp <- tempfile()
  AzureStor::download_blob(container, blob_name, tmp)
  content <- readLines(tmp)
  unlink(tmp)

  expect_true(any(grepl("First write", content)))
  expect_true(any(grepl("Second write", content)))

  # Clean up
  cloud_test_config$cleanup_azure_blobs(strsplit(blob_name, "-")[[1]][1])
})
