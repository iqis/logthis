#!/usr/bin/env Rscript

# R CMD check wrapper that enforces renv environment
# This ensures all checks use the project's renv library

# Activate renv first
source("renv/activate.R")

# Set R_LIBS_USER to the renv library path
renv_lib <- renv:::renv_paths_library()
Sys.setenv(R_LIBS_USER = renv_lib)

# Print library paths for verification
cat("Using renv library path:\n")
cat(paste("R_LIBS_USER:", Sys.getenv("R_LIBS_USER"), "\n"))
cat("Library paths:\n")
cat(paste(.libPaths(), collapse = "\n"), "\n\n")

# Verify shinyalert is available
if (requireNamespace("shinyalert", quietly = TRUE)) {
  cat("✓ shinyalert is available in renv environment\n")
} else {
  cat("✗ shinyalert is NOT available - installing...\n")
  renv::install("shinyalert")
}

# Run R CMD check
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  args <- c(".", "--no-manual")
}

check_cmd <- paste("R CMD check", paste(args, collapse = " "))
cat("Running:", check_cmd, "\n\n")

# Execute R CMD check with proper environment
system2("R", c("CMD", "check", args), env = c(
  R_LIBS_USER = renv_lib,
  R_PROFILE_USER = file.path(getwd(), ".Rprofile")
))