Awesome — here’s the complete, copy-pasteable project wired for:

Public via Cloudflare Tunnel → https://cloud.example.com → http://nextcloud:80 (container network)

Local via NGINX TLS → https://cloud.example.local (binds to your LAN IP, proxies to nextcloud:80)

Nextcloud Apache image (serves HTTP on :80)

Postgres (+ optional Redis)

Docker or Podman (auto-detect + install on Debian/RHEL families)

Systemd service that aggressively refreshes (down → prune → pull → force-recreate)

Ansible reruns always restart the service (fresh deploy)

Self-signed local cert for cloud.example.local (or swap in your own)

📁 Layout
nextcloud-ansible/
├── ansible.cfg
├── requirements.yml
├── inventories/
│   └── prod/
│       ├── hosts.yml
│       └── group_vars/
│           ├── all.yml
│           └── vault.yml        # encrypt with ansible-vault
├── playbooks/
│   └── site.yml
└── roles/
    └── nextcloud_stack/
        ├── defaults/
        │   └── main.yml
        ├── handlers/
        │   └── main.yml
        ├── tasks/
        │   ├── main.yml
        │   ├── prereqs.yml
        │   ├── runtime-docker.yml
        │   ├── runtime-podman.yml
        │   └── nginx-certs.yml
        └── templates/
            ├── docker-compose.yml.j2
            ├── nginx.conf.j2
            └── nextcloud-stack.service.j2

Root files
ansible.cfg
[defaults]
inventory = inventories/prod/hosts.yml
nocows = True
host_key_checking = False
forks = 20
# Optional, to avoid --ask-vault-pass
# vault_password_file = .vault_pass.txt

requirements.yml
---
collections:
  - name: community.docker
  - name: containers.podman
  - name: community.crypto

Inventory
inventories/prod/hosts.yml
all:
  hosts:
    nc-host-1:
      ansible_host: 192.168.0.1

inventories/prod/group_vars/all.yml
# ----- Runtime selection -----
container_runtime: auto            # auto | docker | podman
preferred_runtime: docker
docker_compose_command: "docker compose"
podman_compose_command: "podman-compose"

# ----- Service & paths -----
service_name: nextcloud-stack
use_service_user: true
service_user: nextcloud

project_dir: "/srv/nextcloud"
compose_project_name: "nextcloud"
stack_network: "nextcloud_net"

timezone: "Australia/Sydney"

# ----- Images -----
nextcloud_image: "nextcloud:29-apache"    # Apache variant serves HTTP on :80
postgres_image: "postgres:16"
redis_image: "redis:7"
cloudflared_image: "cloudflare/cloudflared:latest"

# ----- Features -----
redis_enabled: true
cloudflared_enabled: true
reverse_proxy: nginx

# ----- Nextcloud domains/links -----
# Public via Cloudflare Tunnel:
#   cloud.example.com -> http://nextcloud:80 (container network)
# Local via NGINX (LAN):
#   cloud.example.local -> https://<LAN-IP>:443 -> nginx -> nextcloud:80
nextcloud_trusted_domains:
  - "cloud.example.com"
  - "cloud.example.local"
nextcloud_overwrite_host: "cloud.example.com"
nextcloud_overwrite_protocol: "https"
nextcloud_overwrite_cli_url: "https://cloud.example.com"

# Proxies we trust for X-Forwarded-* (tune for your networks)
trusted_proxies_cidrs:
  - "172.16.0.0/12"
  - "192.168.0.0/16"

# ----- Paths for volumes -----
nc_app_dir: "{{ project_dir }}/nextcloud/app"
nc_data_dir: "{{ project_dir }}/nextcloud/data"
pg_data_dir: "{{ project_dir }}/postgres"

# ----- NGINX (local private entrypoint) -----
nginx_image: "nginx:1.27-alpine"
nginx_dir: "{{ project_dir }}/nginx"
nginx_tls_enabled: true
nginx_bind_ip: "0.0.0.0"       # or "192.168.0.1" to bind only on that IP
nginx_https_port: 443
nginx_http_port: 80            # will 301 redirect to HTTPS

# TLS certificate options:
# A) Generate self-signed cert for cloud.example.local
nginx_generate_self_signed: true
nginx_cert_cn: "cloud.example.local"
nginx_cert_sans:
  - "DNS:cloud.example.local"

