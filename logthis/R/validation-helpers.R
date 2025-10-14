#' Validate Data with Audit Trail
#'
#' Validates data using the validate package and logs all validation results
#' with complete audit trail for GxP compliance.
#'
#' @param data A data frame to validate
#' @param rules A validator object from the validate package
#' @param logger A logthis logger object
#' @param user_id User identifier for audit trail (defaults to system user)
#' @param reason Reason for validation (e.g., "Protocol amendment", "Data lock")
#' @param study_id Optional study identifier
#' @param dataset_name Optional dataset name for audit trail
#'
#' @return Invisibly returns the validation result object from validate::confront()
#'
#' @export
#' @family validation
#'
#' @examples
#' \dontrun{
#' library(validate)
#' library(logthis)
#'
#' # Scope-based logger configuration
#' validate_clinical_data <- function(clinical_data) {
#'   # Configure log_this for this scope
#'   log_this <- logger() %>%
#'     with_tags(system = "validation", regulation = "21CFR11") %>%
#'     with_receivers(
#'       to_json() %>% on_local("validation.jsonl")
#'     )
#'
#'   # Define validation rules
#'   rules <- validator(
#'     age_valid = age >= 18 & age <= 100,
#'     weight_positive = weight > 0
#'   )
#'
#'   # Validate with audit trail
#'   result <- validate_with_audit(
#'     data = clinical_data,
#'     rules = rules,
#'     logger = log_this,
#'     user_id = "jdoe",
#'     reason = "Data validation for database lock"
#'   )
#' }
#' }
validate_with_audit <- function(data,
                                 rules,
                                 logger,
                                 user_id = Sys.getenv("USER"),
                                 reason = NULL,
                                 study_id = NULL,
                                 dataset_name = NULL) {
  if (!requireNamespace("validate", quietly = TRUE)) {
    stop("Package 'validate' is required for validate_with_audit(). Install with: install.packages('validate')")
  }

  # Calculate dataset hash for integrity
  dataset_hash <- digest::digest(data)

  # Log validation start
  logger(
    NOTE(
      "Validation started",
      user_id = user_id,
      reason = reason,
      study_id = study_id,
      dataset_name = dataset_name,
      n_records = nrow(data),
      n_rules = length(rules),
      dataset_hash = dataset_hash
    )
  )

  # Run validation
  result <- validate::confront(data, rules)

  # Extract results
  violations <- summary(result)

  # Log each rule result
  for (i in seq_len(nrow(violations))) {
    rule <- violations[i, ]

    log_event <- if (rule$fails > 0) {
      WARNING(
        paste("Validation rule failed:", rule$name),
        user_id = user_id,
        study_id = study_id,
        dataset_name = dataset_name,
        rule_name = rule$name,
        fails = rule$fails,
        passes = rule$passes,
        na_count = rule$nNA,
        expression = as.character(rule$expression)
      )
    } else {
      NOTE(
        paste("Validation rule passed:", rule$name),
        user_id = user_id,
        study_id = study_id,
        dataset_name = dataset_name,
        rule_name = rule$name,
        passes = rule$passes
      )
    }

    logger(log_event)
  }

  # Log completion
  total_fails <- sum(violations$fails)
  logger(
    if (total_fails > 0) {
      ERROR(
        "Validation completed with failures",
        user_id = user_id,
        study_id = study_id,
        dataset_name = dataset_name,
        total_fails = total_fails,
        total_passes = sum(violations$passes),
        dataset_hash = dataset_hash
      )
    } else {
      NOTE(
        "Validation completed successfully",
        user_id = user_id,
        study_id = study_id,
        dataset_name = dataset_name,
        total_passes = sum(violations$passes),
        dataset_hash = dataset_hash
      )
    }
  )

  invisible(result)
}


