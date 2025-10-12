FROM rocker/tidyverse:latest

# Install system dependencies including wget for Claude Code CLI, netcat for health checks, and AWS CLI
RUN apt-get update && apt-get install -y \
    wget \
    netcat-openbsd \
    curl \
    unzip \
    sudo \
    gpg \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI (gh)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Modify existing user (rstudio) to be named vscode and give sudo privileges
RUN usermod -l vscode rstudio \
    && usermod -d /home/vscode -m vscode \
    && groupmod -n vscode rstudio \
    && echo "vscode ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/vscode \
    && chmod 0440 /etc/sudoers.d/vscode

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# Install Node.js and npm if not present, then install devcontainer CLI
RUN apt-get update && apt-get install -y nodejs npm \
    && npm install -g @devcontainers/cli \
    && rm -rf /var/lib/apt/lists/*

# Install renv for dependency management and languageserver for VS Code integration
RUN R -e "install.packages(c('renv', 'languageserver'), repos='https://cloud.r-project.org')"

# Copy renv files for dependency restoration
COPY renv.lock renv.lock
COPY .Rprofile .Rprofile
COPY renv/activate.R renv/activate.R
COPY renv/settings.json renv/settings.json

# Restore the renv environment
RUN R -e "renv::restore()"

# Set up permissions for vscode user
RUN chown -R vscode:vscode /usr/local/lib/R \
    && mkdir -p /home/vscode/.local/share/renv \
    && chown -R vscode:vscode /home/vscode