# B) If you have real certs, disable generation and point to your files:
# nginx_generate_self_signed: false
# nginx_cert_fullchain_src: "/path/to/fullchain.pem"
# nginx_cert_privkey_src:   "/path/to/privkey.pem"

inventories/prod/group_vars/vault.yml ⟵ Encrypt with Vault
# Nextcloud initial admin
vault_nextcloud_admin_user: "admin"
vault_nextcloud_admin_pass: "CHANGE_ME"

# Database
vault_pg_db: "nextcloud"
vault_pg_user: "nc_user"
vault_pg_password: "CHANGE_ME"

# Cloudflared (token-based tunnel)
vault_cloudflared_tunnel_token: "YOUR_TUNNEL_TOKEN"

Playbook
playbooks/site.yml
---
- name: Deploy Nextcloud stack (compose + systemd)
  hosts: all
  become: true
  gather_facts: true

  vars_files:
    - "../inventories/prod/group_vars/vault.yml"

  roles:
    - nextcloud_stack

Role: defaults, handlers, tasks, templates
roles/nextcloud_stack/defaults/main.yml
# Runtime selection
container_runtime: auto
preferred_runtime: docker
docker_compose_command: "docker compose"
podman_compose_command: "podman-compose"

# Paths & misc
project_dir: "/srv/nextcloud"
compose_project_name: "nextcloud"
stack_network: "nextcloud_net"

use_service_user: true
service_user: nextcloud

# SELinux auto-detect (null => detect)
selinux_enabled: null

# Images
nextcloud_image: "nextcloud:29-apache"
postgres_image: "postgres:16"
redis_image: "redis:7"
cloudflared_image: "cloudflare/cloudflared:latest"

# Features
redis_enabled: true
cloudflared_enabled: true
reverse_proxy: nginx

# Ports (NGINX binds host ports; Nextcloud Apache & Cloudflared use container network)
nginx_bind_ip: "0.0.0.0"
nginx_https_port: 443
nginx_http_port: 80

# Timezone
timezone: "UTC"

roles/nextcloud_stack/handlers/main.yml
---
- name: systemd daemon-reload
  listen: daemon reload
  ansible.builtin.systemd:
    daemon_reload: true

roles/nextcloud_stack/tasks/main.yml
---
# 1) Detect + install prerequisites; set compose_command & container_runtime_resolved
- name: Detect & install prerequisites
  ansible.builtin.include_tasks: prereqs.yml

# 2) Ensure runtime bits (networks, services)
- name: Include runtime prerequisites for {{ container_runtime_resolved }}
  ansible.builtin.include_tasks: "runtime-{{ container_runtime_resolved }}.yml"

# 3) Create service user if enabled
- name: Create service user
  when: use_service_user | bool
  ansible.builtin.user:
    name: "{{ service_user }}"
    create_home: true
    shell: /usr/sbin/nologin
    system: true

# 4) Ensure directories
- name: Create project directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    group: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    mode: "0755"
  loop:
    - "{{ project_dir }}"
    - "{{ nc_app_dir }}"
    - "{{ nc_data_dir }}"
    - "{{ pg_data_dir }}"
    - "{{ nginx_dir }}"
    - "{{ nginx_dir }}/certs"

# 5) Render nginx.conf (reverse_proxy=nginx)
- name: Render nginx.conf (when reverse_proxy=nginx)
  when: reverse_proxy == 'nginx'
  ansible.builtin.template:
    src: "nginx.conf.j2"
    dest: "{{ nginx_dir }}/nginx.conf"
    owner: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    group: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    mode: "0644"

# 6) Ensure nginx certs exist (self-signed or provided)
- name: Ensure nginx certs are present
  when:
    - reverse_proxy == 'nginx'
    - nginx_tls_enabled | bool
  ansible.builtin.include_tasks: nginx-certs.yml

# 7) Render docker-compose.yml
- name: Render compose file
  ansible.builtin.template:
    src: "docker-compose.yml.j2"
    dest: "{{ project_dir }}/docker-compose.yml"
    owner: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    group: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    mode: "0644"

# 8) Install systemd unit
- name: Install systemd unit
  ansible.builtin.template:
    src: "nextcloud-stack.service.j2"
    dest: "/etc/systemd/system/{{ service_name }}.service"
    mode: "0644"
  notify: daemon reload