#' Validate Data with Pointblank Agent and Audit Trail
#'
#' Creates a pointblank validation agent with comprehensive audit logging.
#'
#' @param tbl A data frame or database table to validate
#' @param logger A logthis logger object
#' @param user_id User identifier for audit trail (defaults to system user)
#' @param study_id Optional study identifier
#' @param dataset_name Optional dataset name
#' @param ... Additional arguments passed to pointblank::create_agent()
#'
#' @return A pointblank agent object that has been interrogated
#'
#' @export
#' @family validation
#'
#' @examples
#' \dontrun{
#' library(pointblank)
#' library(logthis)
#'
#' validate_with_pointblank <- function(clinical_data) {
#'   # Configure log_this for this scope
#'   log_this <- logger() %>%
#'     with_tags(study = "STUDY-001") %>%
#'     with_receivers(to_json() %>% on_local("validation.jsonl"))
#'
#'   agent <- create_agent_with_audit(
#'     tbl = clinical_data,
#'     logger = log_this,
#'     user_id = "data_manager",
#'     study_id = "STUDY-001"
#'   ) %>%
#'     col_vals_not_null(vars(patient_id)) %>%
#'     col_vals_between(vars(age), 18, 100) %>%
#'     interrogate_with_audit(logger = log_this, user_id = "data_manager")
#' }
#' }
create_agent_with_audit <- function(tbl,
                                     logger,
                                     user_id = Sys.getenv("USER"),
                                     study_id = NULL,
                                     dataset_name = NULL,
                                     ...) {
  if (!requireNamespace("pointblank", quietly = TRUE)) {
    stop("Package 'pointblank' is required. Install with: install.packages('pointblank')")
  }

  # Log agent creation
  logger(
    NOTE(
      "Pointblank validation agent created",
      user_id = user_id,
      study_id = study_id,
      dataset_name = dataset_name %||% deparse(substitute(tbl)),
      n_rows = nrow(tbl),
      n_cols = ncol(tbl)
    )
  )

  # Create and return agent
  pointblank::create_agent(tbl = tbl, ...)
}


#' Interrogate Pointblank Agent with Audit Trail
#'
#' Interrogates a pointblank agent and logs all validation results.
#'
#' @param agent A pointblank agent object
#' @param logger A logthis logger object
#' @param user_id User identifier for audit trail
#' @param study_id Optional study identifier
#' @param dataset_name Optional dataset name
#' @param ... Additional arguments passed to pointblank::interrogate()
#'
#' @return The interrogated agent object
#'
#' @export
#' @family validation
interrogate_with_audit <- function(agent,
                                    logger,
                                    user_id = Sys.getenv("USER"),
                                    study_id = NULL,
#'                                    dataset_name = NULL,
                                    ...) {
  if (!requireNamespace("pointblank", quietly = TRUE)) {
    stop("Package 'pointblank' is required")
  }

  # Interrogate agent
  agent <- pointblank::interrogate(agent, ...)

  # Extract validation results
  report <- pointblank::get_agent_report(agent, display_mode = "none")

  # Log each validation step
  for (i in seq_len(nrow(report))) {
    step <- report[i, ]

    log_event <- if (step$f_failed > 0) {
      WARNING(
        paste("Pointblank validation failed:", step$assertion_type),
        user_id = user_id,
        study_id = study_id,
        dataset_name = dataset_name,
        step_id = i,
        column = step$column,
        assertion = step$assertion_type,
        n_passed = step$n_passed,
        n_failed = step$n_failed,
        f_failed = step$f_failed
      )
    } else {
      NOTE(
        paste("Pointblank validation passed:", step$assertion_type),
        user_id = user_id,
        study_id = study_id,
        dataset_name = dataset_name,
        step_id = i,
        column = step$column,
        n_passed = step$n_passed
      )
    }

    logger(log_event)
  }

  # Log final status
  if (any(report$f_failed > 0.10)) {
    logger(
      CRITICAL(
        "Validation failed - critical threshold exceeded",
        user_id = user_id,
        study_id = study_id,
        dataset_name = dataset_name,
        failed_steps = sum(report$f_failed > 0)
      )
    )
  } else if (any(report$f_failed > 0)) {
    logger(
      WARNING(
        "Validation completed with warnings",
        user_id = user_id,
        study_id = study_id,
        dataset_name = dataset_name,
        total_steps = nrow(report),
        failed_steps = sum(report$f_failed > 0),
        warning_steps = sum(report$f_failed > 0.05 & report$f_failed <= 0.10)
      )
    )
  } else {
    logger(
      NOTE(
        "Pointblank validation completed successfully",
        user_id = user_id,
        study_id = study_id,
        dataset_name = dataset_name,
        total_steps = nrow(report)
      )
    )
  }

  agent
}


