#' Global logger instance
#'
#' The default logger instance that is available when the package is loaded.
#' This is initialized as a dummy logger and can be configured by the user.
#'
#' @seealso [logger()], [dummy_logger()]
#' @export
log_this <- dummy_logger()

.onLoad <- function(libname, pkgname){

}
