# GxP Data Validation Integration with logthis

**Status:** Design concept
**Created:** 2025-10-10
**Compliance Standards:** 21 CFR Part 11, ALCOA+, ICH E6(R2), EU Annex 11

---

## Overview

Integration patterns for data validation frameworks with logthis to create comprehensive audit trails for pharmaceutical/GxP compliance.

### Key Compliance Requirements

**ALCOA+ Principles:**
- **A**ttributable - Who performed the validation?
- **L**egible - Clear, readable audit trail
- **C**ontemporaneous - Real-time logging of validation events
- **O**riginal - First recording of data
- **A**ccurate - Validation results must be precise
- **+** Complete, Consistent, Enduring, Available

**21 CFR Part 11:**
- Secure, computer-generated, time-stamped audit trails
- Record all validation events (create, modify, delete)
- Capture user identity and reason for change
- Electronic signatures support

---

## Pattern 1: {validate} + logthis

### Basic Integration

```r
library(validate)
library(logthis)

# GxP-compliant logger
log_gxp <- logger() %>%
  with_tags(system = "validation", regulation = "21CFR11") %>%
  with_receivers(
    # Immutable audit trail to S3
    to_json() %>% on_s3(
      bucket = "gxp-audit-trails",
      key = paste0("validation-", Sys.Date(), ".jsonl")
    ),
    # Real-time monitoring
    to_json() %>% on_cloudwatch(
      log_group = "/gxp/validation",
      log_stream = Sys.getenv("STUDY_ID")
    )
  )

# Define validation rules
rules <- validator(
  age_valid = age >= 18 & age <= 100,
  weight_positive = weight > 0,
  required_fields = !is.na(patient_id)
)

# Validation with audit trail
validate_with_audit <- function(data, rules, user_id, reason = NULL) {
  # Log validation start
  log_gxp(NOTE(
    "Validation started",
    user_id = user_id,
    reason = reason,
    n_records = nrow(data),
    n_rules = length(rules)
  ))

  # Run validation
  result <- confront(data, rules)

  # Extract results
  violations <- summary(result)

  # Log each rule result
  for (i in seq_len(nrow(violations))) {
    rule <- violations[i, ]

    log_event <- if (rule$fails > 0) {
      WARNING(
        paste("Validation rule failed:", rule$name),
        user_id = user_id,
        rule_name = rule$name,
        fails = rule$fails,
        passes = rule$passes,
        na_count = rule$nNA,
        expression = as.character(rule$expression)
      )
    } else {
      NOTE(
        paste("Validation rule passed:", rule$name),
        user_id = user_id,
        rule_name = rule$name,
        passes = rule$passes
      )
    }

    log_gxp(log_event)
  }

  # Log completion
  total_fails <- sum(violations$fails)
  log_gxp(if (total_fails > 0) {
    ERROR(
      "Validation completed with failures",
      user_id = user_id,
      total_fails = total_fails,
      total_passes = sum(violations$passes)
    )
  } else {
    NOTE(
      "Validation completed successfully",
      user_id = user_id,
      total_passes = sum(violations$passes)
    )
  })

  invisible(result)
}

# Usage
validate_with_audit(
  data = clinical_data,
  rules = rules,
  user_id = Sys.getenv("USER"),
  reason = "Protocol amendment validation"
)
```

**Audit Trail Output (JSON):**
```json
{"time":"2025-10-10T14:30:15Z","level":"NOTE","level_number":30,"message":"Validation started","user_id":"jdoe","reason":"Protocol amendment validation","n_records":500,"n_rules":3,"system":"validation","regulation":"21CFR11"}
{"time":"2025-10-10T14:30:16Z","level":"WARNING","level_number":60,"message":"Validation rule failed: age_valid","user_id":"jdoe","rule_name":"age_valid","fails":5,"passes":495,"na_count":0,"expression":"age >= 18 & age <= 100","system":"validation","regulation":"21CFR11"}
{"time":"2025-10-10T14:30:17Z","level":"ERROR","level_number":80,"message":"Validation completed with failures","user_id":"jdoe","total_fails":5,"total_passes":995,"system":"validation","regulation":"21CFR11"}
```

---

## Pattern 2: {pointblank} + logthis

### Advanced Integration with Reactive Validation