#' Compare Datasets with Audit Trail
#'
#' Compares two datasets using arsenal::comparedf and logs all differences
#' for GxP reconciliation audit trails.
#'
#' @param old_data Original dataset
#' @param new_data Updated dataset
#' @param logger A logthis logger object
#' @param user_id User identifier for audit trail
#' @param reason Reason for comparison (e.g., "Monthly reconciliation")
#' @param study_id Optional study identifier
#' @param ... Additional arguments passed to arsenal::comparedf()
#'
#' @return Invisibly returns the comparedf object
#'
#' @export
#' @family validation
#'
#' @examples
#' \dontrun{
#' library(arsenal)
#' library(logthis)
#'
#' monthly_reconciliation <- function(baseline_data, updated_data) {
#'   # Configure log_this for this scope
#'   log_this <- logger() %>%
#'     with_tags(activity = "reconciliation") %>%
#'     with_receivers(to_json() %>% on_local("reconciliation.jsonl"))
#'
#'   compare_datasets_with_audit(
#'     old_data = baseline_data,
#'     new_data = updated_data,
#'     logger = log_this,
#'     user_id = "data_manager",
#'     reason = "Monthly data lock reconciliation"
#'   )
#' }
#' }
compare_datasets_with_audit <- function(old_data,
                                         new_data,
                                         logger,
                                         user_id = Sys.getenv("USER"),
                                         reason = NULL,
                                         study_id = NULL,
                                         ...) {
  if (!requireNamespace("arsenal", quietly = TRUE)) {
    stop("Package 'arsenal' is required. Install with: install.packages('arsenal')")
  }

  # Log comparison start
  logger(
    NOTE(
      "Dataset comparison started",
      user_id = user_id,
      reason = reason,
      study_id = study_id,
      old_rows = nrow(old_data),
      new_rows = nrow(new_data),
      old_hash = digest::digest(old_data),
      new_hash = digest::digest(new_data)
    )
  )

  # Run comparison
  comp <- arsenal::comparedf(old_data, new_data, ...)
  diffs <- summary(comp)

  # Log differences
  if (nrow(diffs$diffs.table) > 0) {
    for (i in seq_len(min(nrow(diffs$diffs.table), 100))) {  # Limit to 100 to avoid log spam
      diff <- diffs$diffs.table[i, ]

      logger(
        WARNING(
          "Data discrepancy detected",
          user_id = user_id,
          reason = reason,
          study_id = study_id,
          variable = diff$var.x,
          observation = diff$observation,
          old_value = as.character(diff$values.x),
          new_value = as.character(diff$values.y)
        )
      )
    }

    if (nrow(diffs$diffs.table) > 100) {
      logger(
        WARNING(
          paste("Additional discrepancies not logged (total:", nrow(diffs$diffs.table), ")"),
          user_id = user_id,
          study_id = study_id,
          total_differences = nrow(diffs$diffs.table)
        )
      )
    }
  }

  # Log summary
  logger(
    NOTE(
      "Dataset comparison completed",
      user_id = user_id,
      reason = reason,
      study_id = study_id,
      n_differences = nrow(diffs$diffs.table),
      n_variables_compared = length(diffs$vars.summary),
      match_rate = 1 - (nrow(diffs$diffs.table) / max(nrow(new_data), 1))
    )
  )

  invisible(comp)
}


#' Apply Electronic Signature to Validation
#'
#' Logs an electronic signature event for 21 CFR Part 11 compliance.
#'
#' @param validation_object The validation result object (from validate, pointblank, etc.)
#' @param logger A logthis logger object
#' @param user_id User identifier
#' @param password_hash Hashed password (for authentication - simplified example)
#' @param meaning Meaning of signature (e.g., "Approved", "Reviewed", "Rejected")
#' @param study_id Optional study identifier
#' @param verify_credentials Optional function to verify user credentials
#'
#' @return Invisibly returns TRUE if signature is applied
#'
#' @export
#' @family validation
#'
#' @examples
#' \dontrun{
#' # After validation
#' result <- validate_with_audit(data, rules, log_gxp, user_id = "jdoe")
#'
#' # Apply electronic signature
#' esign_validation(
#'   validation_object = result,
#'   logger = log_gxp,
#'   user_id = "jdoe",
#'   password_hash = digest::digest("password"),
#'   meaning = "Data Validation Approved"
#' )
#' }
esign_validation <- function(validation_object,
                              logger,
                              user_id,
                              password_hash,
                              meaning,
                              study_id = NULL,
                              verify_credentials = NULL) {
  # Verify credentials if function provided
  if (!is.null(verify_credentials)) {
    if (!verify_credentials(user_id, password_hash)) {
      logger(
        ERROR(
          "Electronic signature failed - invalid credentials",
          user_id = user_id,
          study_id = study_id,
          timestamp = Sys.time()
        )
      )
      stop("Invalid credentials")
    }
  }

  # Log electronic signature
  logger(
    NOTE(
      "Electronic signature applied",
      user_id = user_id,
      study_id = study_id,
      meaning = meaning,
      signed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
      validation_hash = digest::digest(validation_object),
      ip_address = Sys.getenv("SSH_CLIENT", "unknown"),
      r_version = paste(R.version$major, R.version$minor, sep = ".")
    )
  )

  invisible(TRUE)
}


# Helper operator for NULL coalescing
`%||%` <- function(x, y) {
  if (is.null(x)) y else x
}
