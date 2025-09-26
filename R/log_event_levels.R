#' Log Event Levels
#'
#' @param class S3 class of the event; <character>
#' @param level_number level number; <integer>
#'
#' @return log event constructor; <function>
#' @export
log_event_level <- function(level_class, level_number){

  `if`(!is.character(level_class),
       stop("level_class must be character."))

  `if`(missing(level_class) | is.null(level_class) | is.na(level_class) | level_class == "",
       stop("level_class must be non empty."))

  # Get the structured level_number for validation but extract raw value for storage
  validated_level_number <- level_number(level_number)
  raw_level_number <- as.numeric(validated_level_number)

  structure(
    function(message = "", ...){
      event_data <- list(message = message,
                        time = Sys.time(),
                        level = level_class,
                        level_number = raw_level_number)
      
      # Add extra arguments
      extra_args <- list(...)
      if (length(extra_args) > 0) {
        event_data <- c(event_data, extra_args)
      }
      
      structure(event_data,
                class = c(level_class, "log_event"))
    },
    level_number = raw_level_number,  # Store the raw numeric instead of structured object
    level_class = level_class,
    class = c("log_event_level",
              "function"))
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
ERROR  <- log_event_level("ERROR", 100)

#' @export
#' @rdname log_event_level
HIGHEST  <- log_event_level("HIGHEST", 120)
