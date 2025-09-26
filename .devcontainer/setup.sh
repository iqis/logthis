#!/bin/bash
set -e

echo "🚀 Setting up R Development Environment for logthis package..."

# The rocker/tidyverse image already has R and tidyverse installed
# We just need to install additional development packages

# Update package lists
echo "📦 Updating package lists..."
apt-get update

# Install additional system dependencies for R package development
echo "🔧 Installing additional system dependencies..."
apt-get install -y \
    pandoc \
    pandoc-citeproc \
    texlive-latex-base \
    texlive-fonts-recommended \
    texlive-extra-utils \
    git

# Install R package development dependencies
echo "📚 Installing R package development dependencies..."
R --no-restore --no-save -e "
  options(repos = c(CRAN = 'https://cloud.r-project.org/'))
  
  # Essential package development packages (some may already be installed in tidyverse image)
  install.packages(c(
    'devtools',
    'roxygen2',
    'testthat',
    'usethis',
    'pkgdown',
    'covr',
    'spelling',
    'goodpractice',
    'lintr',
    'styler'
  ), lib = '/usr/local/lib/R/site-library')
  
  # logthis package dependencies not included in tidyverse
  install.packages(c(
    'crayon',
    'shiny',
    'shinyalert'
  ), lib = '/usr/local/lib/R/site-library')
  
  cat('📦 Additional R packages installed successfully!\n')
  cat('� tidyverse packages already available from base image\n')
"

# Set up R profile for better development experience
echo "🎯 Setting up R development environment..."
cat > /home/vscode/.Rprofile << 'EOF'
# logthis package development profile for rocker/tidyverse environment
options(
  repos = c(CRAN = "https://cloud.r-project.org/"),
  browser = function(url) system(paste("code", url)),
  pager = function(files, header, title, delete.file) {
    cat(paste(readLines(files), collapse = "\n"))
  },
  help_type = "html",
  width = 120,
  warn = 1,
  warnPartialMatchArgs = TRUE,
  warnPartialMatchDollar = TRUE,
  warnPartialMatchAttr = TRUE
)

# Automatically load devtools and tidyverse for package development
if (interactive()) {
  suppressMessages({
    if (requireNamespace("devtools", quietly = TRUE)) {
      library(devtools)
      cat("✅ devtools loaded for package development\n")
    }
    if (requireNamespace("tidyverse", quietly = TRUE)) {
      library(tidyverse)
      cat("✅ tidyverse loaded (ggplot2, dplyr, tidyr, readr, purrr, tibble, stringr, forcats)\n")
    }
  })
}

# Custom startup message
cat("🔬 logthis Development Environment Ready!\n")
cat("📍 Working directory:", getwd(), "\n")
cat("📊 R version:", R.version.string, "\n")
cat("🐳 Running in rocker/tidyverse container\n")
EOF

# Fix permissions (rocker images use rstudio user by default, but devcontainer uses vscode)
if id "vscode" &>/dev/null; then
  chown -R vscode:vscode /home/vscode/.Rprofile 2>/dev/null || true
elif id "rstudio" &>/dev/null; then
  chown -R rstudio:rstudio /home/rstudio/.Rprofile 2>/dev/null || true
fi

# Clean up
echo "🧹 Cleaning up..."
apt-get autoremove -y
apt-get autoclean
rm -rf /var/lib/apt/lists/*

echo "✅ R Development Environment setup complete!"
echo "🎉 Ready for logthis package development!"