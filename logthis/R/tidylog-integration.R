#' Enable Tidylog with Logthis Backend
#'
#' Configures tidylog to send transformation messages to a logthis logger
#' instead of the console. Perfect for creating audit trails of dplyr/tidyr
#' pipeline transformations in GxP-compliant workflows.
#'
#' @param logger A logthis logger object (optional, creates default if NULL)
#' @param level Event level for tidylog messages (default: NOTE)
#' @param user_id Optional user identifier for audit trail
#' @param pipeline_id Optional pipeline identifier for tracking
#' @param ... Additional tags to add to all tidylog events
#'
#' @return Invisibly returns the logger being used
#'
#' @export
#' @family tidylog
#'
#' @examples
#' \dontrun{
#' library(dplyr)
#' library(tidylog)
#' library(logthis)
#'
#' # Scope-based logger configuration
#' run_data_pipeline <- function() {
#'   # Configure log_this for this scope and enable tidylog
#'   log_this <- logger() %>%
#'     with_receivers(to_json() %>% on_local("pipeline.jsonl"))
#'
#'   log_tidyverse(
#'     logger = log_this,
#'     user_id = "analyst",
#'     pipeline_id = "data_cleaning_v1"
#'   )
#'
#'   # Now dplyr operations are logged
#'   mtcars %>%
#'     filter(mpg > 20) %>%
#'     select(mpg, cyl, hp)
#'   # Logs: "filter: removed 18 rows (56%), 14 rows remaining"
#'   # Logs: "select: dropped 8 variables (am, carb, disp, drat, gear, qsec, vs, wt)"
#' }
#' }
log_tidyverse <- function(logger = NULL,
                          level = NOTE,
                          user_id = Sys.getenv("USER"),
                          pipeline_id = NULL,
                          ...) {
  if (!requireNamespace("tidylog", quietly = TRUE)) {
    stop("Package 'tidylog' is required. Install with: install.packages('tidylog')")
  }

  # Create default logger if not provided
  if (is.null(logger)) {
    logger <- logger() %>%
      with_receivers(to_console()) %>%
      with_tags(source = "tidylog", ...)
  } else {
    logger <- logger %>% with_tags(source = "tidylog", ...)
  }

  # Create custom tidylog output function
  tidylog_to_logthis <- function(message) {
    # Parse tidylog message
    parts <- parse_tidylog_message(message)

    # Create log event with transformation details
    event <- level(
      message,
      user_id = user_id,
      pipeline_id = pipeline_id,
      operation = parts$operation,
      details = parts$details,
      transformation_type = "tidyverse"
    )

    logger(event)
  }

  # Set tidylog to use our custom function
  options(tidylog.display = list(message = tidylog_to_logthis))

  invisible(logger)
}


#' Parse Tidylog Message
#'
#' Internal function to parse tidylog messages and extract operation details.
#'
#' @param message Character string from tidylog
#' @return List with operation and details
#' @keywords internal
#' @noRd
parse_tidylog_message <- function(message) {
  # Extract operation type (first word before colon)
  operation <- sub("^([^:]+):.*", "\\1", message)

  # Extract details (everything after colon)
  details <- sub("^[^:]+:\\s*", "", message)

  list(
    operation = trimws(operation),
    details = trimws(details)
  )
}


