# Nextcloud Easy Setup for Debian/Ubuntu

This directory contains scripts and configuration files for deploying Nextcloud with PostgreSQL, Redis, and Cloudflare Tunnel on Debian/Ubuntu systems using Docker.

## 📁 File Structure

```
debian/
├── README.md                 # This file
├── config.sh                 # Configuration loader
├── setup-env.sh              # Environment setup script
├── install.sh                # Installation script
├── docker-compose.yml        # Container orchestration (generated)
├── nextcloud.service         # Systemd service unit (generated)
├── .env                      # Main configuration file
├── .env.template             # Configuration template
└── .env.deploy               # Deployment environment file (generated)
```

## 🚀 Quick Start

1. **Clone and navigate to the debian directory:**
   ```bash
   git clone <repository-url>
   cd easySetupNextcloud/debian
   ```

2. **Edit configuration (required):**
   ```bash
   cp .env.template .env
   nano .env
   ```
   Update at minimum:
   - `NEXTCLOUD_DOMAIN` - Your domain name
   - `DB_PASSWORD` - Database password
   - `TUNNEL_TOKEN` - Your Cloudflare tunnel token

3. **Setup environment and generate files:**
   ```bash
   ./setup-env.sh
   ```

4. **Run the installation:**
   ```bash
   sudo ./install.sh
   ```

## 📋 Prerequisites

- Debian 10+, Ubuntu 18.04+, or compatible distribution
- Root or sudo access
- Internet connection
- Cloudflare account with tunnel configured

## ⚙️ Configuration

### Main Configuration (`.env`)

All configuration is centralized in the `.env` file. Key variables you should customize:

```bash
# Cloudflare Tunnel Configuration (REQUIRED)
TUNNEL_TOKEN=your-tunnel-token-here

# Domain configuration (REQUIRED)
NEXTCLOUD_DOMAIN=your-domain.com

# Database settings (RECOMMENDED to change)
DB_PASSWORD=your-secure-password

# Installation paths (optional)
STACK_DIR=/opt/nextcloud

# Container runtime (Docker for Debian/Ubuntu)
CONTAINER_RUNTIME=docker
COMPOSE_COMMAND=docker-compose

# Network settings (optional)
NETWORK_SUBNET=172.28.0.0/16
TRUSTED_PROXIES=10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
```

Copy `.env.template` to `.env` and customize:
```bash
cp .env.template .env
nano .env
```

### Cloudflare Tunnel Token

You need a Cloudflare tunnel token for this setup to work. Get one from:
1. Cloudflare Zero Trust Dashboard
2. Access → Tunnels → Create/Edit Tunnel
3. Copy the tunnel token
4. Add it to your `.env` file before running `setup-env.sh`

To update the token later:
```bash
nano .env  # Edit TUNNEL_TOKEN=your_token_here
./setup-env.sh  # Regenerate files
sudo ./install.sh  # Redeploy
```

## 🔧 Scripts Overview

### `setup-env.sh` - Environment Setup Script
Validates configuration and generates deployment files based on .env settings.

**Functions:**
- `validate_config()` - Validates required configuration variables
- `generate_compose()` - Creates docker-compose.yml with your settings
- `generate_service()` - Creates systemd service file
- `create_stack_env()` - Creates deployment .env file
- `show_summary()` - Shows configuration summary

**Usage:**
```bash
./setup-env.sh
```

### `install.sh` - Installation Script
Installs Docker, deploys files, and starts the stack.

**Functions:**
- `check_prerequisites()` - Verifies setup-env.sh was run
- `install_dependencies()` - Installs Docker and Docker Compose
- `prepare_stack_directory()` - Creates directories and backups
- `deploy_files()` - Moves configuration files to stack directory
- `stop_old_services()` - Stops existing services
- `pull_images()` - Downloads container images
- `start_stack()` - Starts the container stack
- `install_systemd_service()` - Installs systemd service
- `verify_deployment()` - Checks if deployment was successful
- `show_completion_message()` - Shows final instructions

**Usage:**
```bash
sudo ./install.sh
```

### `config.sh` - Configuration Loader
Loads configuration from the `.env` file and sets up derived variables.

**Functions:**
- `load_config()` - Loads all variables from .env file automatically

**Usage:**
```bash
source ./config.sh  # Configuration is auto-loaded
```

## 🐳 Container Architecture

The setup deploys four containers:

1. **PostgreSQL Database** (`db`)
   - Image: `postgres:16`
   - Data: `./data/postgres`
   - Port: Internal only

