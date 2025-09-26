guard_level_type <- function(level){
  if (is.null(level)) {
    message("Level not specified, will not change value in logger.")
  } else {
    if (!(is.numeric(level) | inherits(level, "log_event_level"))) {
      stop("Level must be <numeric> or <log_event_level>")
    }
  }
}

# Internal function for extracting level numbers without validation
# Used by with_limits.logger for processing limit arguments
make_level_number <- function(level, validate = FALSE) {
  if (is.numeric(level)) {
    level_number <- level
  } else if (inherits(level, "log_event_level")) {
    level_number <- attr(level, "level_number")
  } else if (inherits(level, "log_event")) {
    level_number <- level$level_number
  } else {
    stop("Level must be <numeric> or <log_event_level>")
  }

  res <- round(level_number)
  
  if (validate) {
    # Only validate and warn when explicitly requested (for level creation)
    if (level_number < 0 | level_number > 120) {
      stop("Level number must be within [0, 120].")
    }
    
    if (level_number != res) {
      warning(glue::glue("Level number {{level_number}} is rounded to {{res}}."))
    }
    
    structure(res, class = "level_number")
  } else {
    # Simple extraction for internal use (for limit processing)
    res
  }
}

# Full validation version for creating log event levels
level_number <- function(level){
  make_level_number(level, validate = TRUE)
}
