#' Global logger instance
#'
#' The default logger instance that is available when the package is loaded.
#' This is initialized as a dummy logger and can be configured by the user.
#'
#' @param event A log event created by event level functions like NOTE(), WARNING(), etc.
#' @param ... Additional arguments passed to the logger
#' @seealso [logger()], [dummy_logger()]
#' @export
log_this <- dummy_logger()

.onLoad <- function(libname, pkgname){

}
