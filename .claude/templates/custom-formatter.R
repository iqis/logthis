# Template: Custom Formatter
# Purpose: Define new output format (CSV, XML, custom text, etc.)
# Pattern: Formatter defines HOW events are formatted

# Step 1: Define formatter function
# Parameters: Configuration for the format (template, options, etc.)
to_MYFORMAT <- function(option1 = "default",
                        option2 = TRUE) {

  # Step 2: Create formatter closure
  # The closure receives log_event and returns formatted string
  fmt_func <- formatter(function(event) {

    # Step 3: Extract fields from event
    # Standard fields:
    time <- event$time                    # POSIXct timestamp
    level <- event$level_class            # e.g., "NOTE", "ERROR"
    level_number <- event$level_number    # e.g., 30, 80
    message <- event$message              # string

    # Optional fields:
    tags <- if (!is.null(event$tags) && length(event$tags) > 0) {
      event$tags  # character vector
    } else {
      character(0)
    }

    # Custom fields (anything passed to log_event(...))
    custom_fields <- setdiff(names(event),
                             c("time", "level_class", "level_number",
                               "message", "tags"))

    # Step 4: Format according to your specification
    # Example: CSV format
    formatted <- paste(
      as.character(time),
      level,
      level_number,
      message,
      paste(tags, collapse = ";"),
      sep = ","
    )

    # Add custom fields if present
    if (length(custom_fields) > 0) {
      custom_values <- sapply(custom_fields, function(field) {
        as.character(event[[field]])
      })
      formatted <- paste0(formatted, ",", paste(custom_values, collapse = ","))
    }

    formatted
  })

  # Step 5: Set config attribute
  # IMPORTANT: Must include these fields
  attr(fmt_func, "config") <- list(
    format_type = "myformat",          # Unique identifier for this format
    backend = NULL,                     # Will be set by on_xxx() handler
    backend_config = list(),            # Will be set by on_xxx() handler
    lower = NULL,                       # Optional: level filtering
    upper = NULL,                       # Optional: level filtering
    option1 = option1,                  # Store formatter-specific config
    option2 = option2
  )

  # Step 6: Return formatter
  # Auto-inherits 'log_formatter' class from formatter()
  fmt_func
}

# ============================================================================
# Example: XML formatter
# ============================================================================

to_xml <- function(pretty = FALSE) {
  fmt_func <- formatter(function(event) {
    indent <- if (pretty) "  " else ""
    nl <- if (pretty) "\n" else ""

    xml <- paste0(
      "<event>", nl,
      indent, "<time>", event$time, "</time>", nl,
      indent, "<level name=\"", event$level_class, "\" number=\"", event$level_number, "\"/>", nl,
      indent, "<message>", event$message, "</message>", nl
    )

    # Add tags
    if (!is.null(event$tags) && length(event$tags) > 0) {
      xml <- paste0(xml, indent, "<tags>", nl)
      for (tag in event$tags) {
        xml <- paste0(xml, indent, indent, "<tag>", tag, "</tag>", nl)
      }
      xml <- paste0(xml, indent, "</tags>", nl)
    }

    # Add custom fields
    custom_fields <- setdiff(names(event),
                             c("time", "level_class", "level_number",
                               "message", "tags"))
    if (length(custom_fields) > 0) {
      xml <- paste0(xml, indent, "<custom>", nl)
      for (field in custom_fields) {
        xml <- paste0(xml, indent, indent, "<", field, ">",
                      event[[field]], "</", field, ">", nl)
      }
      xml <- paste0(xml, indent, "</custom>", nl)
    }

    xml <- paste0(xml, "</event>")
    xml
  })

  attr(fmt_func, "config") <- list(
    format_type = "xml",
    backend = NULL,
    backend_config = list(),
    lower = NULL,
    upper = NULL,
    pretty = pretty
  )

  fmt_func
}

# ============================================================================
# Usage Examples
# ============================================================================

# Example 1: Use with local file
if (FALSE) {
  library(logthis)

  log_this <- logger() %>%
    with_receivers(
      to_xml(pretty = TRUE) %>%
        on_local("events.xml")
    )

  log_this(NOTE("Application started", version = "1.2.3"))
  log_this(ERROR("Connection failed", host = "db.example.com", port = 5432))
}

# Example 2: Use with S3
if (FALSE) {
  library(logthis)

  log_this <- logger() %>%
    with_receivers(
      to_xml() %>%
        on_s3(bucket = "logs",
              key = "app/events.xml",
              region = "us-east-1")
    )
}

# Example 3: Create CSV formatter
if (FALSE) {
  to_csv <- function(delimiter = ",", quote = TRUE) {
    fmt_func <- formatter(function(event) {
      fields <- c(
        as.character(event$time),
        event$level_class,
        as.character(event$level_number),
        event$message
      )

      if (quote) {
        fields <- paste0("\"", gsub("\"", "\\\"", fields), "\"")
      }

      paste(fields, collapse = delimiter)
    })

    attr(fmt_func, "config") <- list(
      format_type = "csv",
      backend = NULL,
      backend_config = list(),
      lower = NULL,
      upper = NULL,
      delimiter = delimiter,
      quote = quote
    )

    fmt_func
  }

  log_this <- logger() %>%
    with_receivers(
      to_csv() %>% on_local("events.csv")
    )

  log_this(NOTE("CSV formatted event"))
}

# ============================================================================
# Integration Checklist
# ============================================================================

# □ Formatter function created (to_xxx)
# □ Takes configuration parameters (template, options, etc.)
# □ Returns formatter(function(event) {...})
# □ Extracts standard fields: time, level_class, level_number, message, tags
# □ Handles custom fields gracefully
# □ Sets config attribute with format_type
# □ Tested with on_local()
# □ Tested with on_s3() or on_azure()
# □ Added documentation (roxygen2)
# □ Added tests (testthat)
