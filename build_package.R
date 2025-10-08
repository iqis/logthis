#!/usr/bin/env Rscript
# Build and install logthis package

cat("\n=== Building logthis Package ===\n\n")

# Step 1: Generate documentation
cat("1. Generating documentation with roxygen2...\n")
if (!requireNamespace("roxygen2", quietly = TRUE)) {
  cat("   Installing roxygen2...\n")
  install.packages("roxygen2", repos = "https://cloud.r-project.org", quiet = TRUE)
}
roxygen2::roxygenize(".")
cat("   ✓ Documentation generated\n\n")

# Step 2: Install package
cat("2. Installing package...\n")
install.packages(".", repos = NULL, type = "source", quiet = TRUE)
cat("   ✓ Package installed\n\n")

# Step 3: Verify
cat("3. Verifying installation...\n")
library(logthis)
cat("   ✓ Package loaded\n")
cat("   ✓ as_async exported:", "as_async" %in% ls("package:logthis"), "\n")
cat("   ✓ deferred exported:", "deferred" %in% ls("package:logthis"), "\n\n")

cat("=== Build Complete ===\n\n")
