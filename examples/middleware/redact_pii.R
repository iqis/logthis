# PII Redaction Middleware
#
# Demonstrates how to remove personally identifiable information (PII) from
# log messages before they reach receivers. Critical for GDPR, HIPAA, and other
# privacy regulations.

library(logthis)

# ==============================================================================
# Example 1: Credit Card Redaction
# ==============================================================================

#' Redact credit card numbers from log messages
#'
#' Matches common credit card patterns (Visa, Mastercard, Amex, Discover) and
#' replaces all but the last 4 digits with asterisks.
#'
#' @return middleware function
redact_credit_cards <- middleware(function(event) {
  # Pattern: 4 groups of 4 digits (with optional dashes/spaces)
  # Matches: 1234-5678-9012-3456, 1234 5678 9012 3456, 1234567890123456
  event$message <- gsub(
    "(\\d{4})[-\\s]?(\\d{4})[-\\s]?(\\d{4})[-\\s]?(\\d{4})",
    "****-****-****-\\4",
    event$message
  )

  event
})

# Usage example
log_this <- logger() %>%
  with_middleware(redact_credit_cards) %>%
  with_receivers(to_console())

log_this(NOTE("Payment processed: card 4532-1234-5678-9010"))
# Output: "Payment processed: card ****-****-****-9010"

# ==============================================================================
# Example 2: SSN/SIN Redaction
# ==============================================================================

#' Redact Social Security Numbers (US) and Social Insurance Numbers (Canada)
#'
#' @return middleware function
redact_ssn <- middleware(function(event) {
  # SSN pattern: 123-45-6789 or 123456789
  event$message <- gsub(
    "\\b\\d{3}-?\\d{2}-?\\d{4}\\b",
    "***-**-****",
    event$message
  )

  event
})

# ==============================================================================
# Example 3: Email Address Redaction
# ==============================================================================

#' Redact email addresses (keep domain for debugging)
#'
#' @return middleware function
redact_emails <- middleware(function(event) {
  # Pattern: anything@domain.com -> ***@domain.com
  event$message <- gsub(
    "\\b[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\\.[A-Za-z]{2,})\\b",
    "***@\\1",
    event$message
  )

  event
})

log_this <- logger() %>%
  with_middleware(redact_emails) %>%
  with_receivers(to_console())

log_this(WARNING("Failed login attempt: user.name@company.com"))
# Output: "Failed login attempt: ***@company.com"

# ==============================================================================
# Example 4: Comprehensive PII Redaction (Production-Ready)
# ==============================================================================

#' Production PII redaction middleware
#'
#' Combines multiple PII patterns for comprehensive protection. Suitable for
#' pharmaceutical audit trails, healthcare systems, and financial applications.
#'
#' Redacts:
#' - Credit card numbers (Visa, MC, Amex, Discover)
#' - SSN/SIN (US/Canada social security numbers)
#' - Email addresses (keeps domain)
#' - Phone numbers (US/Canada format)
#' - IP addresses (optional - preserves for security logs)
#'
#' @param redact_ips Logical; whether to redact IP addresses (default: FALSE)
#' @return middleware function
redact_all_pii <- function(redact_ips = FALSE) {
  middleware(function(event) {
    # Credit cards
    event$message <- gsub(
      "(\\d{4})[-\\s]?(\\d{4})[-\\s]?(\\d{4})[-\\s]?(\\d{4})",
      "****-****-****-\\4",
      event$message
    )

    # SSN/SIN
    event$message <- gsub(
      "\\b\\d{3}-?\\d{2}-?\\d{4}\\b",
      "***-**-****",
      event$message
    )

    # Email addresses
    event$message <- gsub(
      "\\b[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\\.[A-Za-z]{2,})\\b",
      "***@\\1",
      event$message
    )

    # Phone numbers (US/Canada: +1-234-567-8900, (234) 567-8900, etc.)
    event$message <- gsub(
      "\\+?1?[-\\s]?\\(?\\d{3}\\)?[-\\s]?\\d{3}[-\\s]?\\d{4}\\b",
      "***-***-****",
      event$message
    )

    # IP addresses (optional - may want to keep for security logs)
    if (redact_ips) {
      event$message <- gsub(
        "\\b(?:\\d{1,3}\\.){3}\\d{1,3}\\b",
        "***.***.***.***",
        event$message
      )
    }

    event
  })
}

# ==============================================================================
# Example 5: Custom Field Redaction
# ==============================================================================

#' Redact PII from custom fields (not just message)
#'
#' For structured logging where sensitive data may be in custom fields
#'
#' @param fields Character vector of field names to redact
#' @return middleware function
redact_custom_fields <- function(fields = c("user_email", "ssn", "credit_card")) {
  middleware(function(event) {
    for (field in fields) {
      if (!is.null(event[[field]])) {
        event[[field]] <- "[REDACTED]"
      }
    }
    event
  })
}

# Usage: Redact before logging
log_this <- logger() %>%
  with_middleware(
    redact_all_pii(redact_ips = FALSE),
    redact_custom_fields(fields = c("password", "api_key"))
  ) %>%
  with_receivers(
    to_console(),
    to_json() %>% on_local("audit.jsonl")
  )

log_this(WARNING(
  "Authentication failed",
  user_email = "john.doe@example.com",
  password = "secret123",
  ip_address = "192.168.1.100"
))
# Output: email redacted, password redacted, IP preserved

# ==============================================================================
# Example 6: Pharmaceutical/Clinical Use Case
# ==============================================================================

#' Redact patient identifiers (21 CFR Part 11 compliance)
#'
#' For pharmaceutical and clinical trial logging. Preserves study identifiers
#' while protecting patient identity.
#'
#' @return middleware function
redact_patient_identifiers <- middleware(function(event) {
  # Patient ID pattern: PT-12345, PATIENT-12345
  event$message <- gsub(
    "\\b(PT|PATIENT|SUBJECT)-?\\d+\\b",
    "[PATIENT-ID-REDACTED]",
    event$message,
    ignore.case = TRUE
  )

  # Date of birth (ISO format or US format)
  event$message <- gsub(
    "\\b\\d{4}-\\d{2}-\\d{2}\\b|\\b\\d{1,2}/\\d{1,2}/\\d{2,4}\\b",
    "[DOB-REDACTED]",
    event$message
  )

  # Medical record numbers (MRN-123456)
  event$message <- gsub(
    "\\bMRN[-:]?\\s?\\d+\\b",
    "[MRN-REDACTED]",
    event$message,
    ignore.case = TRUE
  )

  event
})

# Usage in clinical trial data pipeline
log_clinical <- logger() %>%
  with_middleware(
    redact_patient_identifiers,
    redact_all_pii(redact_ips = TRUE)
  ) %>%
  with_tags("GxP", "audit_trail") %>%
  with_receivers(
    to_json() %>% on_local("clinical_audit.jsonl"),
    to_text() %>% on_local("clinical_events.log")
  )

log_clinical(NOTE(
  "Data export completed",
  study_id = "TRIAL-2024-001",
  patient_count = 127,
  exported_by = "data.manager@pharma.com"
))
# Output: Email redacted, patient count preserved, study ID preserved
