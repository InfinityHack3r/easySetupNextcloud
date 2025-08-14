#!/bin/bash
set -euo pipefail

# Nextcloud Installation Script
# This script installs dependencies, moves files, and deploys the stack
echo "🚀 Starting Nextcloud installation..."

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# Function to check if setup-env.sh was run
check_prerequisites() {
    echo "[CHECK] Verifying prerequisites..."
    
    if [[ ! -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
        echo "❌ ERROR: docker-compose.yml not found!"
        echo "Please run setup-env.sh first to generate configuration files"
        exit 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/.env.deploy" ]]; then
        echo "❌ ERROR: .env.deploy not found!"
        echo "Please run setup-env.sh first to generate configuration files"
        exit 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/nextcloud.service" ]]; then
        echo "❌ ERROR: nextcloud.service not found!"
        echo "Please run setup-env.sh first to generate configuration files"
        exit 1
    fi
    
    echo "✅ Prerequisites check passed"
}

# Function to install dependencies
install_dependencies() {
    echo "[DEPS] Installing container runtime and dependencies..."
    
    if command -v dnf >/dev/null 2>&1; then
        echo "  Using DNF package manager..."
        sudo dnf -y install $CONTAINER_RUNTIME ${COMPOSE_COMMAND} >/dev/null
    elif command -v yum >/dev/null 2>&1; then
        echo "  Using YUM package manager..."
        sudo yum -y install $CONTAINER_RUNTIME ${COMPOSE_COMMAND} >/dev/null
    elif command -v apt >/dev/null 2>&1; then
        echo "  Using APT package manager..."
        sudo apt update >/dev/null
        sudo apt -y install $CONTAINER_RUNTIME ${COMPOSE_COMMAND} >/dev/null
    else
        echo "❌ ERROR: Could not detect package manager!"
        echo "Please install $CONTAINER_RUNTIME and ${COMPOSE_COMMAND} manually"
        exit 1
    fi
    
    echo "✅ Dependencies installed successfully"
}

# Function to create stack directory and backup existing files
prepare_stack_directory() {
    echo "[SETUP] Preparing stack directory..."
    
    # Create stack directory
    sudo mkdir -p "$STACK_DIR"
    sudo chown "$USER:$USER" "$STACK_DIR"
    
    # Backup existing files if they exist
    if [[ -f "$STACK_DIR/docker-compose.yml" ]]; then
        local backup_file="$STACK_DIR/docker-compose.yml.bak.$(date +%s)"
        cp "$STACK_DIR/docker-compose.yml" "$backup_file"
        echo "  📦 Backed up existing docker-compose.yml to $(basename "$backup_file")"
    fi
    
    # Create data directories
    mkdir -p "$STACK_DIR/data/postgres" "$STACK_DIR/data/redis" "$STACK_DIR/data/nextcloud"
    
    echo "✅ Stack directory prepared"
}

# Function to move files to stack directory
deploy_files() {
    echo "[DEPLOY] Moving configuration files to stack directory..."
    
    # Copy docker-compose.yml
    cp "$SCRIPT_DIR/docker-compose.yml" "$STACK_DIR/"
    echo "  📄 Copied docker-compose.yml"
    
    # Copy .env file
    cp "$SCRIPT_DIR/.env.deploy" "$STACK_DIR/.env"
    echo "  📄 Copied .env"
    
    echo "✅ Configuration files deployed"
}

# Function to stop old services
stop_old_services() {
    echo "[CLEANUP] Stopping any existing services..."
    
    # Try to stop using docker-compose (ignore errors)
    ( cd "$STACK_DIR" && sudo ${COMPOSE_COMMAND} down --timeout 25 --remove-orphans >/dev/null 2>&1 || true )
    
    # Stop systemd service if it exists
    if systemctl list-unit-files | grep -q "^${UNIT}\.service"; then
        sudo systemctl stop "$UNIT" >/dev/null 2>&1 || true
        echo "  🛑 Stopped systemd service: $UNIT"
    fi
    
    echo "✅ Old services stopped"
}

# Function to pull container images
pull_images() {
    echo "[IMAGES] Pulling container images..."
    
    cd "$STACK_DIR"
    sudo ${COMPOSE_COMMAND} pull
    
    echo "✅ Container images pulled"
}

# Function to start the stack
start_stack() {
    echo "[START] Starting Nextcloud stack..."
    
    cd "$STACK_DIR"
    sudo ${COMPOSE_COMMAND} up -d
    
    echo "✅ Nextcloud stack started"
}

# Function to install systemd service
install_systemd_service() {
    echo "[SYSTEMD] Installing systemd service..."
    
    # Copy service file
    sudo cp "$SCRIPT_DIR/nextcloud.service" "/etc/systemd/system/${UNIT}.service"
    
    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable "$UNIT"
    
    echo "✅ Systemd service installed and enabled"
}

# Function to verify deployment
verify_deployment() {
    echo "[VERIFY] Verifying deployment..."
    
    # Wait a moment for containers to start
    sleep 5
    
    # Check if containers are running
    local running_containers=$(sudo ${CONTAINER_RUNTIME} ps --format "table {{.Names}}" | grep -E "(nextcloud|postgres|redis|cloudflared)" | wc -l)
    
    if [[ $running_containers -ge 4 ]]; then
        echo "✅ All containers are running"
    else
        echo "⚠️  Warning: Not all containers may be running. Check with: sudo ${CONTAINER_RUNTIME} ps"
    fi
}

# Function to show final instructions
show_completion_message() {
    echo ""
    echo "🎉 Nextcloud installation completed successfully!"
    echo ""
    echo "📋 Installation Summary:"
    echo "  Stack Directory: $STACK_DIR"
    echo "  Domain: $NEXTCLOUD_DOMAIN"
    echo "  Systemd Service: $UNIT"
    echo ""
    echo "🌐 Cloudflare Configuration:"
    echo "  In Cloudflare Zero Trust → Access → Tunnels → Public Hostnames:"
    echo "  Service URL: http://nextcloud_app:80"
    echo ""
    echo "🔧 Useful Commands:"
    echo "  Check status:     sudo ${CONTAINER_RUNTIME} ps"
    echo "  View logs:        sudo ${CONTAINER_RUNTIME} logs -f <container_name>"
    echo "  Restart stack:    sudo systemctl restart $UNIT"
    echo "  Stop stack:       sudo systemctl stop $UNIT"
    echo "  Start stack:      sudo systemctl start $UNIT"
    echo ""
    echo "📁 Configuration files are located in: $STACK_DIR"
    echo "📝 To modify configuration: edit .env and run setup-env.sh again"
}

# Main installation function
main() {
    echo "Starting installation process..."
    echo ""
    
    check_prerequisites
    install_dependencies
    prepare_stack_directory
    deploy_files
    stop_old_services
    pull_images
    start_stack
    install_systemd_service
    verify_deployment
    show_completion_message
    
    echo ""
    echo "🚀 Installation process completed!"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