2. **Redis Cache** (`redis`)
   - Image: `redis:7-alpine`
   - Data: `./data/redis`
   - Port: Internal only

3. **Nextcloud Application** (`nextcloud_app`)
   - Image: `nextcloud:29-apache`
   - Data: `./data/nextcloud`
   - Port: HTTP 80 (internal)

4. **Cloudflare Tunnel** (`cloudflared`)
   - Image: `cloudflare/cloudflared:latest`
   - Connects Nextcloud to the internet via Cloudflare

## 🔄 Management Commands

### Service Management
```bash
# Start all services
cd /opt/nextcloud && docker-compose up -d

# Stop all services
cd /opt/nextcloud && docker-compose down

# Restart a specific service
cd /opt/nextcloud && docker-compose restart nextcloud_app

# View logs
docker logs -f $(docker ps -qf name=nextcloud_app)
docker logs -f $(docker ps -qf name=cloudflared)
```

### Systemd Service
The installation creates a systemd service for easier management:

```bash
# Control via systemd
sudo systemctl start nextcloud-stack
sudo systemctl stop nextcloud-stack
sudo systemctl restart nextcloud-stack
sudo systemctl status nextcloud-stack

# Enable/disable auto-start
sudo systemctl enable nextcloud-stack
sudo systemctl disable nextcloud-stack
```

### Maintenance
```bash
# Update container images
cd /opt/nextcloud
docker-compose pull
docker-compose up -d

# Backup data
sudo tar -czf nextcloud-backup-$(date +%Y%m%d).tar.gz -C /opt/nextcloud data/

# Clean up old containers/images
docker system prune -f
```

## 🌐 Cloudflare Configuration

After installation, configure your Cloudflare tunnel:

1. Go to **Cloudflare Zero Trust** → **Access** → **Tunnels**
2. Select your tunnel → **Public Hostnames**
3. Add/Edit hostname:
   - **Subdomain**: `cloud` (or your choice)
   - **Domain**: `your-domain.com`
   - **Service**: `http://nextcloud_app:80`

## 🔒 Security Considerations

1. **Change default passwords** in `.env`
2. **Secure your server** with UFW firewall:
   ```bash
   sudo ufw enable
   sudo ufw allow ssh
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   ```
3. **Regular updates** of container images and system packages
4. **Backup your data** regularly
5. **Monitor logs** for suspicious activity

## 🐛 Troubleshooting

### Common Issues

**Docker permission issues:**
```bash
# Add user to docker group and restart session
sudo usermod -aG docker $USER
# Log out and back in, or run:
newgrp docker
```

**Container won't start:**
```bash
# Check container logs
docker logs CONTAINER_NAME

# Check compose file syntax
cd /opt/nextcloud && docker-compose config
```

**Cloudflare tunnel issues:**
```bash
# Check tunnel token in .env file
grep TUNNEL_TOKEN /opt/nextcloud/.env

# Check cloudflared logs
docker logs -f $(docker ps -qf name=cloudflared)
```

**Database connection issues:**
```bash
# Check database logs
docker logs $(docker ps -qf name=db)

# Test database connection
docker exec -it $(docker ps -qf name=db) psql -U nextcloud -d nextcloud
```

**Permission issues:**
```bash
# Fix data directory permissions
sudo chown -R 33:33 /opt/nextcloud/data/nextcloud
sudo chown -R 999:999 /opt/nextcloud/data/postgres
sudo chown -R 999:999 /opt/nextcloud/data/redis
```

### Docker Installation Issues

**Docker not starting:**
```bash
# Check Docker service status
sudo systemctl status docker

# Start Docker if stopped
sudo systemctl start docker
sudo systemctl enable docker
```

**Docker Compose not found:**
```bash
# Check if docker-compose is installed
which docker-compose

# Reinstall if missing
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### Log Locations

- Container logs: `docker logs CONTAINER_NAME`
- Systemd logs: `sudo journalctl -u nextcloud-stack`
- Nextcloud logs: `/opt/nextcloud/data/nextcloud/data/nextcloud.log`

## 📞 Support

For issues specific to this setup:
1. Check the troubleshooting section above
2. Review container logs
3. Verify Cloudflare tunnel configuration
4. Ensure all prerequisites are met

## 🆚 Differences from Rocky Linux Version

- Uses **Docker** instead of Podman
- Uses **docker-compose** instead of podman-compose
- Different package installation method (APT vs DNF/YUM)
- Docker group membership handling
- Modified systemd service for Docker compatibility

## 📄 License

This project is provided as-is for educational and production use. Please ensure compliance with all software licenses of the included components.
