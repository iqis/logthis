FROM rocker/tidyverse:latest

# Install system dependencies including wget for Claude Code CLI and git-lfs
RUN apt-get update && apt-get install -y wget git-lfs && rm -rf /var/lib/apt/lists/*

# Install renv for dependency management and languageserver for VS Code integration
RUN R -e "install.packages(c('renv', 'languageserver'), repos='https://cloud.r-project.org')"

# Copy renv files for dependency restoration
COPY renv.lock renv.lock
COPY .Rprofile .Rprofile
COPY renv/activate.R renv/activate.R
COPY renv/settings.json renv/settings.json

# Restore the renv environment
RUN R -e "renv::restore()"