# 9) Enable + start service
- name: Enable and start service
  ansible.builtin.systemd:
    name: "{{ service_name }}"
    enabled: true
    state: started

# 10) 🔁 Force a fresh redeploy on every Ansible run
- name: Force hard refresh (restart) every run
  ansible.builtin.systemd:
    name: "{{ service_name }}"
    state: restarted

roles/nextcloud_stack/tasks/prereqs.yml
---
# --- Detect SELinux (affects :Z binds) ---
- name: Detect SELinux status
  ansible.builtin.command: getenforce
  register: _getenforce
  changed_when: false
  failed_when: false

- name: Set SELinux fact
  ansible.builtin.set_fact:
    selinux_enabled: "{{ selinux_enabled
      if selinux_enabled is not none
      else (_getenforce.stdout | default('Disabled')) not in ['Disabled','Permissive',''] }}"

# --- Detect runtimes present ---
- name: Check docker binary
  ansible.builtin.command: bash -lc 'command -v docker'
  register: _has_docker_cmd
  changed_when: false
  failed_when: false

- name: Check podman binary
  ansible.builtin.command: bash -lc 'command -v podman'
  register: _has_podman_cmd
  changed_when: false
  failed_when: false

- name: Presence facts
  ansible.builtin.set_fact:
    docker_present: "{{ _has_docker_cmd.rc == 0 }}"
    podman_present: "{{ _has_podman_cmd.rc == 0 }}"

# --- Resolve runtime (auto -> prefer docker, else podman) ---
- name: Resolve container runtime
  ansible.builtin.set_fact:
    container_runtime_resolved: >-
      {{
        (container_runtime != 'auto') | ternary(
          container_runtime,
          docker_present | ternary('docker', podman_present | ternary('podman', preferred_runtime))
        )
      }}

# --- Install runtime (Debian/Ubuntu) ---
- name: Install Docker (Debian/Ubuntu)
  when:
    - container_runtime_resolved == 'docker'
    - not docker_present
    - ansible_os_family == 'Debian'
  ansible.builtin.apt:
    name: [docker.io, docker-compose-plugin]
    state: present
    update_cache: true

- name: Install Podman (Debian/Ubuntu)
  when:
    - container_runtime_resolved == 'podman'
    - not podman_present
    - ansible_os_family == 'Debian'
  ansible.builtin.apt:
    name: [podman, podman-compose]
    state: present
    update_cache: true

# --- Install runtime (RHEL family) ---
- name: Install Docker (RHEL family)
  when:
    - container_runtime_resolved == 'docker'
    - not docker_present
    - ansible_os_family == 'RedHat'
  ansible.builtin.yum:
    name: [docker, docker-compose-plugin]
    state: present

- name: Install Podman (RHEL family)
  when:
    - container_runtime_resolved == 'podman'
    - not podman_present
    - ansible_os_family == 'RedHat'
  ansible.builtin.yum:
    name: [podman, podman-compose]
    state: present

# --- Enable docker service if used ---
- name: Enable & start Docker
  when: container_runtime_resolved == 'docker'
  ansible.builtin.service:
    name: docker
    enabled: true
    state: started

# Rootless Podman convenience
- name: Enable lingering for service user (rootless Podman)
  when:
    - container_runtime_resolved == 'podman'
    - use_service_user | bool
  ansible.builtin.command: "loginctl enable-linger {{ service_user }}"
  changed_when: false
  failed_when: false

# --- Compose command selection ---
- name: Set compose_command (default for resolved runtime)
  ansible.builtin.set_fact:
    compose_command: >-
      {{
        container_runtime_resolved == 'docker'
        | ternary(docker_compose_command, podman_compose_command)
      }}

# Prefer `docker compose` subcommand if available
- name: Check if `docker compose` subcommand exists
  when: container_runtime_resolved == 'docker'
  ansible.builtin.command: bash -lc 'docker compose version'
  register: _dc_subcmd
  changed_when: false
  failed_when: false

- name: Use `docker compose` if subcommand works, else fallback to `docker-compose`
  when: container_runtime_resolved == 'docker'
  ansible.builtin.set_fact:
    compose_command: "{{ (_dc_subcmd.rc == 0) | ternary('docker compose', 'docker-compose') }}"

roles/nextcloud_stack/tasks/runtime-docker.yml
---
- name: Ensure docker is running
  ansible.builtin.service:
    name: docker
    state: started
    enabled: true

