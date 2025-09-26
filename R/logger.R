#' Create a logger
#'
#' @return logger; <logger>
#' @export
#'
#' @examples
#'
#' log_this <- logger()
#'
logger <- function(){
  structure(function(event, ...){

    config <- attr(sys.function(),
                   "config")
    config$receivers %>%
      purrr::map(purrr::exec,
                 event = event)
  },
  class = c("logger",
            "function"),
  config = list(limits = list(lower = 0,
                              upper = 120),
                receivers = list()))
}

#' @export
#' @rdname logger
dummy_logger <- function(){
  structure(function(event, ...){
    invisible(NULL)
  },
  class = c("logger",
            "function"),
  config = list(limits = list(lower = 0,
                              upper = 120),
                receivers = list()))
}

#' Add receivers to a logger
#'
#' @param logger a logger; <logger>
#' @param ... receivers; <log_receiver>
#' @param append to append to existing receivers, or to overwrite; <logical>
#'
#' @return logger; <logger>
#' @export
#'
#' @examples
#'
#' log_this <- logger() %>%
#'     with_receivers(to_identity(),
#'                    list(to_zero(),
#'                         to_one()))
#'
with_receivers <- function(logger, ..., append = TRUE){
  if (!inherits(logger, "logger")) {
    stop("Argument `logger` must be of type 'logger'. ")
  }

  receivers <- unlist(list(...))

  if (length(receivers) == 0) {
    warning("`...` (receivers) is not supplied.")
  }

  purrr::map(receivers,
             ~ {if (!inherits(., "log_receiver")) {
               stop("Argument `...` (receivers) must be of type 'log_receiver'")
             }})

  config <- attr(logger, "config")
  if (append) {
    config$receivers <- c(config$receivers, receivers)
  } else {
    config$receivers <- receivers
  }
  attr(logger, "config") <- config

  logger
}


with_limits <- function(x, lower, upper, ...){
  UseMethod("with_limits", x)
}

#' Set limits to a logger
#'
#' Log events with level number smaller than the lower limit or
#' higher than the upper limit will be ignored by the logger.
#'
#' @param logger logger; <logger>
#' @param lower lower limit; <numeric> | <log_event_level>
#' @param upper uppwer limit; <numeric> | <log_event_level>
#'
#' @return logger; <logger>
#' @export
#'
#' @examples
#' log_this <- logger() %>%
#'     with_limits(lower = 20,
#'                 upper = logthis::WARNING)
with_limits.logger <- function(x, lower = LOWEST, upper = HIGHEST, ...){
  logger <- x

  lower <- make_level_number(lower)
  upper <- make_level_number(upper)

  config <- attr(logger, "config")

  # guard limit values & apply to config if not null
  if (!is.null(lower)) {
    if (lower < 0 | lower > 119) {
      stop(glue::glue("Lower limit must be in [0, 119], got {lower}"))
    }
    config$limits$lower <- lower
  }

  if (!is.null(upper)) {
    if (upper < 1 | upper > 120) {
      stop(glue::glue("Upper limit must be in [1, 120], got {upper}"))
    }
    config$limits$upper <- upper
  }

  attr(logger, "config") <- config

  logger
}

with_limits.log_receiver <- function(x, lower, upper, ...){
  log_receiver <- x





}


# TODO:
# with_tags() associates tags with log events.
# This can be done to log event levels and receivers, too.
with_tags <- function(x, ...){
  UseMethod("with_tags", x)
}

with_tags.log_event <- function(x, ..., append = TRUE){
  log_event <- x
  tags <- unlist(list(...))

  old_tags <- attr(log_event, "tags")

  if (append) {
    new_tags <- c(old_tags, tags)
  } else {
    new_tags <- tags
  }

  attr(log_event,  "tags") <- new_tags

  log_event
}

with_tags.log_event_level <- function(x, ..., append = TRUE){

  # automatically give every event the tags

}


with_tags.logger <- function(x, ..., append = TRUE){

  # automatically give every event the tags, configure only, implement in logger

  logger <- x
  if (!inherits(logger, "logger")) {
    stop("Argument `logger` must be of type 'logger'. ")
  }

  tags <- unlist(list(...))

  if (length(tags) == 0) {
    warning("`...` (tags) is not supplied.")
  }

  purrr::map(tags,
             ~ {if (!inherits(., "character")) {
               stop("Argument `...` (tags) must be of type 'character'")
             }})

  config <- attr(logger, "config")
  if (append) {
    config$tags <- c(config$tags, tags)
  } else {
    config$tags <- tags
  }
  attr(logger, "config") <- config

  logger


}
