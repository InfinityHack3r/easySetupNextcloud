# Easy Setup Nextcloud

One-command Nextcloud deployment with Ansible.

## Quick Start

1. **Bootstrap** (installs Ansible + dependencies):
   ```bash
   ./bootstrap-ansible.sh
   ```

2. **Configure** your server IP:
   ```bash
   nano ansible/inventories/prod/hosts.yml
   ```
   Change `192.168.0.1` to your server's IP address.

3. **Set passwords**:
   ```bash
   nano ansible/inventories/prod/group_vars/vault.yml
   ```
   Update these values:
   - `vault_nextcloud_admin_pass: "CHANGE_ME"` → your admin password
   - `vault_pg_password: "CHANGE_ME"` → your database password  
   - `vault_cloudflared_tunnel_token: "YOUR_TUNNEL_TOKEN"` → your Cloudflare tunnel token (optional)
   
   Then encrypt it:
   ```bash
   ansible-vault encrypt ansible/inventories/prod/group_vars/vault.yml
   ```

4. **Deploy**:
   ```bash
   cd ansible
   ansible-playbook playbooks/site.yml --ask-vault-pass
   ```

## Access

- **Local**: https://cloud.example.local (self-signed cert)
- **Public**: Configure Cloudflare Tunnel for cloud.example.com

Done! 🎉
