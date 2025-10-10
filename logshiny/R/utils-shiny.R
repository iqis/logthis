# ==============================================================================
# Shiny Type Mapping Utilities
# ==============================================================================
# Internal utilities for mapping log levels to Shiny UI types

# Shiny Type Mapping
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
