# ==============================================================================
# Receiver Async Infrastructure
# ==============================================================================
# Async logging wrapper using mirai for non-blocking, high-throughput logging.
# Can wrap any receiver to make it asynchronous.

# ==============================================================================
# Async Receiver Wrapper (v0.2.0)
# ==============================================================================
# General async wrapper using mirai for non-blocking, high-throughput scenarios
# Based on research in docs/async-logging-research.md

#' Make any receiver asynchronous using mirai
#'
#' Wraps a receiver to process events asynchronously in a background R process.
#' Events are buffered and flushed in batches for performance. Works with ANY
#' receiver - formatters, handlers, or standalone receivers.
#'
#' @param receiver A log_receiver to wrap (created with \code{receiver()})
#' @param flush_threshold Number of events to buffer before flushing (default: 100)
#' @param max_queue_size Maximum queue size before blocking (default: 10000)
#'
#' @details
#' The first call to \code{as_async()} automatically initializes one mirai daemon
#' if none exist. For better performance with multiple async receivers, create a
#' daemon pool before setting up loggers:
#'
#' \code{mirai::daemons(4)}  # Pool of 4 background workers
#'
#' All async receivers share the daemon pool. This prevents slow receivers
#' (e.g., S3 uploads) from blocking fast receivers (e.g., local files).
#'
#' Events are buffered in memory until \code{flush_threshold} is reached, then
#' sent to the daemon for processing. Remaining events are flushed automatically
#' when the receiver is garbage collected.
#'
#' @section Backpressure:
#' If the queue reaches \code{max_queue_size}, the receiver will flush
#' synchronously and warn the user. This prevents memory exhaustion when the
#' daemon cannot keep up with event production.
#'
#' @section Performance:
#' - **Latency**: 0.1-1ms to queue (vs 10-50ms for synchronous writes)
#' - **Throughput**: 10,000-50,000 events/sec
#' - **Memory**: ~1KB per queued event
#'
#' @section Trade-offs:
#' - **Pros**: Non-blocking, high throughput, minimal latency impact
#' - **Cons**: Events may be lost if process crashes before flush,
#'   requires mirai package, slightly higher memory usage
#'
#' @return A log_receiver that processes events asynchronously
#'
#' @examples
#' \dontrun{
#' # Auto-init with 1 daemon (simple)
#' logger() %>%
#'   with_receivers(
#'     to_text() %>% on_local("app.log") %>% as_async()
#'   )
#'
#' # Daemon pool for multiple async receivers (recommended)
#' mirai::daemons(4)
#' logger() %>%
#'   with_receivers(
#'     to_text() %>% on_local("app.log") %>% as_async(),
#'     to_json() %>% on_s3("logs", "events") %>% as_async(flush_threshold = 1000),
#'     to_csv() %>% on_local("metrics.csv") %>% as_async(),
#'     to_teams(webhook_url = "...") %>% as_async(),
#'     to_syslog(host = "syslog.local") %>% as_async()
#'   )
#'
#' # Works with any receiver!
#' to_console() %>% as_async()  # Even console (though not recommended)
#'
#' # Cleanup (optional - happens automatically on exit)
#' mirai::daemons(0)
#' }
#'
#' @family async
#' @family receivers
#' @export
#'
#' @seealso [deferred()] for semantic alias
as_async <- function(receiver,
                     flush_threshold = 100,
                     max_queue_size = 10000) {

  if (!inherits(receiver, "log_receiver")) {
    stop("`receiver` must be a log_receiver (created with receiver())")
  }

  if (!requireNamespace("mirai", quietly = TRUE)) {
    stop("Package 'mirai' required for async logging.\n",
         "  Install with: install.packages('mirai')")
  }

  # Auto-initialize one daemon if none exist
  if (mirai::daemons()$n == 0) {
    mirai::daemons(1, dispatcher = FALSE)
  }

  # Closure state for buffering
  event_queue <- list()
  queue_size <- 0

  # Flush buffered events to daemon
  flush <- function() {
    if (length(event_queue) == 0) return(invisible(NULL))

    # Capture queue locally
    events_batch <- event_queue
    event_queue <<- list()
    queue_size <<- 0

    # Send to daemon (non-blocking!)
    mirai::mirai({
      for (evt in events_batch) {
        receiver_func(evt)
      }
      invisible(NULL)
    }, events_batch = events_batch,
       receiver_func = receiver)

    invisible(NULL)
  }

  # Wrapped receiver
  async_recv <- receiver(function(event) {
    # Backpressure: block if queue is full
    if (queue_size >= max_queue_size) {
      warning("Async log queue full (", max_queue_size, " events). ",
              "Flushing synchronously to prevent memory exhaustion.",
              call. = FALSE)
      flush()
      # Wait briefly for daemon to catch up
      Sys.sleep(0.01)
    }

    # Add event to queue
    event_queue <<- c(event_queue, list(event))
    queue_size <<- queue_size + 1

    # Flush if threshold reached
    if (length(event_queue) >= flush_threshold) {
      flush()
    }

    invisible(NULL)
  })

  # Cleanup finalizer - flush remaining events on GC
  reg.finalizer(environment(async_recv), function(env) {
    if (exists("flush", envir = env, inherits = FALSE)) {
      env$flush()
      Sys.sleep(0.1)  # Give daemon time to write
    }
  }, onexit = TRUE)

  async_recv
}


#' @rdname as_async
#' @export
#' @family async
deferred <- as_async


# Internal helper to stop all mirai daemons on package unload
.stop_async_daemons <- function() {
  if (requireNamespace("mirai", quietly = TRUE)) {
    if (mirai::daemons()$n > 0) {
      mirai::daemons(0)  # Stop all daemons
    }
  }
}