```r
library(pointblank)
library(logthis)

# Create validation agent with audit trail
create_gxp_agent <- function(tbl, study_id, user_id) {
  # Logger specific to this validation
  log_val <- logger() %>%
    with_tags(
      study_id = study_id,
      user_id = user_id,
      validation_type = "pointblank"
    ) %>%
    with_receivers(
      to_json() %>% on_s3(
        bucket = "clinical-audit-trails",
        key = paste0(study_id, "/validation-", Sys.Date(), ".jsonl")
      )
    )

  # Log agent creation
  log_val(NOTE(
    "Validation agent created",
    table_name = deparse(substitute(tbl)),
    n_rows = nrow(tbl),
    n_cols = ncol(tbl)
  ))

  agent <- create_agent(tbl = tbl) %>%
    # Add validation steps
    col_vals_not_null(vars(patient_id)) %>%
    col_vals_between(vars(age), 18, 100) %>%
    col_vals_in_set(vars(sex), c("M", "F")) %>%
    col_vals_regex(vars(patient_id), pattern = "^[A-Z]{3}-\\d{4}$") %>%

    # Custom action on validation
    action_levels(
      warn_at = 0.05,  # Warn if >5% fail
      stop_at = 0.10   # Stop if >10% fail
    )

  # Interrogate with logging
  agent <- interrogate(agent)

  # Extract validation results
  report <- get_agent_report(agent, display_mode = "none")

  # Log each validation step
  for (i in seq_len(nrow(report))) {
    step <- report[i, ]

    log_event <- if (step$f_failed > 0) {
      WARNING(
        paste("Validation step failed:", step$assertion_type),
        step_id = i,
        column = step$column,
        assertion = step$assertion_type,
        n_passed = step$n_passed,
        n_failed = step$n_failed,
        f_failed = step$f_failed
      )
    } else {
      NOTE(
        paste("Validation step passed:", step$assertion_type),
        step_id = i,
        column = step$column,
        n_passed = step$n_passed
      )
    }

    log_val(log_event)
  }

  # Log final status
  if (any(report$f_failed > 0.10)) {
    log_val(CRITICAL(
      "Validation failed - stopping processing",
      failed_steps = sum(report$f_failed > 0)
    ))
    stop("Validation failed critical threshold")
  }

  log_val(NOTE(
    "Validation completed",
    total_steps = nrow(report),
    failed_steps = sum(report$f_failed > 0),
    warning_steps = sum(report$f_failed > 0.05 & report$f_failed <= 0.10)
  ))

  agent
}

# Usage
agent <- create_gxp_agent(
  tbl = clinical_data,
  study_id = "STUDY-001",
  user_id = Sys.getenv("USER")
)
```

---

## Pattern 3: {arsenal} Dataset Comparison Audit Trail

### GxP-Compliant Reconciliation

```r
library(arsenal)
library(logthis)

# Compare datasets with full audit trail
compare_datasets_gxp <- function(old_data, new_data, user_id, reason) {
  log_reconcile <- logger() %>%
    with_tags(activity = "reconciliation", user_id = user_id) %>%
    with_receivers(
      to_json() %>% on_s3(
        bucket = "gxp-reconciliation",
        key = paste0("compare-", Sys.Date(), "-", format(Sys.time(), "%H%M%S"), ".jsonl")
      )
    )

  # Log comparison start
  log_reconcile(NOTE(
    "Dataset comparison started",
    reason = reason,
    old_rows = nrow(old_data),
    new_rows = nrow(new_data)
  ))

  # Run comparison
  comp <- comparedf(old_data, new_data)
  diffs <- summary(comp)

  # Log differences
  if (nrow(diffs$diffs.table) > 0) {
    for (i in seq_len(nrow(diffs$diffs.table))) {
      diff <- diffs$diffs.table[i, ]

      log_reconcile(WARNING(
        "Data discrepancy detected",
        variable = diff$var.x,
        observation = diff$observation,
        old_value = diff$values.x,
        new_value = diff$values.y,
        reason = reason
      ))
    }
  }

  # Log summary
  log_reconcile(NOTE(
    "Comparison completed",
    n_differences = nrow(diffs$diffs.table),
    n_variables_compared = length(diffs$vars.summary),
    match_rate = 1 - (nrow(diffs$diffs.table) / nrow(new_data))
  ))

  invisible(comp)
}

# Usage
compare_datasets_gxp(
  old_data = baseline_data,
  new_data = updated_data,
  user_id = "data_manager",
  reason = "Monthly data lock reconciliation"
)
```

---

## Pattern 4: Middleware for Automatic Validation Logging

### Transparent Validation Audit Trail

