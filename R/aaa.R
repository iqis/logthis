#' @importFrom crayon white silver green yellow red bold
#' @importFrom purrr compose
NULL

guard_level_type <- function(level){
  if (is.null(level)) {
    message("Level not specified, will not change value in logger.")
  } else {
    if (!(is.numeric(level) | inherits(level, "log_event_level"))) {
      stop("Level must be <numeric> or <log_event_level>")
    }
  }
}

# Package-level constant for log level to color mapping
# Used by to_console() receiver
.LEVEL_COLOR_MAP <- list(
  levels = c(0, 20, 40, 60, 80, 100),
  colors = list(
    crayon::white,
    crayon::silver,
    crayon::green,
    crayon::yellow,
    crayon::red,
    purrr::compose(crayon::red, crayon::bold)
  )
)

# Efficient color lookup function
get_log_color <- function(level_number) {
  idx <- findInterval(level_number, .LEVEL_COLOR_MAP$levels, rightmost.closed = TRUE)
  # findInterval returns 0 if level_number < min, so we need to handle that
  if (idx == 0) idx <- 1
  .LEVEL_COLOR_MAP$colors[[idx]]
}
