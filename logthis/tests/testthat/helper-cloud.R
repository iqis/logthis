# Cloud Testing Configuration
# This file is automatically loaded by testthat before running tests
# DO NOT export these utilities - they are test-only infrastructure

cloud_test_config <- list(
  # LocalStack S3 configuration
  localstack = list(
    endpoint = "http://localhost:4566",
    bucket = "logthis-test",
    region = "us-east-1",
    credentials = list(
      access_key_id = "test",
      secret_access_key = "test"
    )
  ),

  # Azurite Azure Blob Storage configuration
  azurite = list(
    endpoint_url = "http://127.0.0.1:10000/devstoreaccount1",
    account_name = "devstoreaccount1",
    # Default Azurite well-known key
    account_key = "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==",
    container = "logthis-test"
  ),

  # Check if LocalStack is running
  check_s3 = function() {
    if (!requireNamespace("httr", quietly = TRUE)) {
      return(FALSE)
    }
    tryCatch({
      response <- httr::GET(
        "http://localhost:4566/_localstack/health",
        httr::timeout(2)
      )
      httr::status_code(response) == 200
    }, error = function(e) {
      FALSE
    })
  },

  # Check if Azurite is running
  check_azure = function() {
    if (!requireNamespace("httr", quietly = TRUE)) {
      return(FALSE)
    }
    tryCatch({
      response <- httr::GET(
        "http://127.0.0.1:10000/devstoreaccount1?comp=list",
        httr::timeout(2)
      )
      # Azurite returns 200 even without auth for list operations
      httr::status_code(response) %in% c(200, 401, 403)
    }, error = function(e) {
      FALSE
    })
  },

  # Configure environment for aws.s3 to use LocalStack
  setup_s3_env = function() {
    Sys.setenv(
      "AWS_ACCESS_KEY_ID" = cloud_test_config$localstack$credentials$access_key_id,
      "AWS_SECRET_ACCESS_KEY" = cloud_test_config$localstack$credentials$secret_access_key,
      "AWS_DEFAULT_REGION" = cloud_test_config$localstack$region,
      "AWS_S3_ENDPOINT" = cloud_test_config$localstack$endpoint
    )
  },

  # Get configured Azure endpoint for AzureStor package
  get_azure_endpoint = function() {
    if (!requireNamespace("AzureStor", quietly = TRUE)) {
      skip("AzureStor not available")
    }

    # Create storage endpoint for Azurite
    AzureStor::storage_endpoint(
      endpoint = cloud_test_config$azurite$endpoint_url,
      key = cloud_test_config$azurite$account_key
    )
  },

  # Generate unique test key/blob name to avoid conflicts
  generate_test_key = function(prefix = "test") {
    paste0(prefix, "-", format(Sys.time(), "%Y%m%d-%H%M%S-"),
           sample(1000:9999, 1))
  },

  # Clean up S3 test objects
  cleanup_s3_objects = function(prefix = "test") {
    if (!cloud_test_config$check_s3()) return(invisible(NULL))
    if (!requireNamespace("aws.s3", quietly = TRUE)) return(invisible(NULL))

    tryCatch({
      cloud_test_config$setup_s3_env()

      objects <- aws.s3::get_bucket(
        bucket = cloud_test_config$localstack$bucket,
        prefix = prefix,
        region = cloud_test_config$localstack$region,
        base_url = cloud_test_config$localstack$endpoint
      )

      if (length(objects) > 0) {
        for (obj in objects) {
          aws.s3::delete_object(
            object = obj$Key,
            bucket = cloud_test_config$localstack$bucket,
            region = cloud_test_config$localstack$region,
            base_url = cloud_test_config$localstack$endpoint
          )
        }
      }
    }, error = function(e) {
      warning("Failed to clean up S3 objects: ", conditionMessage(e))
    })

    invisible(NULL)
  },

  # Clean up Azure test blobs
  cleanup_azure_blobs = function(prefix = "test") {
    if (!cloud_test_config$check_azure()) return(invisible(NULL))
    if (!requireNamespace("AzureStor", quietly = TRUE)) return(invisible(NULL))

    tryCatch({
      endpoint <- cloud_test_config$get_azure_endpoint()
      container <- AzureStor::blob_container(
        endpoint,
        cloud_test_config$azurite$container
      )

      blobs <- AzureStor::list_blobs(container, info = "name")

      if (nrow(blobs) > 0) {
        test_blobs <- blobs$name[grepl(paste0("^", prefix), blobs$name)]

        for (blob_name in test_blobs) {
          AzureStor::delete_blob(container, blob_name)
        }
      }
    }, error = function(e) {
      warning("Failed to clean up Azure blobs: ", conditionMessage(e))
    })

    invisible(NULL)
  }
)
