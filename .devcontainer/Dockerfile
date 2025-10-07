FROM rocker/tidyverse:latest

# Install system dependencies including wget for Claude Code CLI, netcat for health checks, and AWS CLI
RUN apt-get update && apt-get install -y \
    wget \
    netcat-openbsd \
    curl \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# Install renv for dependency management and languageserver for VS Code integration
RUN R -e "install.packages(c('renv', 'languageserver'), repos='https://cloud.r-project.org')"

# Copy renv files for dependency restoration (paths relative to parent directory)
COPY ../renv.lock renv.lock
COPY ../.Rprofile .Rprofile
COPY ../renv/activate.R renv/activate.R
COPY ../renv/settings.json renv/settings.json

# Restore the renv environment
RUN R -e "renv::restore()"
