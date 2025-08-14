#!/bin/bash
set -euo pipefail

# Setup environment script - prepares configuration files based on .env settings
echo "🔧 Setting up Nextcloud configuration files..."

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Function to validate required variables
validate_config() {
    echo "[VALIDATE] Checking configuration..."
    
    local errors=0
    
    if [[ "$TUNNEL_TOKEN" == "REPLACE_ME_TUNNEL_TOKEN" ]] || [[ -z "$TUNNEL_TOKEN" ]]; then
        echo "❌ ERROR: TUNNEL_TOKEN must be set in .env file"
        errors=$((errors + 1))
    fi
    
    if [[ "$NEXTCLOUD_DOMAIN" == "cloud.example.com" ]] || [[ -z "$NEXTCLOUD_DOMAIN" ]]; then
        echo "❌ ERROR: NEXTCLOUD_DOMAIN must be set to your actual domain in .env file"
        errors=$((errors + 1))
    fi
    
    if [[ "$DB_PASSWORD" == "changeme_db" ]]; then
        echo "⚠️  WARNING: You should change DB_PASSWORD from the default value"
    fi
    
    if [[ $errors -gt 0 ]]; then
        echo ""
        echo "Please edit .env file and set the required variables:"
        echo "  nano .env"
        exit 1
    fi
    
    echo "✅ Configuration validation passed"
}

# Function to generate docker-compose.yml with current config
generate_compose() {
    echo "[COMPOSE] Generating docker-compose.yml with your configuration..."
    
    cat > "$SCRIPT_DIR/docker-compose.yml" <<YAML
version: "3.9"

services:
  db:
    image: docker.io/library/postgres:${POSTGRES_VERSION}
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - ./data/postgres:/var/lib/postgresql/data:Z
    networks: [web]

  redis:
    image: docker.io/library/redis:${REDIS_VERSION}-alpine
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - ./data/redis:/data:Z
    networks: [web]

  # Nextcloud runs on HTTP:80 internally (no local TLS)
  nextcloud_app:
    image: docker.io/library/nextcloud:${NEXTCLOUD_VERSION}-apache
    restart: unless-stopped
    depends_on: [db, redis]
    environment:
      # --- Database ---
      POSTGRES_HOST: db
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}

      # --- Reverse proxy awareness (public users come via Cloudflare HTTPS) ---
      OVERWRITEPROTOCOL: https
      OVERWRITEHOST: ${NEXTCLOUD_DOMAIN}
      OVERWRITECLIURL: https://${NEXTCLOUD_DOMAIN}
      TRUSTED_PROXIES: ${TRUSTED_PROXIES}

      # --- Redis cache ---
      REDIS_HOST: redis
    volumes:
      - ./data/nextcloud:/var/www/html:Z
    networks: [web]

  # Cloudflare Tunnel (egress on TCP 443 using HTTP/2)
  cloudflared:
    image: docker.io/cloudflare/cloudflared:latest
    restart: unless-stopped
    depends_on: [nextcloud_app]
    environment:
      TUNNEL_TOKEN: ${TUNNEL_TOKEN}
    # Force TCP/443 egress to Cloudflare
    command: tunnel --no-autoupdate --protocol http2 run
    networks: [web]

networks:
  web:
    driver: bridge
    ipam:
      config:
        - subnet: ${NETWORK_SUBNET}
YAML
    
    echo "✅ docker-compose.yml generated"
}

# Function to generate systemd service file
generate_service() {
    echo "[SERVICE] Generating systemd service file..."
    
    cat > "$SCRIPT_DIR/nextcloud.service" <<EOF
[Unit]
Description=Nextcloud stack (${CONTAINER_RUNTIME}) — clean start/stop with prune
After=network-online.target ${CONTAINER_RUNTIME}.service
Wants=network-online.target
Requires=${CONTAINER_RUNTIME}.service

[Service]
Type=oneshot
RemainAfterExit=yes
# Set project name so labels & network names are predictable
Environment=COMPOSE_PROJECT_NAME=nextcloud
Environment=COMPOSE_FILE=${STACK_DIR}/docker-compose.yml
WorkingDirectory=${STACK_DIR}

# --- PRE-START CLEANUP (handles unclean previous shutdowns) ---
# Try a graceful compose down first
ExecStartPre=/bin/sh -lc '/usr/bin/${COMPOSE_COMMAND} -f "\$COMPOSE_FILE" down --timeout 25 --remove-orphans || true'
# Force-remove any lingering containers for this project (labels are set by ${COMPOSE_COMMAND})
ExecStartPre=/bin/sh -lc '/usr/bin/${CONTAINER_RUNTIME} ps -aq --filter "label=io.${CONTAINER_RUNTIME}.compose.project=\$COMPOSE_PROJECT_NAME" | xargs -r /usr/bin/${CONTAINER_RUNTIME} rm -f || true'
# Remove the project network if it still exists (common if down aborted)
ExecStartPre=/bin/sh -lc '/usr/bin/${CONTAINER_RUNTIME} network ls --format "{{.Name}}" | grep -x "\${COMPOSE_PROJECT_NAME}_web" >/dev/null 2>&1 && /usr/bin/${CONTAINER_RUNTIME} network rm "\${COMPOSE_PROJECT_NAME}_web" || true'

# --- START ---
ExecStart=/usr/bin/${COMPOSE_COMMAND} -f "\$COMPOSE_FILE" up -d

# --- STOP ---
ExecStop=/bin/sh -lc '/usr/bin/${COMPOSE_COMMAND} -f "\$COMPOSE_FILE" down --timeout 25 --remove-orphans || true'

[Install]
WantedBy=multi-user.target
EOF
    
    echo "✅ nextcloud.service generated"
}

# Function to create .env file for the stack
create_stack_env() {
    echo "[ENV] Creating .env file for deployment..."
    
    cat > "$SCRIPT_DIR/.env.deploy" <<EOF
# Nextcloud Stack Environment
# This file will be copied to ${STACK_DIR}/.env during installation

TUNNEL_TOKEN=${TUNNEL_TOKEN}
POSTGRES_VERSION=${POSTGRES_VERSION}
REDIS_VERSION=${REDIS_VERSION}
NEXTCLOUD_VERSION=${NEXTCLOUD_VERSION}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
NEXTCLOUD_DOMAIN=${NEXTCLOUD_DOMAIN}
TRUSTED_PROXIES=${TRUSTED_PROXIES}
NETWORK_SUBNET=${NETWORK_SUBNET}
EOF
    
    echo "✅ Deployment .env file created"
}

# Function to show configuration summary
show_summary() {
    echo ""
    echo "📋 Configuration Summary:"
    echo "  Domain: ${NEXTCLOUD_DOMAIN}"
    echo "  Stack Directory: ${STACK_DIR}"
    echo "  Container Runtime: ${CONTAINER_RUNTIME}"
    echo "  Nextcloud Version: ${NEXTCLOUD_VERSION}"
    echo "  Database: PostgreSQL ${POSTGRES_VERSION}"
    echo "  Cache: Redis ${REDIS_VERSION}"
    echo "  Tunnel Token: ${TUNNEL_TOKEN:0:20}..." # Show first 20 chars
    echo ""
    echo "✅ Configuration setup complete!"
    echo ""
    echo "Next steps:"
    echo "  1. Review the generated files:"
    echo "     - docker-compose.yml"
    echo "     - nextcloud.service"
    echo "     - .env.deploy"
    echo "  2. Run the installation: sudo ./install.sh"
}

# Main execution
main() {
    validate_config
    generate_compose
    generate_service
    create_stack_env
    show_summary
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
