guard_level_type <- function(level){
  if (is.null(level)) {
    message("Level not specified, will not change value in logger.")
  } else {
    if (!(is.numeric(level) | inherits(level, "log_event_level"))) {
      stop("Level must be <numeric> or <log_event_level>")
    }
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
