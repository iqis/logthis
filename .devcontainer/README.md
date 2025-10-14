# DevContainer Configuration

This devcontainer is configured for R package development with Docker support for cloud backend testing.

## Features

- **R Environment**: Based on `rocker/tidyverse` with renv for dependency management
- **Docker-in-Docker**: Enables running LocalStack and Azurite for cloud testing
- **AWS CLI v2**: For S3 bucket management in LocalStack
- **VS Code Extensions**: R language support and Claude Code

## Ports

- `8000`: Development Server
- `3838`: Shiny App
- `4566`: LocalStack (S3 emulation)
- `10000`: Azurite (Azure Blob emulation)

## Rebuilding the Container

After updating the devcontainer configuration, you need to rebuild:

1. **Command Palette** (Ctrl+Shift+P / Cmd+Shift+P)
2. Select: **"Dev Containers: Rebuild Container"**
3. Wait for rebuild to complete (~5-10 minutes)

Or rebuild without cache:

1. **Command Palette**
2. Select: **"Dev Containers: Rebuild Container Without Cache"**

## Verifying Docker Setup

After rebuild, verify Docker is available:

```bash
docker --version
docker-compose --version
aws --version
```

## Testing Cloud Backends

Once Docker is available:

```bash
# Start cloud services
cd tests/cloud
./start-services.sh

# Run cloud tests
Rscript -e "devtools::test(filter = 'cloud')"

# Stop services
./stop-services.sh
```

## Troubleshooting

**Docker not found after rebuild:**
- Ensure you ran "Rebuild Container" not just "Reload Window"
- Check that Docker daemon is running: `docker ps`
- Try: `sudo service docker start` if daemon not running

**LocalStack health check fails:**
- Check container logs: `docker-compose -f tests/cloud/docker-compose.yml logs localstack`
- Verify port 4566 is not already in use: `netstat -tuln | grep 4566`

**Azurite connection fails:**
- Check container logs: `docker-compose -f tests/cloud/docker-compose.yml logs azurite`
- Verify port 10000 is not already in use: `netstat -tuln | grep 10000`
