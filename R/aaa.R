NULL

# Null-coalescing operator (returns rhs if lhs is NULL)
`%||%` <- function(lhs, rhs) {
  if (is.null(lhs)) rhs else lhs
}

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
# ANSI escape codes for terminal colors (replaces crayon dependency)
# Maps to levels: LOWEST(0), TRACE(10), DEBUG(20), NOTE(30), MESSAGE(40), WARNING(60), ERROR(80), CRITICAL(90), HIGHEST(100)
.LEVEL_COLOR_MAP <- list(
  levels = c(0, 10, 20, 30, 40, 60, 80, 90),
  colors = list(
    function(x) paste0("\033[97m", x, "\033[39m"),   # white (LOWEST)
    function(x) paste0("\033[90m", x, "\033[39m"),   # bright black/silver (TRACE)
    function(x) paste0("\033[36m", x, "\033[39m"),   # cyan (DEBUG)
    function(x) paste0("\033[32m", x, "\033[39m"),   # green (NOTE)
    function(x) paste0("\033[33m", x, "\033[39m"),   # yellow (MESSAGE)
    function(x) paste0("\033[31m", x, "\033[39m"),   # red (WARNING)
    function(x) paste0("\033[1;31m", x, "\033[0m"),  # bold red (ERROR)
    function(x) paste0("\033[1;31m", x, "\033[0m")   # bold red (CRITICAL + HIGHEST)
  )
)

# Efficient color lookup function
get_log_color <- function(level_number) {
  idx <- findInterval(level_number, .LEVEL_COLOR_MAP$levels, rightmost.closed = TRUE)
  # findInterval returns 0 if level_number < min, so we need to handle that
  if (idx == 0) idx <- 1
  .LEVEL_COLOR_MAP$colors[[idx]]
}

# Package-level constant for built-in event levels
# Used to protect standard levels from modification (e.g., via with_tags)
# Custom levels (created via log_event_level()) are not in this list
.BUILTIN_LEVELS <- c(
  "LOWEST",    # 0
  "TRACE",     # 10
  "DEBUG",     # 20
  "NOTE",      # 30
  "MESSAGE",   # 40
  "WARNING",   # 60
  "ERROR",     # 80
  "CRITICAL",  # 90
  "HIGHEST"    # 100
)

# Package-level constant for Shiny notification type mapping
# Maps log event levels to Shiny alert/notification types
# Used by to_shinyalert() and to_notif() receivers
.SHINY_TYPE_MAP <- list(
  # shinyalert types: "info", "success", "warning", "error"
  # Level ranges map to visual urgency
  shinyalert = list(
    levels = c(0, 20, 30, 40, 60, 80),  # Thresholds
    types = c("info",     # LOWEST-TRACE (0-19): info
              "info",     # DEBUG (20-29): info
              "success",  # NOTE (30-39): success
              "info",     # MESSAGE (40-59): info
              "warning",  # WARNING (60-79): warning
              "error")    # ERROR-HIGHEST (80+): error
  ),
  # shiny::showNotification types: "default", "message", "warning", "error"
  # More granular mapping for inline notifications
  notif = list(
    levels = c(0, 20, 30, 40, 60, 80),  # Thresholds
    types = c("default",  # LOWEST-TRACE (0-19): default
              "default",  # DEBUG (20-29): default
              "message",  # NOTE (30-39): message
              "message",  # MESSAGE (40-59): message
              "warning",  # WARNING (60-79): warning
              "error")    # ERROR-HIGHEST (80+): error
  )
)

# Get Shiny type for a given log level
# @param level_number Numeric log level (0-100)
# @param receiver_type Either "shinyalert" or "notif"
# @return Character string with Shiny type
get_shiny_type <- function(level_number, receiver_type = c("shinyalert", "notif")) {
  receiver_type <- match.arg(receiver_type)
  map <- .SHINY_TYPE_MAP[[receiver_type]]

  idx <- findInterval(level_number, map$levels, rightmost.closed = TRUE)
  if (idx == 0) idx <- 1

  map$types[[idx]]
}
