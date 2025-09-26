# Dummy receivers, mainly for testing
#' @export
to_identity <- function(){
  structure(function(event){
    event
  },
  class = c("log_receiver",
            "function"))
}

#' @export
to_void <- function(){
  structure(function(event){
    invisible(NULL)
  },
  class = c("log_receiver",
            "function"))
}

#' @export
to_console <- function(min_level = LOWEST,
                       max_level = HIGHEST){
  structure(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(min_level, "level_number") <= event$level_number &&
          event$level_number < attr(max_level, "level_number")) {

        log_color <- function(level_number){
          level_color_lookup <-
            tibble::tibble(level_number = seq(0, 100, 20),
                           crayon_f = list(crayon::white,
                                           crayon::silver,
                                           crayon::green,
                                           crayon::yellow,
                                           crayon::red,
                                           purrr::compose(crayon::red, crayon::bold)))
          for (i in 1:nrow(level_color_lookup)) {
            if (level_color_lookup$level_number[i] >= level_number) {
              res <- level_color_lookup$crayon_f[[i]]
              break
            }
          }
          res
        }

        with(event,
             cat(log_color(level_number)(paste0(time, " ",
                                                "[", level_class, "]", " ",
                                                message,
                                                "\n"))))
      }
      event
      },
      class = c("log_receiver",
              "function"))
}

to_shinyalert <- function(lower = WARNING, upper = HIGHEST, ...){
  structure(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number < attr(upper, "level_number")) {

        # TODO: add level lookup table

        shinyalert::shinyalert(text = event$message,
                               type = "error",
                               ...)
      }
      event
    },
    class = c("log_receiver",
              "function"))
}

to_notif <- function(lower = NOTE, upper = WARNING, ...){
  structure(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number < attr(upper, "level_number")) {


        # TODO: build event level mapping
        shiny::showNotification(event$message,
                                ...)
      }
      event
    },
    class = c("log_receiver",
              "function"))
}

to_text_file <- function(lower = LOWEST,
                         upper = HIGHEST,
                         path = "log.txt",
                         append = FALSE, ...){
  stopifnot(is.character(path),
            is.logical(append))

  if (!append) {
    unlink(path)
  }

  con <- file(path)

  structure(
    function(event){
      `if`(!inherits(event, "log_event"),
           stop("`event` must be of class `log_event`"))

      if (attr(lower, "level_number") <= event$level_number &&
          event$level_number < attr(upper, "level_number")) {

        with(event,
             cat(paste0(time, " ",
                        "[", level_class, "]", " ",
                        message,
                        "\n"),
                 file = path,
                 append = TRUE))
      }
      event
    },
    class = c("log_receiver",
              "function"))
}

