#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
REQUIREMENTS_FILE="requirements.yml"

# --- Functions ---
log() { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
die() { echo -e "\033[1;31m[!] $*\033[0m"; exit 1; }

# Detect package manager
detect_pkg_mgr() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  else
    die "No supported package manager found (apt, dnf, yum)."
  fi
}

PKG_MGR=$(detect_pkg_mgr)

# Install packages
install_pkgs() {
  local pkgs=("$@")
  case "$PKG_MGR" in
    apt)
      log "Updating apt cache..."
      sudo apt-get update -y
      log "Installing: ${pkgs[*]}"
      sudo apt-get install -y "${pkgs[@]}"
      ;;
    dnf|yum)
      log "Installing: ${pkgs[*]}"
      sudo $PKG_MGR install -y "${pkgs[@]}"
      ;;
  esac
}

# Ensure ansible
ensure_ansible() {
  if ! command -v ansible >/dev/null 2>&1; then
    log "Ansible not found, installing..."
    if [ "$PKG_MGR" = "apt" ]; then
      install_pkgs software-properties-common
      sudo apt-add-repository --yes --update ppa:ansible/ansible || true
      install_pkgs ansible
    else
      install_pkgs ansible
    fi
  else
    log "Ansible already installed: $(ansible --version | head -n1)"
  fi
}

# Ensure Python3 + pip
ensure_python() {
  if ! command -v python3 >/dev/null 2>&1; then
    log "Installing Python3..."
    install_pkgs python3 python3-pip
  fi
  if ! command -v pip3 >/dev/null 2>&1; then
    log "Installing pip3..."
    install_pkgs python3-pip
  fi
}

# Ensure deps like git/curl
ensure_basic_deps() {
  local deps=(git curl rsync)
  for d in "${deps[@]}"; do
    if ! command -v "$d" >/dev/null 2>&1; then
      missing+=("$d")
    fi
  done
  if [ "${#missing[@]:-0}" -gt 0 ]; then
    log "Installing missing deps: ${missing[*]}"
    install_pkgs "${missing[@]}"
  fi
}

# Install galaxy collections
install_collections() {
  if [ -f "$REQUIREMENTS_FILE" ]; then
    log "Installing Ansible Galaxy collections from $REQUIREMENTS_FILE..."
    ansible-galaxy collection install -r "$REQUIREMENTS_FILE"
  else
    warn "No $REQUIREMENTS_FILE found, skipping galaxy collections."
  fi
}

# --- Main ---
log "Bootstrapping Ansible environment..."

ensure_python
ensure_ansible
ensure_basic_deps
install_collections

log "Done! You can now run: ansible-playbook playbooks/site.yml --ask-vault-pass"
