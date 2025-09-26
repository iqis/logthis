guard_level_type <- function(level){
  if (is.null(level)) {
    message("Level not specified, will not change value in logger.")
  } else {
    if (!(is.numeric(level) | inherits(level, "log_event_level"))) {
      stop("Level must be <numeric> or <log_event_level>")
    }
  }
}

# Internal function for processing level numbers in limits
make_level_number <- function(level){
  if (is.null(level)) {
    return(NULL)
  } else if (is.numeric(level)) {
    return(round(level))
  } else if (inherits(level, "log_event_level")) {
    return(as.numeric(attr(level, "level_number")))
  } else if (inherits(level, "log_event")) {
    return(level$level_number)
  } else {
    stop("Level must be <numeric>, <log_event_level>, or <log_event>")
  }
}

# Alias for backward compatibility with tests - returns simple numeric
normalize_limit <- function(level){
  if (is.null(level)) {
    return(NULL)
  } else if (is.numeric(level)) {
    return(round(level))
  } else if (inherits(level, "log_event_level")) {
    return(as.numeric(attr(level, "level_number")))
  } else if (inherits(level, "log_event")) {
    return(level$level_number)
  } else {
    stop("Level must be <numeric>, <log_event_level>, or <log_event>")
  }
}

level_number <- function(level){
  if (is.numeric(level)) {
    level_number <- level
  } else if (inherits(level, "log_event_level")) {
    level_number <- attr(level, "level_number")
  } else if (inherits(level, "log_event")) {
    level_number <- level$level_number
  }

  `if`(level_number < 0 | level_number > 120,
       stop("Level number must be within [0, 120]."))

  res <- round(level_number)

  `if`(level_number != res,
       warning(glue::glue("Level number {{level_number}} is rounded to {{res}}.")))

  structure(res,
            class = "level_number")
}
