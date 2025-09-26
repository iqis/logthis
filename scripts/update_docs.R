#!/usr/bin/env Rscript

# Update package documentation
# Run this script to regenerate all documentation

cat("Updating documentation...\n")

# Update roxygen2 documentation
devtools::document()

# Build vignettes
devtools::build_vignettes()

# Build pkgdown site
pkgdown::build_site()

# Run tests
devtools::test()

# Check package
devtools::check()

cat("Documentation update complete!\n")