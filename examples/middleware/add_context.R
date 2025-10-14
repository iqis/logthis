# Context Enrichment Middleware
#
# Demonstrates how to automatically add contextual information to all log events
# before they reach receivers. Useful for distributed systems, microservices,
# and multi-tenant applications.

library(logthis)

# ==============================================================================
# Example 1: Add Hostname and System Information
# ==============================================================================

#' Add system context to all log events
#'
#' Automatically adds hostname, OS, and R version to every log event. Useful for
#' distributed systems where logs are aggregated from multiple servers.
#'
#' @return middleware function
add_system_context <- middleware(function(event) {
  sys_info <- Sys.info()

  event$hostname <- sys_info[["nodename"]]
  event$os <- paste(sys_info[["sysname"]], sys_info[["release"]])
  event$r_version <- paste(R.version$major, R.version$minor, sep = ".")

  event
})

# Usage
log_this <- logger() %>%
  with_middleware(add_system_context) %>%
  with_receivers(to_json() %>% on_local("app.jsonl"))

log_this(NOTE("Application started"))
# Output: JSON with hostname, os, r_version fields added

# ==============================================================================
# Example 2: Add Application Version and Environment
# ==============================================================================

#' Add application metadata to all log events
#'
#' Captures application version, deployment environment, and build timestamp.
#' Critical for troubleshooting production issues.
#'
#' @param app_name Application name
#' @param app_version Application version (from DESCRIPTION or config)
#' @param environment Deployment environment (dev/staging/prod)
#' @return middleware function
add_app_context <- function(app_name, app_version, environment) {
  middleware(function(event) {
    event$app_name <- app_name
    event$app_version <- app_version
    event$environment <- environment

    event
  })
}

# Usage
log_this <- logger() %>%
  with_middleware(
    add_app_context(
      app_name = "clinical-data-pipeline",
      app_version = "1.2.3",
      environment = Sys.getenv("ENVIRONMENT", "dev")
    )
  ) %>%
  with_receivers(to_console())

log_this(WARNING("Database connection slow", query_time_ms = 2500))
# Output: Includes app_name, app_version, environment fields

# ==============================================================================
# Example 3: Add Request ID (Distributed Tracing)
# ==============================================================================

#' Add request/trace ID to all log events in current context
#'
#' For distributed tracing across microservices. The request ID should be
#' propagated from incoming HTTP headers and attached to all logs.
#'
#' @param request_id Unique request identifier (UUID or similar)
#' @return middleware function
add_request_id <- function(request_id = NULL) {
  # Generate request ID if not provided
  if (is.null(request_id)) {
    request_id <- paste0(
      format(Sys.time(), "%Y%m%d%H%M%S"),
      "-",
      paste(sample(c(0:9, letters[1:6]), 8, replace = TRUE), collapse = "")
    )
  }

  middleware(function(event) {
    event$request_id <- request_id
    event
  })
}

# Usage in API handler
handle_api_request <- function(req) {
  # Extract request ID from header or generate new one
  request_id <- req$headers[["X-Request-ID"]] %||% uuid::UUIDgenerate()

  # Create logger with request context
  log_this <- logger() %>%
    with_middleware(
      add_request_id(request_id),
      add_system_context
    ) %>%
    with_receivers(to_json() %>% on_local("api.jsonl"))

  log_this(NOTE("API request received", endpoint = req$path, method = req$method))

  # ... handle request ...

  log_this(NOTE("API request completed", status_code = 200, duration_ms = 45))
}

# ==============================================================================
# Example 4: Add User Context (Authentication)
# ==============================================================================

#' Add authenticated user information to log events
#'
#' For audit trails requiring user attribution. Captures user ID, roles,
#' and authentication method.
#'
#' @param user_id User identifier
#' @param roles Character vector of user roles
#' @param auth_method Authentication method (e.g., "oauth2", "api_key")
#' @return middleware function
add_user_context <- function(user_id, roles = NULL, auth_method = NULL) {
  middleware(function(event) {
    event$user_id <- user_id

    if (!is.null(roles)) {
      event$user_roles <- paste(roles, collapse = ",")
    }

    if (!is.null(auth_method)) {
      event$auth_method <- auth_method
    }

    event
  })
}

# Usage in authenticated session
create_session_logger <- function(session) {
  logger() %>%
    with_middleware(
      add_user_context(
        user_id = session$user$id,
        roles = session$user$roles,
        auth_method = "oauth2"
      )
    ) %>%
    with_tags("audit_trail") %>%
    with_receivers(
      to_json() %>% on_local("user_actions.jsonl")
    )
}

# ==============================================================================
# Example 5: Add Process/Thread Information
# ==============================================================================

#' Add process and session information
#'
#' Useful for parallel processing or long-running applications with multiple
#' concurrent sessions.
#'
#' @return middleware function
add_process_context <- middleware(function(event) {
  event$pid <- Sys.getpid()
  event$session_id <- Sys.getenv("RSTUDIO_SESSION_ID", "unknown")

  # Add parent process info if available
  if (nzchar(Sys.getenv("R_PARENT_PID"))) {
    event$parent_pid <- Sys.getenv("R_PARENT_PID")
  }

  event
})

