NULL

# Suppress R CMD check NOTE for variables used in non-standard evaluation contexts
# receiver_func: Used in mirai closures in as_async() and deferred()
utils::globalVariables("receiver_func")

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
# All mappings follow SEMANTIC consistency (not console color matching):
#   - 0-29 (TRACE/DEBUG): info/default/debug (informational)
#   - 30-39 (NOTE): success/message/log (positive confirmation)
#   - 40-59 (MESSAGE): info/message/log (informational)
#   - 60-79 (WARNING): warning/warn (caution needed)
#   - 80+ (ERROR/CRITICAL): error/error (failure)
.SHINY_TYPE_MAP <- list(
  # shinyalert types: "info", "success", "warning", "error"
  shinyalert = list(
    levels = c(0, 20, 30, 40, 60, 80),
    types = c("info",     # LOWEST-TRACE (0-19): info (blue)
              "info",     # DEBUG (20-29): info (blue)
              "success",  # NOTE (30-39): success (green)
              "info",     # MESSAGE (40-59): info (blue)
              "warning",  # WARNING (60-79): warning (yellow)
              "error")    # ERROR-HIGHEST (80+): error (red)
  ),
  # shiny::showNotification types: "default", "message", "warning", "error"
  notif = list(
    levels = c(0, 20, 30, 40, 60, 80),
    types = c("default",  # LOWEST-TRACE (0-19): default (gray)
              "default",  # DEBUG (20-29): default (gray)
              "message",  # NOTE (30-39): message (blue)
              "message",  # MESSAGE (40-59): message (blue)
              "warning",  # WARNING (60-79): warning (yellow)
              "error")    # ERROR-HIGHEST (80+): error (red)
  ),
  # shinyWidgets::sendSweetAlert types: "info", "success", "warning", "error"
  # SweetAlert2 modal alerts - same semantic mapping as shinyalert
  sweetalert = list(
    levels = c(0, 20, 30, 40, 60, 80),
    types = c("info",     # LOWEST-TRACE: info (blue)
              "info",     # DEBUG: info (blue)
              "success",  # NOTE: success (green)
              "info",     # MESSAGE: info (blue)
              "warning",  # WARNING: warning (yellow)
              "error")    # ERROR+: error (red)
  ),
  # shinyWidgets::show_toast types: "default", "success", "error", "info", "warning", "question"
  # Toast notifications - semantic mapping
  show_toast = list(
    levels = c(0, 20, 30, 40, 60, 80),
    types = c("info",     # LOWEST-TRACE: info (blue)
              "info",     # DEBUG: info (blue)
              "success",  # NOTE: success (green)
              "info",     # MESSAGE: info (blue)
              "warning",  # WARNING: warning (yellow)
              "error")    # ERROR+: error (red)
  ),
  # shinytoastr types: "success", "info", "warning", "error"
  # toastr.js toast notifications - semantic mapping
  toastr = list(
    levels = c(0, 20, 30, 40, 60, 80),
    types = c("info",     # LOWEST-TRACE: info (blue)
              "info",     # DEBUG: info (blue)
              "success",  # NOTE: success (green)
              "info",     # MESSAGE: info (blue)
              "warning",  # WARNING: warning (yellow)
              "error")    # ERROR+: error (red)
  ),
  # Browser console.* methods: "debug", "log", "warn", "error"
  # JavaScript console output - semantic mapping
  js_console = list(
    levels = c(0, 20, 30, 60, 80),
    methods = c("debug",  # LOWEST-DEBUG (0-29): console.debug()
                "log",    # NOTE-MESSAGE (30-59): console.log()
                "warn",   # WARNING (60-79): console.warn()
                "error")  # ERROR+ (80+): console.error()
  )
)

# Get Shiny type/method for a given log level
# @param level_number Numeric log level (0-100)
# @param receiver_type One of: "shinyalert", "notif", "sweetalert", "show_toast", "toastr", "js_console"
# @return Character string with type or method name
get_shiny_type <- function(level_number, receiver_type = c("shinyalert", "notif", "sweetalert", "show_toast", "toastr", "js_console")) {
  receiver_type <- match.arg(receiver_type)
  map <- .SHINY_TYPE_MAP[[receiver_type]]

  idx <- findInterval(level_number, map$levels, rightmost.closed = FALSE)
  if (idx == 0) idx <- 1

  # js_console uses "methods" key, others use "types"
  if (receiver_type == "js_console") {
    map$methods[[idx]]
  } else {
    map$types[[idx]]
  }
}
