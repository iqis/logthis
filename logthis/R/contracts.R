#' Contract Enforcement System for logthis
#'
#' Provides executable pre/post conditions and invariants that serve as
#' both runtime validation and machine-readable documentation for AI systems.
#'
#' @section Philosophy:
#' Contracts are code, not comments. They:
#' - Execute at runtime (can be disabled in production)
#' - Self-document expected behavior
#' - Provide immediate feedback on contract violations
#' - Are AI-readable without parsing roxygen comments
#' - Serve as single source of truth for function specifications
#'
#' @section Contract Types and Control:
#' Contracts can be independently enabled/disabled by type:
#'
#' - **Preconditions** (`require_that()`): Validate caller inputs
#'   - Control: `options(logthis.contracts.preconditions = FALSE)`
#'   - Use case: Disable in production for performance (trust validated inputs)
#'
#' - **Postconditions** (`ensure_that()`): Verify function correctness
#'   - Control: `options(logthis.contracts.postconditions = FALSE)`
#'   - Use case: Keep enabled in production to catch implementation bugs
#'
#' - **Invariants** (`check_invariant()`): Verify internal consistency
#'   - Control: `options(logthis.contracts.invariants = FALSE)`
#'   - Use case: Disable in hot paths, keep in critical operations
#'
#' - **Performance** (`with_performance_contract()`): Measure/enforce timing
#'   - Control: `options(logthis.contracts.performance = FALSE)`
#'   - Use case: Disable measurements in production, enable in testing
#'
#' @section Production Configuration Examples:
#' ```r
#' # Defensive: Trust inputs, verify correctness
#' options(logthis.contracts.preconditions = FALSE)  # Performance gain
#' # postconditions still enabled (default TRUE)
#'
#' # High-assurance: Always verify results
#' options(logthis.contracts.postconditions = TRUE)  # Force on
#'
#' # Performance-critical: Minimal checking
#' options(
#'   logthis.contracts.preconditions = FALSE,
#'   logthis.contracts.invariants = FALSE,
#'   logthis.contracts.postconditions = TRUE  # Keep final verification
#' )
#'
#' # Disable everything
#' options(
#'   logthis.contracts.preconditions = FALSE,
#'   logthis.contracts.postconditions = FALSE,
#'   logthis.contracts.invariants = FALSE,
#'   logthis.contracts.performance = FALSE
#' )
#' ```
#'
#' @section Contract Registry:
#' All contracts are automatically registered for internal introspection.
#' The registry is used by dev/generate_contract_docs.R to extract
#' contracts from code for documentation generation.
#'
#' @name contracts
NULL

# Internal contract registry (populated at runtime)
.contract_registry <- new.env(parent = emptyenv())

#' Register a contract for introspection
#' @keywords internal
.register_contract <- function(fn_name, type, conditions) {
  if (!exists(fn_name, envir = .contract_registry)) {
    .contract_registry[[fn_name]] <- list(
      preconditions = list(),
      postconditions = list(),
      invariants = list()
    )
  }

  .contract_registry[[fn_name]][[type]] <- c(
    .contract_registry[[fn_name]][[type]],
    list(conditions)
  )
}

#' Core contract checking logic
#' @keywords internal
.check_contract <- function(conditions,
                           contract_type,
                           calling_fn = NULL,
                           enabled = TRUE,
                           error_formatter) {
  condition_names <- names(conditions)

  if (is.null(condition_names) || any(condition_names == "")) {
    stop(sprintf("All %s must be named", contract_type), call. = FALSE)
  }

  # Auto-detect calling function if not provided
  if (is.null(calling_fn)) {
    calling_fn <- deparse(sys.call(-2)[[1]])
  }

  # Register contract for introspection
  .register_contract(calling_fn, contract_type, condition_names)

  if (!enabled) return(invisible(NULL))

  # Check all conditions
  for (i in seq_along(conditions)) {
    if (!isTRUE(conditions[[i]])) {
      stop(error_formatter(condition_names[i], calling_fn), call. = FALSE)
    }
  }

  invisible(NULL)
}

#' Get all registered contracts
#'
#' Returns all contracts registered during package execution.
#' Used internally by dev/generate_contract_docs.R.
#'
#' @return Named list of contracts by function
#' @keywords internal
get_all_contracts <- function() {
  as.list(.contract_registry)
}

#' Get contracts for specific function
#'
#' Used internally by dev/generate_contract_docs.R.
#'
#' @param fn_name Function name as string
#' @return List with preconditions, postconditions, invariants
#' @keywords internal
get_function_contracts <- function(fn_name) {
  if (!exists(fn_name, envir = .contract_registry)) {
    return(list(
      preconditions = list(),
      postconditions = list(),
      invariants = list()
    ))
  }
  .contract_registry[[fn_name]]
}