```r
# Middleware that logs validation events automatically
log_validation_events <- function(event) {
  # Check if event has validation metadata
  if (!is.null(event$validation_result)) {
    # Enhance event with validation details
    event$validation_status <- if (event$validation_result$passed) "PASS" else "FAIL"
    event$validation_rule_count <- length(event$validation_result$rules)
  }

  event
}

# Logger with validation middleware
log_gxp <- logger() %>%
  with_middleware(log_validation_events) %>%
  with_tags(compliance = "GxP", system = "validation") %>%
  with_receivers(
    to_json() %>% on_s3(bucket = "audit-trails", key = "validation.jsonl"),
    to_json() %>% on_cloudwatch(log_group = "/gxp/validation", log_stream = "main")
  )

# Validation function that emits rich events
validate_clinical_data <- function(data, rules, log_gxp) {
  result <- confront(data, rules)
  violations <- summary(result)

  # Emit event with validation metadata
  log_gxp(NOTE(
    "Validation completed",
    validation_result = list(
      passed = sum(violations$fails) == 0,
      rules = nrow(violations),
      total_fails = sum(violations$fails)
    ),
    dataset_hash = digest::digest(data)  # Data integrity check
  ))

  result
}
```

---

## Pattern 5: Electronic Signature Integration

### 21 CFR Part 11 Electronic Signatures

```r
library(logthis)

# Electronic signature function
esign_validation <- function(validation_result, user_id, password_hash, meaning) {
  log_esign <- logger() %>%
    with_tags(compliance = "21CFR11", activity = "esignature") %>%
    with_receivers(
      # Immutable audit trail
      to_json() %>% on_s3(
        bucket = "esignature-audit",
        key = paste0("esign-", Sys.Date(), ".jsonl")
      )
    )

  # Verify user credentials (simplified - use proper auth in production)
  if (!verify_credentials(user_id, password_hash)) {
    log_esign(ERROR(
      "Electronic signature failed - invalid credentials",
      user_id = user_id,
      timestamp = Sys.time()
    ))
    stop("Invalid credentials")
  }

  # Log electronic signature
  log_esign(NOTE(
    "Electronic signature applied",
    user_id = user_id,
    user_name = get_user_name(user_id),
    meaning = meaning,  # e.g., "Approved", "Reviewed", "Rejected"
    signed_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    validation_hash = digest::digest(validation_result),
    ip_address = get_client_ip()
  ))

  invisible(TRUE)
}

# Usage in validation workflow
result <- validate_with_audit(clinical_data, rules, user_id = "jdoe")

# Apply electronic signature
esign_validation(
  validation_result = result,
  user_id = "jdoe",
  password_hash = "...",
  meaning = "Data Validation Approved"
)
```

---

## Pharma-Specific Validation Packages

### Additional GxP Tools in R

1. **{admiral}** - ADaM dataset creation with validation
   - Built-in checks for CDISC compliance
   - Metadata validation
   - Used by: Roche, GSK, Novartis

2. **{datacutr}** - Clinical trial data cuts
   - Reproducible data snapshots
   - Built-in audit trail
   - Used by: Clinical trial sponsors

3. **{diffdf}** - Dataset comparison for pharma
   - GxP-focused reconciliation
   - Detailed difference reports

4. **{dataquieR}** - Data quality reporting
   - Comprehensive quality checks
   - Integration with validation frameworks

### Example: admiral + logthis

```r
library(admiral)
library(logthis)

# ADaM dataset creation with audit trail
log_adam <- logger() %>%
  with_tags(study = "STUDY-001", dataset = "ADSL") %>%
  with_receivers(
    to_json() %>% on_s3(bucket = "adam-audit", key = "adsl-creation.jsonl")
  )

# Log derivation steps
adsl <- dm %>%
  derive_vars_merged(
    dataset_add = ex,
    by_vars = vars(STUDYID, USUBJID)
  ) %>%
  # Log after each derivation
  (function(data) {
    log_adam(NOTE(
      "Derived treatment variables",
      n_subjects = n_distinct(data$USUBJID)
    ))
    data
  }) %>%
  derive_vars_dt(
    new_vars_prefix = "TRTS",
    dtc = EXSTDTC
  ) %>%
  (function(data) {
    log_adam(NOTE(
      "Derived treatment start date",
      n_with_date = sum(!is.na(data$TRTSDTM))
    ))
    data
  })

# Validate against CDISC
validation_result <- validate_admiral_dataset(adsl)
log_adam(NOTE(
  "CDISC validation completed",
  validation_passed = validation_result$passed,
  n_checks = validation_result$n_checks
))
```

---

## Best Practices for GxP Validation + Logging

