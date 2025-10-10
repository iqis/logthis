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

# ==============================================================================
# Intent-Based Function Index
# Machine-parseable metadata for AI assistants
# ==============================================================================
#
# Format: intent → functions
# Intents are natural language descriptions of what user wants to do
#
# @intent Create a logger
# @functions logger(), void_logger()
# @file R/logger.R
#
# @intent Log an event to console
# @functions to_console(), logger(), with_receivers(), NOTE(), ERROR(), etc.
# @files R/receivers.R, R/logger.R, R/log_event_levels.R
#
# @intent Log an event to file
# @functions to_text(), to_json(), on_local()
# @files R/receivers.R
#
# @intent Rotate log files by size
# @functions on_local(max_size, max_files)
# @files R/receivers.R
#
# @intent Log to cloud storage (S3, Azure)
# @functions to_json(), on_s3(), on_azure()
# @files R/receivers.R
#
# @intent Filter events by log level
# @functions with_limits(), with_limits.logger(), with_limits.log_receiver()
# @files R/logger.R, R/receivers.R
#
# @intent Add tags to events
# @functions with_tags(), log_event(..., tags = ...)
# @files R/logger.R, R/log_events.R
#
# @intent Add custom fields to events
# @functions log_event(message, ...), NOTE(...), ERROR(...), etc.
# @files R/log_events.R, R/log_event_levels.R
#
# @intent Format logs as text
# @functions to_text(template)
# @files R/receivers.R
#
# @intent Format logs as JSON
# @functions to_json(), to_json_file()
# @files R/receivers.R
#
# @intent Create custom log level
# @functions log_event_level(name, number)
# @files R/log_event_levels.R
# @template .claude/templates/custom-level.R
#
# @intent Create custom formatter
# @functions formatter(func), to_text(), to_json()
# @files R/receivers.R
# @template .claude/templates/custom-formatter.R
#
# @intent Create custom handler (storage destination)
# @functions on_local(), on_s3(), on_azure()
# @files R/receivers.R
# @template .claude/templates/custom-handler.R
#
# @intent Create custom receiver (standalone)
# @functions receiver(func), to_console(), to_identity(), to_void()
# @files R/receivers.R
# @template .claude/templates/custom-receiver.R
#
# @intent Log to multiple destinations
# @functions with_receivers(...), logger()
# @files R/logger.R
#
# @intent Configure different receivers for different levels
# @functions to_console(lower, upper), with_limits.log_receiver()
# @files R/receivers.R
#
# @intent Enhance logger in specific scope
# @functions with_receivers(..., append = TRUE), logger()
# @files R/logger.R
# @pattern Scope-Based Enhancement (vignettes/patterns.Rmd)
#
# @intent Log in data pipeline
# @functions logger()(event), magrittr pipe
# @files R/logger.R
# @pattern Pipeline Logging (vignettes/patterns.Rmd)
#
# @intent Disable logging for performance
# @functions void_logger()
# @files R/logger.R
#
# @intent Handle receiver failures gracefully
# @description Built-in behavior, no special setup needed
# @files R/logger.R (execute_receivers)
#
# @intent Debug logger configuration
# @functions print.logger(), attr(logger, "config")
# @files R/logger.R
#
# @intent Create event with specific level
# @functions TRACE(), DEBUG(), NOTE(), MESSAGE(), WARNING(), ERROR(), CRITICAL()
# @files R/log_event_levels.R
#
# @intent Compare log levels
# @functions log_event_level comparison operators (>, <, >=, <=, ==, !=)
# @files R/log_event_levels.R
#
# @intent Access event fields
# @description event$time, event$level_class, event$level_number, event$message, event$tags
# @files R/log_events.R
#
# @intent Configure logging from YAML
# @description Use config package with setup function
# @files scratch.md (Config Management Integration)
# @pattern Config-Driven Setup (vignettes/patterns.Rmd)
#
# ==============================================================================
# Type Signatures (Informal)
# ==============================================================================
#
# logger() -> logger
# void_logger() -> logger
# with_receivers(logger, ...) -> logger
# with_limits(logger, lower = log_event_level, upper = log_event_level) -> logger
# with_tags(logger, ...) -> logger
#
# log_event(message: string, ...) -> log_event
# log_event_level(name: string, number: numeric) -> log_event_level
#
# formatter(func: function(log_event) -> string) -> log_formatter
# to_text(template: string) -> log_formatter
# to_json(pretty: logical) -> log_formatter
#
# on_local(log_formatter, path: string, ...) -> log_formatter
# on_s3(log_formatter, bucket: string, key: string, ...) -> log_formatter
# on_azure(log_formatter, container: string, blob: string, ...) -> log_formatter
#
# receiver(func: function(log_event) -> NULL) -> log_receiver
# to_console(lower: log_event_level, upper: log_event_level) -> log_receiver
# to_identity() -> log_receiver
# to_void() -> log_receiver
#
# with_limits.log_receiver(log_receiver, lower, upper) -> log_receiver
# with_limits.log_formatter(log_formatter, lower, upper) -> log_formatter
#
# ==============================================================================
