#' @importFrom crayon white silver green yellow red bold cyan
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
# Maps to levels: LOWEST(0), TRACE(10), DEBUG(20), NOTE(30), MESSAGE(40), WARNING(60), ERROR(80), CRITICAL(90), HIGHEST(100)
.LEVEL_COLOR_MAP <- list(
  levels = c(0, 10, 20, 30, 40, 60, 80, 90),
  colors = list(
    crayon::white,                              # LOWEST (boundary)
    crayon::silver,                             # TRACE
    crayon::cyan,                               # DEBUG
    crayon::green,                              # NOTE
    crayon::yellow,                             # MESSAGE
    crayon::red,                                # WARNING
    function(x) crayon::bold(crayon::red(x)),   # ERROR
    function(x) crayon::bold(crayon::red(x))    # CRITICAL + HIGHEST
  )
)

# Efficient color lookup function
get_log_color <- function(level_number) {
  idx <- findInterval(level_number, .LEVEL_COLOR_MAP$levels, rightmost.closed = TRUE)
  # findInterval returns 0 if level_number < min, so we need to handle that
  if (idx == 0) idx <- 1
  .LEVEL_COLOR_MAP$colors[[idx]]
}