- name: Create project network (Docker)
  community.docker.docker_network:
    name: "{{ stack_network }}"
    state: present

roles/nextcloud_stack/tasks/runtime-podman.yml
---
- name: Verify Podman available
  ansible.builtin.command: podman info
  changed_when: false
  failed_when: false

- name: Create project network (Podman)
  containers.podman.podman_network:
    name: "{{ stack_network }}"
    state: present

roles/nextcloud_stack/tasks/nginx-certs.yml
---
# Option A: Generate self-signed cert with DNS SAN for cloud.example.local
- name: Generate self-signed key (if requested)
  when:
    - reverse_proxy == 'nginx'
    - nginx_tls_enabled | bool
    - nginx_generate_self_signed | bool
  community.crypto.openssl_privatekey:
    path: "{{ nginx_dir }}/certs/privkey.pem"
    size: 2048
    type: RSA
    mode: "0600"
    owner: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    group: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"

- name: Generate CSR for self-signed (if requested)
  when:
    - reverse_proxy == 'nginx'
    - nginx_tls_enabled | bool
    - nginx_generate_self_signed | bool
  community.crypto.openssl_csr:
    path: "{{ nginx_dir }}/certs/request.csr"
    privatekey_path: "{{ nginx_dir }}/certs/privkey.pem"
    common_name: "{{ nginx_cert_cn }}"
    subject_alt_name: "{{ nginx_cert_sans }}"
    owner: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    group: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    mode: "0644"

- name: Generate self-signed certificate (if requested)
  when:
    - reverse_proxy == 'nginx'
    - nginx_tls_enabled | bool
    - nginx_generate_self_signed | bool
  community.crypto.openssl_certificate:
    path: "{{ nginx_dir }}/certs/fullchain.pem"
    privatekey_path: "{{ nginx_dir }}/certs/privkey.pem"
    csr_path: "{{ nginx_dir }}/certs/request.csr"
    provider: selfsigned
    valid_days: 825
    owner: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    group: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    mode: "0644"

# Option B: Use provided cert files (copy into place)
- name: Copy provided fullchain.pem
  when:
    - reverse_proxy == 'nginx'
    - nginx_tls_enabled | bool
    - not nginx_generate_self_signed | bool
  ansible.builtin.copy:
    src: "{{ nginx_cert_fullchain_src }}"
    dest: "{{ nginx_dir }}/certs/fullchain.pem"
    owner: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    group: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    mode: "0644"

- name: Copy provided privkey.pem
  when:
    - reverse_proxy == 'nginx'
    - nginx_tls_enabled | bool
    - not nginx_generate_self_signed | bool
  ansible.builtin.copy:
    src: "{{ nginx_cert_privkey_src }}"
    dest: "{{ nginx_dir }}/certs/privkey.pem"
    owner: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    group: "{{ (use_service_user | bool) | ternary(service_user, 'root') }}"
    mode: "0600"

Templates
roles/nextcloud_stack/templates/docker-compose.yml.j2
version: "3.9"

networks:
  default:
    name: {{ stack_network }}