#' Log Data Pipeline with Comprehensive Audit Trail
#'
#' Wraps a data transformation pipeline with comprehensive audit logging,
#' including input/output hashing for GxP compliance.
#'
#' @param data Input data frame
#' @param pipeline_expr Expression containing the pipeline (use rlang::quo)
#' @param logger A logthis logger object
#' @param pipeline_name Name of the pipeline for audit trail
#' @param user_id User identifier
#' @param study_id Optional study identifier (for clinical trials)
#' @param validate_output Optional validation function for output
#'
#' @return Transformed data frame
#'
#' @export
#' @family tidylog
#'
#' @examples
#' \dontrun{
#' library(dplyr)
#' library(tidylog)
#' library(logthis)
#'
#' # Scope-based GxP pipeline
#' analyze_fuel_efficiency <- function(mtcars) {
#'   # Configure log_this for this scope
#'   log_this <- create_gxp_logger(
#'     study_id = "STUDY-001",
#'     system_name = "Data Pipeline",
#'     audit_path = "pipeline_audit.jsonl"
#'   )
#'
#'   result <- with_pipeline_audit(
#'     data = mtcars,
#'     pipeline_expr = . %>%
#'       filter(mpg > 20) %>%
#'       mutate(efficiency = mpg / hp) %>%
#'       select(mpg, hp, efficiency),
#'     logger = log_this,
#'     pipeline_name = "fuel_efficiency_analysis",
#'     user_id = "data_analyst"
#'   )
#' }
#' }
with_pipeline_audit <- function(data,
                                 pipeline_expr,
                                 logger,
                                 pipeline_name,
                                 user_id = Sys.getenv("USER"),
                                 study_id = NULL,
                                 validate_output = NULL) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required for data integrity hashing")
  }

  # Enable tidylog if available (optional)
  tidylog_available <- requireNamespace("tidylog", quietly = TRUE)
  if (tidylog_available) {
    # Enable tidylog with logthis
    log_tidyverse(
      logger = logger,
      user_id = user_id,
      pipeline_id = pipeline_name
    )
  }

  # Calculate input hash
  input_hash <- digest::digest(data)

  # Log pipeline start
  logger(
    NOTE(
      paste("Pipeline started:", pipeline_name),
      user_id = user_id,
      study_id = study_id,
      pipeline_name = pipeline_name,
      input_rows = nrow(data),
      input_cols = ncol(data),
      input_hash = input_hash,
      timestamp = Sys.time()
    )
  )

  # Execute pipeline with error handling
  result <- tryCatch({
    # Evaluate pipeline expression
    if (inherits(pipeline_expr, "formula")) {
      # Handle formula syntax: ~ . %>% filter(...)
      pipeline_func <- rlang::as_function(pipeline_expr)
      pipeline_func(data)
    } else {
      # Handle direct expression
      eval(substitute(data %>% pipeline_expr))
    }
  }, error = function(e) {
    logger(
      ERROR(
        paste("Pipeline failed:", pipeline_name),
        user_id = user_id,
        study_id = study_id,
        pipeline_name = pipeline_name,
        error_message = conditionMessage(e),
        timestamp = Sys.time()
      )
    )
    stop(e)
  })

  # Calculate output hash
  output_hash <- digest::digest(result)

  # Validate output if function provided
  if (!is.null(validate_output)) {
    validation_result <- tryCatch({
      validate_output(result)
    }, error = function(e) {
      logger(
        ERROR(
          paste("Pipeline validation failed:", pipeline_name),
          user_id = user_id,
          study_id = study_id,
          pipeline_name = pipeline_name,
          validation_error = conditionMessage(e)
        )
      )
      stop(e)
    })

    if (!isTRUE(validation_result)) {
      logger(
        WARNING(
          paste("Pipeline validation warning:", pipeline_name),
          user_id = user_id,
          study_id = study_id,
          pipeline_name = pipeline_name,
          validation_message = as.character(validation_result)
        )
      )
    }
  }

  # Log pipeline completion
  logger(
    NOTE(
      paste("Pipeline completed:", pipeline_name),
      user_id = user_id,
      study_id = study_id,
      pipeline_name = pipeline_name,
      input_hash = input_hash,
      output_hash = output_hash,
      output_rows = nrow(result),
      output_cols = ncol(result),
      rows_changed = nrow(result) - nrow(data),
      cols_changed = ncol(result) - ncol(data),
      timestamp = Sys.time()
    )
  )

  result
}


