#' Global logger instance
#'
#' The default logger instance that is available when the package is loaded.
#' This is initialized as a void logger and can be configured by the user.
#'
#' @param event A log event created by event level functions like NOTE(), WARNING(), etc.
#' @param ... Additional arguments passed to the logger
#' @seealso [logger()], [void_logger()]
#' @export
log_this <- void_logger()

.onLoad <- function(libname, pkgname){

}