### 1. Immutable Audit Trails
```r
# S3 with versioning enabled
to_json() %>% on_s3(
  bucket = "immutable-audit-trail",
  key = paste0("validation-", Sys.Date(), ".jsonl")
)

# CloudWatch with retention policy
to_json() %>% on_cloudwatch(
  log_group = "/gxp/validation",
  log_stream = Sys.getenv("STUDY_ID")
)
# Then set retention in AWS: 10 years
```

### 2. Capture Required Metadata
```r
# ALCOA+ compliant event
log_gxp(NOTE(
  "Validation performed",
  user_id = Sys.getenv("USER"),                 # Attributable
  user_name = get_ldap_name(Sys.getenv("USER")), # Attributable
  timestamp = Sys.time(),                        # Contemporaneous
  activity = "Data validation",                  # Legible
  reason = "Protocol amendment",                 # Complete
  dataset_hash = digest::digest(data),          # Accurate
  validation_version = packageVersion("validate"), # Enduring
  r_version = R.version.string,                 # Enduring
  system_info = Sys.info()["nodename"]          # Available
))
```

### 3. Validation Rule Versioning
```r
# Store validation rules with version control
rules_v1 <- validator(
  age >= 18,
  !is.na(patient_id)
)

log_gxp(NOTE(
  "Applying validation rules",
  rules_version = "v1.0",
  rules_hash = digest::digest(rules_v1),
  rules_count = length(rules_v1)
))
```

### 4. Change Control Documentation
```r
# Log all changes to validation rules
log_change_control <- function(old_rules, new_rules, change_reason, approver) {
  log_gxp(NOTE(
    "Validation rules updated",
    old_rules_hash = digest::digest(old_rules),
    new_rules_hash = digest::digest(new_rules),
    change_reason = change_reason,
    changed_by = Sys.getenv("USER"),
    approved_by = approver,
    change_date = Sys.Date()
  ))
}
```

---

## Compliance Reports from Audit Trails

### Generate Regulatory Reports

```r
# Query audit trail for compliance report
library(jsonlite)

# Read audit trail from S3
audit_data <- stream_in(file("s3://audit-trails/validation.jsonl"))

# Generate 21 CFR Part 11 compliant report
compliance_report <- audit_data %>%
  filter(activity == "validation") %>%
  select(
    timestamp = time,
    user = user_id,
    action = message,
    result = validation_status,
    details = validation_result
  ) %>%
  arrange(timestamp)

# Export for regulatory submission
write.csv(compliance_report, "21CFR11_Validation_Report.csv")
```

---

## Validation Framework Comparison

| Framework | Pharma Adoption | GxP Features | logthis Integration |
|-----------|----------------|--------------|---------------------|
| **{validate}** | High | Rule versioning, comprehensive reports | ⭐⭐⭐ Excellent |
| **{pointblank}** | Medium | Modern, database support | ⭐⭐⭐ Excellent |
| **{arsenal}** | High | Mayo Clinic developed, reconciliation | ⭐⭐ Good |
| **{admiral}** | Very High | CDISC-specific, pharma-focused | ⭐⭐⭐ Excellent |
| **{diffdf}** | Medium | Dataset comparison | ⭐⭐ Good |

---

## Recommended Approach for GxP

1. **Use {validate} for core validation**
   - Industry standard
   - Well-documented
   - Easy to integrate with logthis

2. **Use {admiral} for CDISC datasets**
   - Purpose-built for clinical trials
   - Has built-in validation

3. **Use logthis for audit trail**
   - Captures all validation events
   - Immutable storage (S3, CloudWatch)
   - ALCOA+ compliant metadata

4. **Combine all three:**
```r
# Complete GxP validation pipeline
library(validate)
library(admiral)
library(logthis)

# GxP logger
log_gxp <- logger() %>%
  with_tags(
    system = "validation",
    compliance = "21CFR11",
    study = "STUDY-001"
  ) %>%
  with_receivers(
    to_json() %>% on_s3(bucket = "gxp-audit", key = "validation.jsonl"),
    to_json() %>% on_cloudwatch(log_group = "/gxp", log_stream = "validation")
  )

# Define rules
rules <- validator(...)

# Validate with audit
result <- validate_with_audit(
  data = adsl,
  rules = rules,
  user_id = "data_manager",
  log_gxp = log_gxp
)

# Electronic signature
esign_validation(result, user_id = "reviewer", meaning = "Approved")
```

---

## Next Steps

1. Create example vignette: `vignettes/gxp-validation.Rmd`
2. Add helper functions: `validate_with_audit()`, `esign_validation()`
3. Document ALCOA+ metadata requirements
4. Provide CDISC validation examples
5. Create compliance report templates
