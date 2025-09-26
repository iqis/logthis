source("renv/activate.R")
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
      
      # Load logthis if we're in the project directory
      if (file.exists("DESCRIPTION") && grepl("logthis", readLines("DESCRIPTION")[1])) {
        tryCatch({
          load_all(".")
          cat("📦 logthis package loaded from source\n")
        }, error = function(e) {
          cat("⚠️  Could not load logthis package:", e$message, "\n")
        })
      }
    }
  })
}

# Custom startup message
cat("🔬 logthis Development Environment Ready!\n")
cat("📍 Working directory:", getwd(), "\n")
cat("📊 R version:", R.version.string, "\n")

# Useful development aliases
if (interactive()) {
  # Quick commands for package development
  .test <- function() devtools::test()
  .check <- function() devtools::check()
  .document <- function() devtools::document()
  .install <- function() devtools::install()
  .load <- function() devtools::load_all()
  .build <- function() devtools::build()
  .site <- function() pkgdown::build_site()
  
  cat("🛠️  Development shortcuts available:\n")
  cat("   .test()     - Run tests\n")
  cat("   .check()    - Check package\n")
  cat("   .document() - Update documentation\n")
  cat("   .install()  - Install package\n")
  cat("   .load()     - Load all functions\n")
  cat("   .build()    - Build package\n")
  cat("   .site()     - Build pkgdown site\n")
}
