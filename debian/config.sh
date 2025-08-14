#!/bin/bash
# Configuration loader for Nextcloud installation
# This script loads configuration from .env file

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Function to load configuration from .env file
load_config() {
    local env_file="$SCRIPT_DIR/.env"
    
    if [[ -f "$env_file" ]]; then
        # Source the .env file, handling both export and non-export lines
        set -a  # automatically export all variables
        source "$env_file"
        set +a  # turn off automatic export
        
        # Set derived paths
        export COMPOSE="$STACK_DIR/docker-compose.yml"
        export ENVFILE="$STACK_DIR/.env"
        export DATA_DIR="$STACK_DIR/data"
        export POSTGRES_DATA="$DATA_DIR/postgres"
        export REDIS_DATA="$DATA_DIR/redis"
        export NEXTCLOUD_DATA="$DATA_DIR/nextcloud"
        
        echo "✅ Configuration loaded from $env_file"
    else
        echo "❌ ERROR: Configuration file not found at $env_file"
        echo "Please copy .env.template to .env and customize it"
        exit 1
    fi
}

# Auto-load configuration when sourced
load_config
