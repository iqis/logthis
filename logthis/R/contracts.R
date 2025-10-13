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
#' @section Contract Registry:
#' All contracts are automatically registered for introspection:
#' - `get_all_contracts()` - List all contracts in package
#' - `get_function_contracts("logger")` - Get contracts for specific function
#' - `verify_all_contracts()` - Run contract verification tests
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

#' Get all registered contracts
#'
#' Returns all contracts registered during package execution.
#' Useful for generating documentation and verification.
#'
#' @return Named list of contracts by function
#' @export
#' @family contracts
get_all_contracts <- function() {
  as.list(.contract_registry)
}

#' Get contracts for specific function
#'
#' @param fn_name Function name as string
#' @return List with preconditions, postconditions, invariants
#' @export
#' @family contracts
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
#' @param ... Named logical conditions to check
#' @param .enabled Whether to enforce (default: getOption("logthis.contracts", TRUE))
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
#' @export
require_that <- function(...,
                        .enabled = getOption("logthis.contracts", TRUE),
                        .calling_fn = NULL) {
  conditions <- list(...)
  condition_names <- names(conditions)

  if (is.null(condition_names) || any(condition_names == "")) {
    stop("All preconditions must be named", call. = FALSE)
  }

  # Register contract for introspection
  if (is.null(.calling_fn)) {
    # Auto-detect calling function
    .calling_fn <- deparse(sys.call(-1)[[1]])
  }
  .register_contract(.calling_fn, "preconditions", condition_names)

  if (!.enabled) return(invisible(NULL))

  for (i in seq_along(conditions)) {
    if (!isTRUE(conditions[[i]])) {
      stop(
        "Precondition failed: ", condition_names[i], "\n",
        "  Function: ", .calling_fn, "\n",
        "  This indicates incorrect usage. Please check the function documentation.",
        call. = FALSE
      )
    }
  }

  invisible(NULL)
}


#' Check Postconditions
#'
#' Validates function outputs and object state. Failures indicate bugs.
#'
#' @param ... Named logical conditions to check
#' @param .enabled Whether to enforce (default: getOption("logthis.contracts", TRUE))
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
#' @export
ensure_that <- function(...,
                       .enabled = getOption("logthis.contracts", TRUE),
                       .calling_fn = NULL) {
  conditions <- list(...)
  condition_names <- names(conditions)

  if (is.null(condition_names) || any(condition_names == "")) {
    stop("All postconditions must be named", call. = FALSE)
  }

  # Register contract for introspection
  if (is.null(.calling_fn)) {
    .calling_fn <- deparse(sys.call(-1)[[1]])
  }
  .register_contract(.calling_fn, "postconditions", condition_names)

  if (!.enabled) return(invisible(NULL))

  for (i in seq_along(conditions)) {
    if (!isTRUE(conditions[[i]])) {
      stop(
        "Postcondition failed: ", condition_names[i], "\n",
        "  Function: ", .calling_fn, "\n",
        "  This is a BUG in logthis. Please report at: ",
        "https://github.com/iqis/logthis/issues\n",
        "  Include the full error message and a reproducible example.",
        call. = FALSE
      )
    }
  }

  invisible(NULL)
}


#' Check Invariants
#'
#' Validates object state that must always hold true.
#' Can be called at any point to verify internal consistency.
#'
#' @param ... Named logical conditions to check
#' @param .enabled Whether to enforce (default: getOption("logthis.contracts", TRUE))
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
#' @export
check_invariant <- function(...,
                           .enabled = getOption("logthis.contracts", TRUE),
                           .calling_fn = NULL) {
  conditions <- list(...)
  condition_names <- names(conditions)

  if (is.null(condition_names) || any(condition_names == "")) {
    stop("All invariants must be named", call. = FALSE)
  }

  # Register contract for introspection
  if (is.null(.calling_fn)) {
    .calling_fn <- deparse(sys.call(-1)[[1]])
  }
  .register_contract(.calling_fn, "invariants", condition_names)

  if (!.enabled) return(invisible(NULL))

  for (i in seq_along(conditions)) {
    if (!isTRUE(conditions[[i]])) {
      stop(
        "Invariant violated: ", condition_names[i], "\n",
        "  Function: ", .calling_fn, "\n",
        "  This indicates corrupted internal state (BUG).\n",
        "  Please report at: https://github.com/iqis/logthis/issues",
        call. = FALSE
      )
    }
  }

  invisible(NULL)
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
                        .enabled = getOption("logthis.contracts", TRUE)) {
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
                         .enabled = getOption("logthis.contracts", TRUE)) {
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
                          .enabled = getOption("logthis.contracts", TRUE)) {
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
                                      .enabled = getOption("logthis.contracts", TRUE)) {
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
