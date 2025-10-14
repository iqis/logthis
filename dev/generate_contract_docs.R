#!/usr/bin/env Rscript
#' Generate Contract Documentation from Code
#'
#' This script extracts contracts from code and generates markdown documentation.
#' Single source of truth: contracts in R/*.R files
#' Derived documentation: inst/contracts.md (generated, do not edit manually)
#'
#' Run: Rscript dev/generate_contract_docs.R

# No need to library(logthis) - we use devtools::load_all() below

#' Extract all contracts from package
#'
#' Loads package and executes all functions with contracts to populate registry
extract_contracts <- function() {
  # Load package to register contracts
  devtools::load_all(".")

  # Get all exported functions
  exports <- getNamespaceExports("logthis")

  message("Triggering contract registration...")

  # For each function, try to call it with minimal args to register contracts
  # This is tricky - we don't actually want to run the functions
  # Instead, we'll parse the source code

  all_contracts <- list()

  for (fn_name in exports) {
    # Get function source
    fn <- tryCatch(
      get(fn_name, envir = asNamespace("logthis")),
      error = function(e) NULL
    )

    if (!is.null(fn) && is.function(fn)) {
      # Parse function body for contract calls
      body_text <- deparse(body(fn))

      # Look for require_that, ensure_that, check_invariant calls
      pre <- extract_contract_from_source(body_text, "require_that")
      post <- extract_contract_from_source(body_text, "ensure_that")
      inv <- extract_contract_from_source(body_text, "check_invariant")

      if (length(pre) > 0 || length(post) > 0 || length(inv) > 0) {
        all_contracts[[fn_name]] <- list(
          preconditions = pre,
          postconditions = post,
          invariants = inv
        )
      }
    }
  }

  all_contracts
}

#' Extract contract conditions from source code
#' @param body_text Function body as character vector
#' @param contract_fn Name of contract function (require_that, etc.)
#' @return Character vector of condition names
extract_contract_from_source <- function(body_text, contract_fn) {
  # Find lines with contract_fn
  pattern <- paste0(contract_fn, "\\(")
  start_lines <- grep(pattern, body_text)

  if (length(start_lines) == 0) return(character(0))

  conditions <- character(0)

  for (start_idx in start_lines) {
    # Find matching closing paren
    depth <- 0
    in_contract <- FALSE
    current_condition <- ""

    for (i in start_idx:length(body_text)) {
      line <- body_text[i]

      # Count parens to find matching close
      open_count <- length(gregexpr("\\(", line)[[1]])
      close_count <- length(gregexpr("\\)", line)[[1]])

      if (grepl(pattern, line)) {
        in_contract <- TRUE
        depth <- open_count - close_count
      } else if (in_contract) {
        depth <- depth + open_count - close_count
      }

      # Extract condition names (text before =)
      if (in_contract && grepl("\"[^\"]+\"\\s*=", line)) {
        matches <- regmatches(line, gregexpr("\"([^\"]+)\"\\s*=", line))
        if (length(matches[[1]]) > 0) {
          for (match in matches[[1]]) {
            # Extract just the condition name
            cond_name <- gsub("\"([^\"]+)\"\\s*=", "\\1", match)
            conditions <- c(conditions, cond_name)
          }
        }
      }

      if (depth <= 0 && in_contract) {
        break
      }
    }
  }

  unique(conditions)
}

#' Generate markdown documentation from contracts
generate_contract_markdown <- function(contracts) {
  lines <- character(0)

  # Header
  lines <- c(lines, "# Function Contracts")
  lines <- c(lines, "")
  lines <- c(lines, "**GENERATED FILE - DO NOT EDIT MANUALLY**")
  lines <- c(lines, "")
  lines <- c(lines, "Source of truth: R/*.R files (executable contracts)")
  lines <- c(lines, sprintf("Generated: %s", Sys.time()))
  lines <- c(lines, "")
  lines <- c(lines, "---")
  lines <- c(lines, "")

  # Table of contents
  lines <- c(lines, "## Table of Contents")
  lines <- c(lines, "")
  for (fn_name in sort(names(contracts))) {
    lines <- c(lines, sprintf("- [%s](#%s)", fn_name, tolower(gsub("_", "-", fn_name))))
  }
  lines <- c(lines, "")
  lines <- c(lines, "---")
  lines <- c(lines, "")

  # Contract details
  for (fn_name in sort(names(contracts))) {
    contract <- contracts[[fn_name]]

    lines <- c(lines, sprintf("## `%s()`", fn_name))
    lines <- c(lines, "")

    # Preconditions
    if (length(contract$preconditions) > 0) {
      lines <- c(lines, "### Preconditions (Caller's Responsibility)")
      lines <- c(lines, "")
      for (cond in contract$preconditions) {
        lines <- c(lines, sprintf("- %s", cond))
      }
      lines <- c(lines, "")
    }

    # Postconditions
    if (length(contract$postconditions) > 0) {
      lines <- c(lines, "### Postconditions (Function's Guarantee)")
      lines <- c(lines, "")
      for (cond in contract$postconditions) {
        lines <- c(lines, sprintf("- %s", cond))
      }
      lines <- c(lines, "")
    }

    # Invariants
    if (length(contract$invariants) > 0) {
      lines <- c(lines, "### Invariants (Must Always Hold)")
      lines <- c(lines, "")
      for (cond in contract$invariants) {
        lines <- c(lines, sprintf("- %s", cond))
      }
      lines <- c(lines, "")
    }

    lines <- c(lines, sprintf("**Source**: [`R/%s`](../R/)", fn_name))
    lines <- c(lines, "")
    lines <- c(lines, "---")
    lines <- c(lines, "")
  }

  lines
}

# Main execution
main <- function() {
  message("Extracting contracts from source code...")
  contracts <- extract_contracts()

  message(sprintf("Found contracts in %d functions", length(contracts)))

  message("Generating markdown documentation...")
  md_lines <- generate_contract_markdown(contracts)

  # Write to inst/contracts.md
  output_file <- "inst/contracts.md"
  dir.create("inst", showWarnings = FALSE, recursive = TRUE)

  writeLines(md_lines, output_file)

  message(sprintf("Contract documentation written to: %s", output_file))
  message("✓ Done")
}

if (!interactive()) {
  main()
}