services:
  db:
    image: {{ postgres_image }}
    container_name: {{ compose_project_name }}-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: "{{ vault_pg_db }}"
      POSTGRES_USER: "{{ vault_pg_user }}"
      POSTGRES_PASSWORD: "{{ vault_pg_password }}"
      TZ: "{{ timezone }}"
    volumes:
      - "{{ pg_data_dir }}:/var/lib/postgresql/data{% if ansible_os_family == 'RedHat' and selinux_enabled %}:Z{% endif %}"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U {{ vault_pg_user }} -d {{ vault_pg_db }}"]
      interval: 10s
      timeout: 5s
      retries: 10

  {% if redis_enabled %}
  redis:
    image: {{ redis_image }}
    container_name: {{ compose_project_name }}-redis
    restart: unless-stopped
    command: ["redis-server", "--appendonly", "yes"]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 10
  {% endif %}

  # Nextcloud Apache (serves HTTP on :80 inside the container)
  nextcloud:
    image: {{ nextcloud_image }}
    container_name: {{ compose_project_name }}-app
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
      {% if redis_enabled %}
      redis:
        condition: service_started
      {% endif %}
    environment:
      POSTGRES_HOST: "db"
      POSTGRES_DB: "{{ vault_pg_db }}"
      POSTGRES_USER: "{{ vault_pg_user }}"
      POSTGRES_PASSWORD: "{{ vault_pg_password }}"
      NEXTCLOUD_ADMIN_USER: "{{ vault_nextcloud_admin_user }}"
      NEXTCLOUD_ADMIN_PASSWORD: "{{ vault_nextcloud_admin_pass }}"
      NEXTCLOUD_TRUSTED_DOMAINS: "{{ nextcloud_trusted_domains | join(' ') }}"
      OVERWRITEHOST: "{{ nextcloud_overwrite_host }}"
      OVERWRITEPROTOCOL: "{{ nextcloud_overwrite_protocol }}"
      OVERWRITECLIURL: "{{ nextcloud_overwrite_cli_url }}"
      TRUSTED_PROXIES: "{{ trusted_proxies_cidrs | join(',') }}"
      {% if redis_enabled %}REDIS_HOST: "redis"{% endif %}
      PHP_MEMORY_LIMIT: 1024M
      TZ: "{{ timezone }}"
    volumes:
      - "{{ nc_app_dir }}:/var/www/html{% if ansible_os_family == 'RedHat' and selinux_enabled %}:Z{% endif %}"
      - "{{ nc_data_dir }}:/var/www/html/data{% if ansible_os_family == 'RedHat' and selinux_enabled %}:Z{% endif %}"

  {% if reverse_proxy == 'nginx' %}
  # Local HTTPS: 443 on host => NGINX => nextcloud:80
  nginx:
    image: {{ nginx_image }}
    container_name: {{ compose_project_name }}-nginx
    restart: unless-stopped
    depends_on:
      - nextcloud
    ports:
      - "{{ nginx_bind_ip }}:{{ nginx_https_port }}:443"
      - "{{ nginx_bind_ip }}:{{ nginx_http_port }}:80"
    volumes:
      - "{{ nginx_dir }}/nginx.conf:/etc/nginx/nginx.conf{% if ansible_os_family == 'RedHat' and selinux_enabled %}:Z{% endif %}"
      - "{{ nginx_dir }}/certs:/etc/nginx/certs:ro{% if ansible_os_family == 'RedHat' and selinux_enabled %}:Z{% endif %}"
  {% endif %}

  {% if cloudflared_enabled %}
  # Public HTTPS via Cloudflare Tunnel -> http://nextcloud:80
  cloudflared:
    image: {{ cloudflared_image }}
    container_name: {{ compose_project_name }}-cloudflared
    restart: unless-stopped
    depends_on:
      - nextcloud
    command: ["tunnel", "run"]
    environment:
      TUNNEL_TOKEN: "{{ vault_cloudflared_tunnel_token }}"
  {% endif %}

roles/nextcloud_stack/templates/nginx.conf.j2
user  nginx;
worker_processes  auto;

events { worker_connections 1024; }

http {
  include       /etc/nginx/mime.types;
  default_type  application/octet-stream;

  sendfile on;
  tcp_nopush on;
  tcp_nodelay on;
  keepalive_timeout 65;
  client_max_body_size 1024M;

  upstream nextcloud_upstream {
    server {{ compose_project_name }}-app:80;
    keepalive 32;
  }

  # HTTP listener → redirect to HTTPS
  server {
    listen 80 default_server;
    server_name cloud.example.local _;
    return 301 https://$host$request_uri;
  }

  # HTTPS listener with local cert
  server {
    listen 443 ssl http2 default_server;
    server_name cloud.example.local;

    ssl_certificate     /etc/nginx/certs/fullchain.pem;
    ssl_certificate_key /etc/nginx/certs/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    location / {
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto https;
      proxy_pass http://nextcloud_upstream;
      proxy_http_version 1.1;
      proxy_read_timeout 3600s;
      proxy_send_timeout 3600s;
      proxy_request_buffering off;
    }

    client_body_timeout 3600s;
    send_timeout 3600s;

    add_header X-Content-Type-Options nosniff;
    add_header Referrer-Policy no-referrer;
  }
}