#' Check Preconditions
#'
#' Validates function inputs. Failures indicate caller error.
#'
#' Control preconditions independently with:
#' `options(logthis.contracts.preconditions = FALSE)`
#'
#' @param ... Named logical conditions to check
#' @param .enabled Whether to enforce (default: getOption("logthis.contracts.preconditions", TRUE))
#' @param .calling_fn Name of calling function (auto-detected if NULL)
#'
#' @return Invisible NULL if all pass, otherwise stops with descriptive error
#'
#' @examples
#' my_function <- function(x, y) {
#'   require_that(
#'     "x must be numeric" = is.numeric(x),
#'     "y must be positive" = is.numeric(y) && y > 0,
#'     "x and y must be same length" = length(x) == length(y)
#'   )
#'   # ... rest of function
#' }
#'
#' # Disable preconditions for performance
#' options(logthis.contracts.preconditions = FALSE)
#'
#' @export
require_that <- function(...,
                        .enabled = getOption("logthis.contracts.preconditions", TRUE),
                        .calling_fn = NULL) {
  .check_contract(
    conditions = list(...),
    contract_type = "preconditions",
    calling_fn = .calling_fn,
    enabled = .enabled,
    error_formatter = function(condition, fn) {
      paste0(
        "Precondition failed: ", condition, "\n",
        "  Function: ", fn, "\n",
        "  This indicates incorrect usage. Please check the function documentation."
      )
    }
  )
}


#' Check Postconditions
#'
#' Validates function outputs and object state. Failures indicate bugs.
#'
#' Control postconditions independently with:
#' `options(logthis.contracts.postconditions = FALSE)`
#'
#' @param ... Named logical conditions to check
#' @param .enabled Whether to enforce (default: getOption("logthis.contracts.postconditions", TRUE))
#' @param .calling_fn Name of calling function (auto-detected if NULL)
#'
#' @return Invisible NULL if all pass, otherwise stops with BUG error
#'
#' @examples
#' logger <- function(void = FALSE) {
#'   # ... create result ...
#'
#'   ensure_that(
#'     "result is log_logger" = inherits(result, "log_logger"),
#'     "result is function" = is.function(result),
#'     "config is list" = is.list(attr(result, "config")),
#'     "receivers match labels" =
#'       length(attr(result, "config")$receivers) ==
#'       length(attr(result, "config")$receiver_labels)
#'   )
#'
#'   result
#' }
#'
#' # Keep postconditions on in production to catch bugs
#' options(logthis.contracts.postconditions = TRUE)
#'
#' @export
ensure_that <- function(...,
                       .enabled = getOption("logthis.contracts.postconditions", TRUE),
                       .calling_fn = NULL) {
  .check_contract(
    conditions = list(...),
    contract_type = "postconditions",
    calling_fn = .calling_fn,
    enabled = .enabled,
    error_formatter = function(condition, fn) {
      paste0(
        "Postcondition failed: ", condition, "\n",
        "  Function: ", fn, "\n",
        "  This is a BUG in logthis. Please report at: ",
        "https://github.com/iqis/logthis/issues\n",
        "  Include the full error message and a reproducible example."
      )
    }
  )
}


#' Check Invariants
#'
#' Validates object state that must always hold true.
#' Can be called at any point to verify internal consistency.
#'
#' Control invariants independently with:
#' `options(logthis.contracts.invariants = FALSE)`
#'
#' @param ... Named logical conditions to check
#' @param .enabled Whether to enforce (default: getOption("logthis.contracts.invariants", TRUE))
#' @param .calling_fn Name of calling function (auto-detected if NULL)
#'
#' @return Invisible NULL if all pass, otherwise stops with INVARIANT error
#'
#' @examples
#' with_receivers <- function(logger_obj, ...) {
#'   # Verify logger state before modification
#'   check_invariant(
#'     "logger has config" = !is.null(attr(logger_obj, "config")),
#'     "receivers is list" = is.list(attr(logger_obj, "config")$receivers)
#'   )
#'
#'   # ... modify logger ...
#'
#'   # Verify logger state after modification
#'   check_invariant(
#'     "receivers match labels" =
#'       length(new_config$receivers) == length(new_config$receiver_labels)
#'   )
#'
#'   new_logger
#' }
#'
#' # Disable invariants in performance-critical code
#' options(logthis.contracts.invariants = FALSE)
#'
#' @export
check_invariant <- function(...,
                           .enabled = getOption("logthis.contracts.invariants", TRUE),
                           .calling_fn = NULL) {
  .check_contract(
    conditions = list(...),
    contract_type = "invariants",
    calling_fn = .calling_fn,
    enabled = .enabled,
    error_formatter = function(condition, fn) {
      paste0(
        "Invariant violated: ", condition, "\n",
        "  Function: ", fn, "\n",
        "  This indicates corrupted internal state (BUG).\n",
        "  Please report at: https://github.com/iqis/logthis/issues"
      )
    }
  )
}


