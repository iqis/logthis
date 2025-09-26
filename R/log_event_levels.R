#' Log Event Levels
#'
#' @param level_class S3 class of the event; <character>
#' @param level_number level number; <integer>
#'
#' @return log event constructor; <function>
#' @export
log_event_level <- function(level_class, level_number){

  `if`(!is.character(level_class),
       stop("level_class must be character."))

  `if`(missing(level_class) | is.null(level_class) | is.na(level_class) | level_class == "",
       stop("level_class must be non empty."))

  level_number <- make_level_number(level_number, validate = TRUE)

  structure(
    function(message = "", ...){
      structure(list(message = message,
                     time = Sys.time(),
                     level_class = level_class,
                     level_number = level_number,
                     tags = c(),
                     ...),
                class = c(level_class,
                          "log_event"))
    },
    level_number = level_number,
    level_class = level_class,
    class = c("log_event_level",
              "function"))
}

#' Extract and normalize level number from log_event_level or numeric values
#'
#' Converts log_event_level objects to numeric values, handles rounding and validation
#'
#' @param x A log_event_level object, log_event object, or numeric value
#' @param validate Whether to validate range and warn about rounding (default TRUE for level creation, FALSE for limits)
#' @return Numeric level number, rounded if necessary
#' @keywords internal
make_level_number <- function(x, validate = FALSE) {
  if (inherits(x, "log_event_level")) {
    res <- attr(x, "level_number")
  } else if (inherits(x, "log_event")) {
    res <- x$level_number
  } else if (is.numeric(x)) {
    res <- x
  } else {
    stop("Level must be a log_event_level object, log_event object, or numeric value")
  }
  
  if (validate) {
    if (res < 0 | res > 120) {
      stop("Level number must be within [0, 120].")
    }

    original_res <- res
    res <- round(res)

    if (original_res != res) {
      warning(glue::glue("Level number {{original_res}} is rounded to {{res}}."))
    }
    
    return(structure(res, class = "level_number"))
  } else {
    return(round(res))
  }
}

#' @export
#' @rdname log_event_level
LOWEST <- log_event_level("LOWEST", 0)

#' @export
#' @rdname log_event_level
CHATTER <- log_event_level("CHATTER", 20)

#' @export
#' @rdname log_event_level
NOTE <- log_event_level("NOTE", 40)

#' @export
#' @rdname log_event_level
MESSAGE <- log_event_level("MESSAGE", 60)

#' @export
#' @rdname log_event_level
WARNING <- log_event_level("WARNING", 80)

#' @export
#' @rdname log_event_level
ERROR <- log_event_level("ERROR", 100)

#' @export
#' @rdname log_event_level
HIGHEST <- log_event_level("HIGHEST", 120)