roles/nextcloud_stack/templates/nextcloud-stack.service.j2
[Unit]
Description=Nextcloud stack ({{ container_runtime_resolved|title }}) — hard refresh (terminate -> prune -> pull -> redeploy)
Wants=network-online.target
After=network-online.target {% if container_runtime_resolved == 'docker' %}docker.service{% else %}multi-user.target{% endif %}
{% if container_runtime_resolved == 'docker' -%}
Requires=docker.service
{%- endif %}

[Service]
{% if use_service_user -%}
User={{ service_user }}
Group={{ service_user }}
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus
Environment=XDG_RUNTIME_DIR=/run/user/%U
{%- endif %}
Type=oneshot
RemainAfterExit=yes

Environment=COMPOSE_PROJECT_NAME={{ compose_project_name }}
Environment=COMPOSE_FILE={{ project_dir }}/docker-compose.yml
WorkingDirectory={{ project_dir }}
{% if use_service_user -%}
Environment=PATH=/usr/local/bin:/usr/bin:/bin
{%- endif %}

# ===== PRE-START CLEANUP =====
ExecStartPre=/bin/sh -lc '{% if not use_service_user %}/usr/bin/{% endif %}{{ compose_command }} -f "$COMPOSE_FILE" down --timeout 25 --remove-orphans || true'
{% if container_runtime_resolved == 'podman' -%}
ExecStartPre=/bin/sh -lc '{% if not use_service_user %}/usr/bin/{% endif %}podman ps -aq --filter "label=io.podman.compose.project=$COMPOSE_PROJECT_NAME" | xargs -r {% if not use_service_user %}/usr/bin/{% endif %}podman rm -f || true'
{% else -%}
ExecStartPre=/bin/sh -lc '{% if not use_service_user %}/usr/bin/{% endif %}docker ps -aq --filter "label=com.docker.compose.project=$COMPOSE_PROJECT_NAME" | xargs -r {% if not use_service_user %}/usr/bin/{% endif %}docker rm -f || true'
{%- endif %}
ExecStartPre=/bin/sh -lc '{% if not use_service_user %}/usr/bin/{% endif %}{{ container_runtime_resolved }} network ls --format "{%raw%}{{.Name}}{%endraw%}" | grep -x "$COMPOSE_PROJECT_NAME_web" >/dev/null 2>&1 && {% if not use_service_user %}/usr/bin/{% endif %}{{ container_runtime_resolved }} network rm "$COMPOSE_PROJECT_NAME_web" || true'
{% if container_runtime_resolved == 'podman' -%}
ExecStartPre=/bin/sh -lc '{% if not use_service_user %}/usr/bin/{% endif %}podman system prune -f || true'
{% else -%}
ExecStartPre=/bin/sh -lc '{% if not use_service_user %}/usr/bin/{% endif %}docker system prune -f || true'
{%- endif %}
ExecStartPre=/bin/sh -lc '{% if not use_service_user %}/usr/bin/{% endif %}{{ container_runtime_resolved }} pull $( {{ compose_command }} -f "$COMPOSE_FILE" config --images ) || true'

# ===== START (force recreate) =====
ExecStart={% if not use_service_user %}/usr/bin/{% endif %}{{ compose_command }} -f "$COMPOSE_FILE" up -d --force-recreate --remove-orphans

# ===== STOP (graceful) =====
ExecStop=/bin/sh -lc '{% if not use_service_user %}/usr/bin/{% endif %}{{ compose_command }} -f "$COMPOSE_FILE" down --timeout 25 --remove-orphans || true'

{% if container_runtime_resolved == 'podman' and use_service_user -%}
ExecStopPost=/bin/sh -lc 'podman system prune -f || true'
{%- endif %}

Restart=on-failure
TimeoutStartSec=0
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target

🚀 Run it

Install collections:

ansible-galaxy collection install -r requirements.yml


Put secrets in inventories/prod/group_vars/vault.yml and encrypt:

ansible-vault create inventories/prod/group_vars/vault.yml


Point your LAN DNS so cloud.example.local → your server’s LAN IP (e.g., 192.168.0.1).

Deploy:

ansible-playbook playbooks/site.yml --ask-vault-pass


Local: open https://cloud.example.local (you’ll trust the self-signed cert unless you provide a real one).

Public: configure your Cloudflare Tunnel’s Public Hostname:
cloud.example.com → HTTP → Service = http://nextcloud:80.

If you want anything tweaked (e.g., pinning image tags to latest, disabling Redis, or binding NGINX to a single IP), just tell me what to change and I’ll update the code.