#' Assert Type Contract
#'
#' Shorthand for common type-checking preconditions.
#'
#' @param x Value to check
#' @param type Character vector of acceptable classes
#' @param allow_null Whether NULL is acceptable (default: FALSE)
#' @param .enabled Whether to enforce
#'
#' @return Invisible NULL if valid, otherwise stops
#'
#' @examples
#' to_text_file <- function(path, append = TRUE) {
#'   assert_type(path, "character")
#'   assert_type(append, "logical")
#'   # ... rest of function
#' }
#'
#' @export
assert_type <- function(x,
                        type,
                        allow_null = FALSE,
                        .enabled = getOption("logthis.contracts.preconditions", TRUE)) {
  if (!.enabled) return(invisible(NULL))

  var_name <- deparse(substitute(x))

  if (is.null(x)) {
    if (allow_null) {
      return(invisible(NULL))
    } else {
      stop(var_name, " must not be NULL", call. = FALSE)
    }
  }

  if (!inherits(x, type)) {
    stop(
      var_name, " must be ", paste(type, collapse = " or "),
      ", not ", class(x)[1],
      call. = FALSE
    )
  }

  invisible(NULL)
}


#' Assert Range Contract
#'
#' Shorthand for numeric range checking.
#'
#' @param x Numeric value to check
#' @param min Minimum value (inclusive)
#' @param max Maximum value (inclusive)
#' @param .enabled Whether to enforce
#'
#' @return Invisible NULL if valid, otherwise stops
#'
#' @examples
#' log_event_level <- function(level_class, level_number) {
#'   assert_range(level_number, min = 0, max = 100)
#'   # ... rest of function
#' }
#'
#' @export
assert_range <- function(x,
                         min = -Inf,
                         max = Inf,
                         .enabled = getOption("logthis.contracts.preconditions", TRUE)) {
  if (!.enabled) return(invisible(NULL))

  var_name <- deparse(substitute(x))

  if (!is.numeric(x)) {
    stop(var_name, " must be numeric for range check", call. = FALSE)
  }

  if (any(x < min | x > max)) {
    stop(
      var_name, " must be in range [", min, ", ", max, "], ",
      "got: ", paste(head(x), collapse = ", "),
      call. = FALSE
    )
  }

  invisible(NULL)
}


#' Assert Length Contract
#'
#' Shorthand for length checking.
#'
#' @param x Value to check
#' @param n Expected length (or NULL for no check)
#' @param min Minimum length (default: 1)
#' @param max Maximum length (default: Inf)
#' @param .enabled Whether to enforce
#'
#' @return Invisible NULL if valid, otherwise stops
#'
#' @examples
#' my_function <- function(x, flag) {
#'   assert_length(flag, n = 1)  # Exactly one value
#'   assert_length(x, min = 1)   # At least one value
#'   # ... rest of function
#' }
#'
#' @export
assert_length <- function(x,
                          n = NULL,
                          min = 1,
                          max = Inf,
                          .enabled = getOption("logthis.contracts.preconditions", TRUE)) {
  if (!.enabled) return(invisible(NULL))

  var_name <- deparse(substitute(x))
  len <- length(x)

  if (!is.null(n)) {
    if (len != n) {
      stop(var_name, " must have length ", n, ", got ", len, call. = FALSE)
    }
  } else {
    if (len < min || len > max) {
      stop(
        var_name, " length must be in [", min, ", ", max, "], got ", len,
        call. = FALSE
      )
    }
  }

  invisible(NULL)
}


#' Performance Contract
#'
#' Documents and optionally enforces performance characteristics.
#' Useful for regression testing and AI understanding of complexity.
#'
#' Control performance contracts independently with:
#' `options(logthis.contracts.performance = FALSE)`
#'
#' @param operation_name Human-readable operation description
#' @param expr Expression to time
#' @param max_seconds Maximum allowed time (Inf to only measure, not enforce)
#' @param log_to Optional logger to log timing information
#' @param .enabled Whether to enforce
#'
#' @return Result of expr
#'
#' @examples
#' \dontrun{
#' # Just measure (don't enforce)
#' result <- with_performance_contract(
#'   "Build 1000-event parquet file",
#'   {
#'     for (i in 1:1000) log(NOTE("event"))
#'   },
#'   max_seconds = Inf
#' )
#'
#' # Enforce performance requirement
#' result <- with_performance_contract(
#'   "Single log event",
#'   log(NOTE("test")),
#'   max_seconds = 0.01  # Must complete in 10ms
#' )
#' }
#'
#' @export
with_performance_contract <- function(operation_name,
                                      expr,
                                      max_seconds = Inf,
                                      log_to = NULL,
                                      .enabled = getOption("logthis.contracts.performance", TRUE)) {
  if (!.enabled) return(eval.parent(substitute(expr)))

  start_time <- Sys.time()
  result <- eval.parent(substitute(expr))
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))

  # Log if logger provided
  if (!is.null(log_to)) {
    log_to(NOTE(
      paste("Performance:", operation_name),
      elapsed_seconds = elapsed,
      within_contract = elapsed <= max_seconds
    ))
  }

  # Enforce if max_seconds is finite
  if (is.finite(max_seconds) && elapsed > max_seconds) {
    stop(
      "Performance contract violated: ", operation_name, "\n",
      "  Expected: <= ", max_seconds, "s\n",
      "  Actual:   ", round(elapsed, 4), "s",
      call. = FALSE
    )
  }

  result
}
