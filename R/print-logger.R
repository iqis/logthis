#' Print method for logger objects
#'
#' Displays logger configuration including level limits and attached receivers
#'
#' @param x A logger object
#' @param ... Additional arguments passed to print (unused)
#' @return The logger object invisibly
#' @export
print.logger <- function(x, ...) {
  config <- attr(x, "config")
  
  cat("<logger>\n")
  cat("Level limits: ", config$limits$lower, " to ", config$limits$upper, "\n")
  
  if (length(config$receivers) == 0) {
    cat("Receivers: (none)\n")
  } else {
    cat("Receivers:\n")
    
    if (!is.null(config$receiver_calls)) {
      # Print the captured calls
      for (i in seq_along(config$receiver_calls)) {
        call_text <- deparse(config$receiver_calls[[i]], width.cutoff = 60L)
        if (length(call_text) > 1) {
          call_text <- paste(call_text[1], "...")
        }
        cat("  [", i, "] ", call_text, "\n", sep = "")
      }
    } else {
      # Fallback: show receiver classes if calls aren't available
      receiver_classes <- sapply(config$receivers, function(r) class(r)[1])
      for (i in seq_along(receiver_classes)) {
        cat("  [", i, "] ", receiver_classes[i], "\n", sep = "")
      }
    }
  }
  
  invisible(x)
}