#' Manually Log a Data Transformation
#'
#' Logs a data transformation step without using tidylog. Useful for
#' custom transformations or non-dplyr operations.
#'
#' @param data_before Data before transformation
#' @param data_after Data after transformation
#' @param operation_name Name of the operation
#' @param logger A logthis logger object
#' @param user_id User identifier
#' @param ... Additional fields to include in log event
#'
#' @return Invisibly returns data_after
#'
#' @export
#' @family tidylog
#'
#' @examples
#' \dontrun{
#' # Scope-based custom transformation tracking
#' custom_filter_high_mpg <- function(mtcars) {
#'   # Configure log_this for this scope
#'   log_this <- create_gxp_logger(
#'     study_id = "STUDY-001",
#'     system_name = "Custom Transform",
#'     audit_path = "transform.jsonl"
#'   )
#'
#'   before <- mtcars
#'   after <- mtcars[mtcars$mpg > 20, ]
#'
#'   track_transformation(
#'     data_before = before,
#'     data_after = after,
#'     operation_name = "custom_filter_high_mpg",
#'     logger = log_this,
#'     user_id = "analyst",
#'     criteria = "mpg > 20"
#'   )
#' }
#' }
track_transformation <- function(data_before,
                                  data_after,
                                  operation_name,
                                  logger,
                                  user_id = Sys.getenv("USER"),
                                  ...) {
  if (!requireNamespace("digest", quietly = TRUE)) {
    stop("Package 'digest' is required for data integrity hashing")
  }

  rows_before <- nrow(data_before)
  rows_after <- nrow(data_after)
  cols_before <- ncol(data_before)
  cols_after <- ncol(data_after)

  logger(
    NOTE(
      paste("Transformation:", operation_name),
      user_id = user_id,
      operation = operation_name,
      rows_before = rows_before,
      rows_after = rows_after,
      rows_removed = rows_before - rows_after,
      cols_before = cols_before,
      cols_after = cols_after,
      cols_changed = cols_after - cols_before,
      input_hash = digest::digest(data_before),
      output_hash = digest::digest(data_after),
      ...
    )
  )

  invisible(data_after)
}



#' Disable Tidylog Integration
#'
#' Resets tidylog to use default console output instead of logthis.
#'
#' @export
#' @family tidylog
#'
#' @examples
#' \dontrun{
#' # Scope-based usage
#' run_analysis <- function() {
#'   log_this <- logger() %>% with_receivers(to_console())
#'
#'   # Enable tidylog in this scope
#'   log_tidyverse(logger = log_this)
#'
#'   # ... do some work ...
#'
#'   # Disable when done
#'   disable_tidylog()
#' }
#' }
disable_tidylog <- function() {
  options(tidylog.display = NULL)
  invisible(NULL)
}


#' Get Pipeline Summary from Audit Trail
#'
#' Extracts and summarizes pipeline execution from audit trail logs.
#'
#' @param audit_file Path to audit trail JSON file
#' @param pipeline_name Optional pipeline name to filter
#'
#' @return Data frame with pipeline summary
#'
#' @export
#' @family tidylog
#'
#' @examples
#' \dontrun{
#' # Get summary of all pipelines
#' summary <- get_pipeline_summary("pipeline_audit.jsonl")
#'
#' # Get summary of specific pipeline
#' summary <- get_pipeline_summary(
#'   "pipeline_audit.jsonl",
#'   pipeline_name = "sdtm_derivation"
#' )
#'
#' print(summary)
#' }
get_pipeline_summary <- function(audit_file, pipeline_name = NULL) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("Package 'jsonlite' is required")
  }

  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("Package 'dplyr' is required")
  }

  # Read audit trail
  audit_data <- jsonlite::stream_in(file(audit_file), verbose = FALSE)

  # Filter for pipeline events
  pipeline_events <- audit_data %>%
    dplyr::filter(grepl("pipeline|transformation", message, ignore.case = TRUE))

  # Filter by pipeline name if provided
  if (!is.null(pipeline_name)) {
    pipeline_events <- pipeline_events %>%
      dplyr::filter(pipeline_name == !!pipeline_name)
  }

  # Summarize
  summary <- pipeline_events %>%
    dplyr::group_by(pipeline_name, user_id) %>%
    dplyr::summarize(
      n_operations = dplyr::n(),
      first_run = min(time),
      last_run = max(time),
      operations = paste(unique(operation), collapse = ", "),
      .groups = "drop"
    )

  summary
}
