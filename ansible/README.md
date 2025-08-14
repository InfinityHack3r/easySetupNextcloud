# Nextcloud Ansible Deployment

This Ansible playbook deploys Nextcloud with PostgreSQL, Redis, and Cloudflare Tunnel on both Rocky Linux/RHEL (using Podman) and Debian/Ubuntu (using Docker) systems.

## 📁 File Structure

```
ansible/
├── README.md                 # This file
├── site.yml                  # Main playbook (contains all configuration)
├── hosts.ini                 # Inventory file
└── templates/
    ├── docker-compose.yml.j2      # Container orchestration template
    └── nextcloud-stack.service.j2 # Systemd service template
```

## 🚀 Quick Start

### 1. Prerequisites

**On your control machine:**
- Ansible 2.9+ installed
- SSH access to target servers
- Sudo access on target servers

**Target servers:**
- Rocky Linux 8+, RHEL 8+, Debian 10+, or Ubuntu 18.04+
- Internet connection
- SSH server running

### 2. Configuration

#### Edit Inventory (`hosts.ini`)

```ini
[nextcloud_servers]
rocky.example.com ansible_user=rocky ansible_host=192.168.1.100
ubuntu.example.com ansible_user=ubuntu ansible_host=192.168.1.101

[rocky_servers]
rocky.example.com

[debian_servers]
ubuntu.example.com
```

#### Edit Playbook Variables (`site.yml`)

The playbook automatically detects the OS and configures the appropriate container runtime:
- **Rocky Linux/RHEL**: Podman + podman-compose (rootless with service user)
- **Debian/Ubuntu**: Docker + docker-compose (root privileges)

Key variables to customize:

```yaml
vars:
  # --- Domain & Cloudflare (REQUIRED) ---
  domain_public: your-domain.com
  tunnel_token: "your_cloudflare_tunnel_token_here"
  
  # --- Database (RECOMMENDED to change) ---
  postgres_password: "your_secure_database_password"
  
  # --- Project Configuration ---
  project_dir: /opt/nextcloud
  service_name: nextcloud-stack
  
  # --- Versions ---
  nextcloud_version: 29
  postgres_version: 16
  redis_version: 7
  
  # --- Network ---
  network_subnet: "172.28.0.0/16"
  trusted_proxies: "10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
  
  # --- Optional Features ---
  enable_local_test_port: false  # Enable localhost:8080 for testing
  redis_password: ""             # Leave empty to disable Redis auth
```

### 3. Get Cloudflare Tunnel Token

1. Go to **Cloudflare Zero Trust Dashboard**
2. Navigate to **Access** → **Tunnels**
3. Create or select your tunnel
4. Copy the tunnel token
5. Update `tunnel_token` in `site.yml`

### 4. Run the Playbook

```bash
# Deploy to all servers
ansible-playbook -i hosts.ini site.yml

# Deploy to specific group
ansible-playbook -i hosts.ini site.yml --limit rocky_servers
ansible-playbook -i hosts.ini site.yml --limit debian_servers

# Deploy to specific server
ansible-playbook -i hosts.ini site.yml --limit rocky.example.com

# Dry run (check mode)
ansible-playbook -i hosts.ini site.yml --check

# Verbose output
ansible-playbook -i hosts.ini site.yml -v
```

## 🔧 Advanced Configuration

### Multiple Environments

Create separate inventory files for different environments:

```bash
# Production
ansible-playbook -i inventories/production/hosts.ini site.yml

# Staging  
ansible-playbook -i inventories/staging/hosts.ini site.yml
```

### Custom Variables

Override variables using extra vars:

```bash
ansible-playbook -i hosts.ini site.yml \
  -e "domain_public=cloud.mycompany.com" \
  -e "postgres_password=supersecret123"
```

### Vault for Secrets

Use Ansible Vault for sensitive data:

```bash
# Create encrypted vars file
ansible-vault create group_vars/all/vault.yml

# Add to vault.yml:
vault_tunnel_token: "your_secret_token"
vault_postgres_password: "your_secret_password"

# Update site.yml to use vault variables:
tunnel_token: "{{ vault_tunnel_token }}"
postgres_password: "{{ vault_postgres_password }}"

# Run playbook with vault
ansible-playbook -i hosts.ini site.yml --ask-vault-pass
```

## 🐳 Architecture Differences

### Rocky Linux/RHEL (Podman)
- **Container Runtime**: Podman (rootless)
- **Service User**: `nextcloudsvc` (system user, no shell)
- **Compose Command**: `podman-compose`
- **Volume Mounting**: SELinux-aware (`:Z` flag)
- **Image Registry**: `docker.io/library/` prefix
- **Systemd Service**: User service with environment variables

