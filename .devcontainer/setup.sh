#!/bin/bash
set -e

echo "🚀 Setting up R Development Environment for logthis package..."

# Update package lists
echo "📦 Updating package lists..."
apt-get update

# Install basic dependencies
echo "🔧 Installing basic dependencies..."
apt-get install -y software-properties-common dirmngr wget curl

# Add R repository GPG key
echo "🔑 Adding R repository GPG key..."
wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc

# Add R repository
echo "📋 Adding R repository..."
add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/" -y

# Update package lists again
apt-get update

# Install R and development dependencies
echo "📊 Installing R and development packages..."
apt-get install -y \
    r-base \
    r-base-dev \
    build-essential \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    pandoc \
    pandoc-citeproc \
    texlive-latex-base \
    texlive-fonts-recommended \
    texlive-extra-utils

# Install commonly used R packages for package development
echo "📚 Installing R package development dependencies..."
R --no-restore --no-save -e "
  options(repos = c(CRAN = 'https://cloud.r-project.org/'))
  
  # Essential package development packages
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
  ))
  
  # logthis package dependencies
  install.packages(c(
    'magrittr',
    'purrr',
    'crayon',
    'tibble',
    'glue',
    'shiny',
    'shinyalert'
  ))
  
  # Additional useful packages
  install.packages(c(
    'rmarkdown',
    'knitr',
    'htmltools',
    'DT',
    'ggplot2',
    'dplyr'
  ))
  
  cat('📦 R packages installed successfully!\n')
"

# Set up R profile for better development experience
echo "🎯 Setting up R development environment..."
cat > /home/vscode/.Rprofile << 'EOF'
# logthis package development profile
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

# Automatically load devtools for package development
if (interactive()) {
  suppressMessages({
    if (requireNamespace("devtools", quietly = TRUE)) {
      library(devtools)
      cat("✅ devtools loaded for package development\n")
    }
  })
}

# Custom startup message
cat("🔬 logthis Development Environment Ready!\n")
cat("📍 Working directory:", getwd(), "\n")
cat("📊 R version:", R.version.string, "\n")
EOF

# Fix permissions
chown -R vscode:vscode /home/vscode/.Rprofile

# Clean up
echo "🧹 Cleaning up..."
apt-get autoremove -y
apt-get autoclean
rm -rf /var/lib/apt/lists/*

echo "✅ R Development Environment setup complete!"
echo "🎉 Ready for logthis package development!"