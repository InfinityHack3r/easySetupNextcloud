# Nextcloud Ansible Testing Setup

This is a complete Nextcloud deployment using Ansible with the following features:

## Features
- **Public Access**: Via Cloudflare Tunnel → https://cloud.example.com → http://nextcloud:80 (container network)
- **Local Access**: Via NGINX TLS → https://cloud.example.local (binds to your LAN IP, proxies to nextcloud:80)
- **Nextcloud**: Apache image (serves HTTP on :80)
- **Database**: PostgreSQL with optional Redis
- **Container Runtime**: Auto-detect + install Docker or Podman on Debian/RHEL families
- **Systemd Service**: Aggressively refreshes (down → prune → pull → force-recreate)
- **Self-signed Certificates**: For local access (or use your own)

## Quick Start

1. **Install Ansible Collections**:
   ```bash
   ansible-galaxy collection install -r requirements.yml
   ```

2. **Configure Inventory**:
   - Edit `inventories/prod/hosts.yml` to set your server IP
   - Edit `inventories/prod/group_vars/all.yml` for general configuration
   - Edit `inventories/prod/group_vars/vault.yml` for sensitive data

3. **Encrypt Secrets**:
   ```bash
   ansible-vault encrypt inventories/prod/group_vars/vault.yml
   ```

4. **Configure DNS**:
   - Point your LAN DNS so `cloud.example.local` → your server's LAN IP (e.g., 192.168.0.1)

5. **Deploy**:
   ```bash
   ansible-playbook playbooks/site.yml --ask-vault-pass
   ```

6. **Access**:
   - **Local**: https://cloud.example.local (trust the self-signed cert)
   - **Public**: Configure your Cloudflare Tunnel's Public Hostname: `cloud.example.com` → HTTP → Service = `http://nextcloud:80`

## Configuration

### Key Variables in `inventories/prod/group_vars/all.yml`:
- `container_runtime`: auto | docker | podman
- `nginx_bind_ip`: "0.0.0.0" or specific IP
- `redis_enabled`: true/false
- `cloudflared_enabled`: true/false
- `timezone`: Set your timezone

### Secrets in `inventories/prod/group_vars/vault.yml`:
- `vault_nextcloud_admin_user`: Admin username
- `vault_nextcloud_admin_pass`: Admin password
- `vault_pg_password`: PostgreSQL password
- `vault_cloudflared_tunnel_token`: Your Cloudflare tunnel token

## Directory Structure
```
nextcloud-ansible-testing/
├── ansible.cfg
├── requirements.yml
├── inventories/
│   └── prod/
│       ├── hosts.yml
│       └── group_vars/
│           ├── all.yml
│           └── vault.yml
├── playbooks/
│   └── site.yml
└── roles/
    └── nextcloud_stack/
        ├── defaults/
        ├── handlers/
        ├── tasks/
        └── templates/
```

## Notes
- The systemd service forces a fresh redeploy on every Ansible run
- Self-signed certificates are generated automatically for local access
- SELinux compatibility is built-in
- Supports both Docker and Podman with automatic detection