# ==============================================================================
# Example 6: Add Git Commit Hash (Deployment Tracking)
# ==============================================================================

#' Add git commit information to log events
#'
#' Captures the git commit hash of the deployed code. Useful for correlating
#' production issues with specific code versions.
#'
#' @return middleware function
add_git_context <- middleware(function(event) {
  # Try to read git commit from environment variable (set during deployment)
  git_commit <- Sys.getenv("GIT_COMMIT", NA)

  # If not set, try to read from .git directory (development only)
  if (is.na(git_commit)) {
    git_head_file <- ".git/HEAD"
    if (file.exists(git_head_file)) {
      ref_line <- readLines(git_head_file, n = 1, warn = FALSE)
      if (grepl("^ref:", ref_line)) {
        # HEAD points to a ref
        ref_path <- sub("^ref: ", "", ref_line)
        ref_file <- file.path(".git", ref_path)
        if (file.exists(ref_file)) {
          git_commit <- trimws(readLines(ref_file, n = 1, warn = FALSE))
        }
      } else {
        # Detached HEAD (commit hash directly)
        git_commit <- ref_line
      }
    }
  }

  if (!is.na(git_commit) && nzchar(git_commit)) {
    event$git_commit <- substr(git_commit, 1, 8)  # Short hash
  }

  event
})

# ==============================================================================
# Example 7: Comprehensive Production Context
# ==============================================================================

#' Production-ready context enrichment
#'
#' Combines multiple context sources for complete observability. Suitable for
#' microservices, API backends, and data pipelines.
#'
#' @param app_config List with app_name, app_version, environment
#' @param request_id Optional request/trace ID
#' @param user_id Optional authenticated user ID
#' @return middleware function
add_production_context <- function(app_config, request_id = NULL, user_id = NULL) {
  middleware(function(event) {
    # System context
    sys_info <- Sys.info()
    event$hostname <- sys_info[["nodename"]]

    # Application context
    event$app_name <- app_config$app_name
    event$app_version <- app_config$app_version
    event$environment <- app_config$environment

    # Request context (if available)
    if (!is.null(request_id)) {
      event$request_id <- request_id
    }

    # User context (if available)
    if (!is.null(user_id)) {
      event$user_id <- user_id
    }

    # Process context
    event$pid <- Sys.getpid()

    # Git context
    git_commit <- Sys.getenv("GIT_COMMIT", NA)
    if (!is.na(git_commit) && nzchar(git_commit)) {
      event$git_commit <- substr(git_commit, 1, 8)
    }

    event
  })
}

# Usage example: API microservice
app_config <- list(
  app_name = "customer-api",
  app_version = "2.1.0",
  environment = Sys.getenv("ENV", "production")
)

api_handler <- function(req) {
  log_this <- logger() %>%
    with_middleware(
      add_production_context(
        app_config = app_config,
        request_id = req$headers[["X-Request-ID"]],
        user_id = req$user$id
      )
    ) %>%
    with_receivers(
      to_json() %>% on_local("api.jsonl"),
      to_console(lower = WARNING)  # Only warnings+ to console
    )

  log_this(NOTE("Processing request", endpoint = req$path))
  # ... business logic ...
  log_this(NOTE("Request completed", status = 200))
}

# ==============================================================================
# Example 8: Pharmaceutical/Clinical Context
# ==============================================================================

#' Add GxP audit trail context
#'
#' For pharmaceutical and clinical applications requiring 21 CFR Part 11
#' compliance. Captures study, site, and operator information.
#'
#' @param study_id Clinical study identifier
#' @param site_id Clinical site identifier
#' @param operator_id Operator/technician ID
#' @param system_id Validated system ID (for CSV compliance)
#' @return middleware function
add_gxp_context <- function(study_id, site_id = NULL, operator_id = NULL, system_id = NULL) {
  middleware(function(event) {
    event$study_id <- study_id

    if (!is.null(site_id)) {
      event$site_id <- site_id
    }

    if (!is.null(operator_id)) {
      event$operator_id <- operator_id
    }

    if (!is.null(system_id)) {
      event$system_id <- system_id
      event$system_validated <- TRUE
    }

    # Add timestamp in ISO 8601 format (regulatory requirement)
    event$timestamp_iso <- format(event$time, "%Y-%m-%dT%H:%M:%S%z")

    event
  })
}

# Usage: Clinical data processing
log_clinical <- logger() %>%
  with_middleware(
    add_gxp_context(
      study_id = "TRIAL-2024-001",
      site_id = "SITE-NYU-01",
      operator_id = "OP-12345",
      system_id = "LIMS-PROD-001"
    )
  ) %>%
  with_tags("GxP", "audit_trail", "21CFR11") %>%
  with_receivers(
    to_json() %>% on_local("gxp_audit.jsonl"),
    to_text() %>% on_local("gxp_audit.log")
  )

log_clinical(NOTE("Sample analysis started", sample_id = "SMP-001", assay = "HPLC"))
# Output: Includes study_id, site_id, operator_id, system_id, timestamp_iso