### Debian/Ubuntu (Docker)
- **Container Runtime**: Docker (root privileges)
- **Service User**: root
- **Compose Command**: `docker-compose`
- **Volume Mounting**: Standard Docker volumes
- **Image Registry**: Docker Hub default
- **Systemd Service**: System service

## 🔄 Management

### Service Management

```bash
# Check status
sudo systemctl status nextcloud-stack

# Start/stop/restart
sudo systemctl start nextcloud-stack
sudo systemctl stop nextcloud-stack  
sudo systemctl restart nextcloud-stack

# View logs
sudo journalctl -u nextcloud-stack -f

# Enable/disable auto-start
sudo systemctl enable nextcloud-stack
sudo systemctl disable nextcloud-stack
```

### Container Management

**Rocky Linux (Podman):**
```bash
# As service user
sudo -u nextcloudsvc podman ps
sudo -u nextcloudsvc podman logs nextcloud_nextcloud_app_1
```

**Debian/Ubuntu (Docker):**
```bash
# As root
docker ps
docker logs nextcloud_nextcloud_app_1
```

### Manual Operations

```bash
# Navigate to project directory
cd /opt/nextcloud

# View compose configuration
docker-compose config  # or podman-compose config

# Pull latest images
docker-compose pull    # or podman-compose pull

# Restart specific service
docker-compose restart nextcloud_app
```

## 🌐 Cloudflare Configuration

After deployment, configure your Cloudflare tunnel:

1. Go to **Cloudflare Zero Trust** → **Access** → **Tunnels**
2. Select your tunnel → **Public Hostnames**
3. Add hostname:
   - **Subdomain**: `cloud` (or your choice)
   - **Domain**: `your-domain.com`  
   - **Service**: `http://nextcloud_app:80`

## 🔒 Security Best Practices

1. **Use Ansible Vault** for sensitive variables
2. **Change default passwords** before deployment
3. **Limit SSH access** to control machine
4. **Use SSH keys** instead of passwords
5. **Enable firewall** on target servers:
   ```bash
   # Rocky Linux
   sudo firewall-cmd --permanent --add-service=ssh
   sudo firewall-cmd --reload
   
   # Debian/Ubuntu  
   sudo ufw allow ssh
   sudo ufw enable
   ```

## 🐛 Troubleshooting

### Playbook Execution Issues

**SSH connection failed:**
```bash
# Test SSH connectivity
ansible -i hosts.ini nextcloud_servers -m ping

# Debug SSH issues
ansible-playbook -i hosts.ini site.yml -vvv
```

**Permission denied:**
```bash
# Ensure user has sudo access
ansible -i hosts.ini nextcloud_servers -m shell -a "sudo whoami" -b
```

### Container Issues

**Containers not starting:**
```bash
# Check container logs
ansible -i hosts.ini nextcloud_servers -m shell -a "cd /opt/nextcloud && docker-compose logs" -b

# Check systemd service
ansible -i hosts.ini nextcloud_servers -m shell -a "systemctl status nextcloud-stack" -b
```

**Podman rootless issues on Rocky Linux:**
```bash
# Check user lingering
ansible -i hosts.ini rocky_servers -m shell -a "loginctl show-user nextcloudsvc | grep Linger" -b

# Check service user environment  
ansible -i hosts.ini rocky_servers -m shell -a "sudo -u nextcloudsvc env | grep XDG" -b
```

### OS Detection Issues

The playbook auto-detects OS family, but you can override:

```bash
ansible-playbook -i hosts.ini site.yml -e "container_runtime=docker"
```

## 📋 Verification

After deployment, verify the installation:

```bash
# Check all services are running
ansible -i hosts.ini nextcloud_servers -m shell -a "systemctl is-active nextcloud-stack" -b

# Check container status
ansible -i hosts.ini debian_servers -m shell -a "docker ps" -b
ansible -i hosts.ini rocky_servers -m shell -a "sudo -u nextcloudsvc podman ps" -b

# Test local port (if enabled)
curl -I http://server-ip:8080
```

## 🔄 Updates and Maintenance

### Update Container Images

```bash
# Create update playbook
cat > update.yml <<EOF
---
- hosts: nextcloud_servers
  become: true
  tasks:
    - name: Pull latest images
      shell: cd /opt/nextcloud && {{ compose_command }} pull
      
    - name: Restart services  
      systemd:
        name: nextcloud-stack
        state: restarted
EOF

# Run update
ansible-playbook -i hosts.ini update.yml
```

### Backup Data

```bash
# Create backup playbook
ansible -i hosts.ini nextcloud_servers -m shell -a "tar -czf /backup/nextcloud-$(date +%Y%m%d).tar.gz -C /opt/nextcloud data/" -b
```

## 📄 License

This project is provided as-is for educational and production use. Please ensure compliance with all software licenses of the included components.
