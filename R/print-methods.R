#' Print method for logger objects
#'
#' @param x A logger object
#' @param ... Additional arguments (ignored)
#' @export
print.logger <- function(x, ...) {
  config <- attr(x, "config")
  
  cat("Logger Configuration:\n")
  cat("===================\n")
  
  # Show level limits with level names if possible
  lower_name <- get_level_name(config$limits$lower)
  upper_name <- get_level_name(config$limits$upper)
  
  cat(sprintf("Level Limits: %s (%d) to %s (%d)\n", 
              lower_name, config$limits$lower,
              upper_name, config$limits$upper))
  
  # Show receivers
  num_receivers <- length(config$receivers)
  cat(sprintf("Receivers: %d attached\n", num_receivers))
  
  if (num_receivers > 0) {
    cat("\nReceiver Details:\n")
    for (i in seq_along(config$receivers)) {
      receiver <- config$receivers[[i]]
      receiver_type <- identify_receiver_type(receiver)
      
      cat(sprintf("  [%d] %s\n", i, receiver_type))
    }
  } else {
    cat("  (no receivers attached - events will be discarded)\n")
  }
  
  cat("\nUsage: logger_object(log_event)\n")
  cat("Example: log_this(NOTE(\"Application started\"))\n")
  invisible(x)
}

# Helper function to get level name from number
get_level_name <- function(level_number) {
  level_map <- list(
    "0" = "LOWEST",
    "20" = "CHATTER", 
    "40" = "NOTE",
    "60" = "MESSAGE",
    "80" = "WARNING",
    "100" = "ERROR",
    "120" = "HIGHEST"
  )
  
  level_map[[as.character(level_number)]] %||% "CUSTOM"
}

# Helper function to identify receiver type from class and structure
identify_receiver_type <- function(receiver) {
  classes <- class(receiver)
  
  if (!"log_receiver" %in% classes) {
    return("Custom function (not a log_receiver)")
  }
  
  # Try to identify by examining the function body
  func_body <- deparse(body(receiver))
  
  if (any(grepl("crayon::", func_body)) || any(grepl("cat\\(", func_body))) {
    return("Console receiver (to_console)")
  } else if (any(grepl("shinyalert::", func_body))) {
    return "Shiny alert receiver (to_shinyalert)"
  } else if (any(grepl("shiny::showNotification", func_body))) {
    return("Notification receiver (to_notif)")
  } else if (any(grepl("file\\(", func_body)) || any(grepl("writeLines", func_body))) {
    return("File receiver (to_text_file)")
  } else if (any(grepl("^\\s*event\\s*$", func_body))) {
    return("Identity receiver (to_identity)")
  } else if (any(grepl("invisible\\(event\\)", func_body)) && length(func_body) < 5) {
    return("Void receiver (to_void)")
  } else {
    return("Custom log_receiver")
  }
}

# Helper function for null coalescing
`%||%` <- function(x, y) if (is.null(x)) y else x