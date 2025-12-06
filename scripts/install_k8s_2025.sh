#!/bin/bash
# Kubernetes single-node control-plane setup
# by Jayden Aung
# Tested Dec 2025 on:
#   - Ubuntu 24.04 LTS (noble) amd64/arm64
#   - Ubuntu 22.04 LTS (jammy) amd64/arm64
# Kubernetes:
#   - kubeadm / kubelet / kubectl v1.34 via pkgs.k8s.io apt repo
#
# IMPORTANT:
#   - Run as your normal user (not root), with sudo privileges.
#   - Re-running is mostly idempotent; kubeadm init is skipped if already done.

set -euo pipefail

K8S_MINOR_VERSION="v1.34"   # For pkgs.k8s.io repo path
HOSTNAME_DEFAULT="controller"

log()  { echo -e "[INFO ] $*"; }
warn() { echo -e "[WARN ] $*" >&2; }
err()  { echo -e "[ERROR] $*" >&2; }

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    err "Required command '$1' not found. Please install it and re-run."
    exit 1
  fi
}

append_if_missing() {
  local line="$1"
  local file="$2"
  if [ ! -f "$file" ]; then
    echo "$line" > "$file"
    return
  fi
  if ! grep -qxF "$line" "$file" 2>/dev/null; then
    echo "$line" >> "$file"
  fi
}

#---------------------------
# Basic sanity checks
#---------------------------

require_cmd lsb_release
require_cmd dpkg

if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release
else
  err "/etc/os-release not found; unsupported OS."
  exit 1
fi

case "${ID:-}" in
  ubuntu) ;;
  *)
    err "This script is intended for Ubuntu. Detected ID=${ID:-unknown}."
    exit 1
    ;;
esac

UBUNTU_VERSION="${VERSION_ID:-unknown}"
if [[ "$UBUNTU_VERSION" != "24.04" && "$UBUNTU_VERSION" != "22.04" ]]; then
  warn "Ubuntu $UBUNTU_VERSION detected. Script is tested on 22.04 and 24.04; continuing anyway..."
fi

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64|arm64)
    log "Architecture: $ARCH (supported)"
    ;;
  *)
    err "Unsupported architecture: $ARCH. Only amd64 and arm64 are supported."
    exit 1
    ;;
esac

if [[ $EUID -eq 0 ]]; then
  warn "You are running as root. For best results, run as a normal user with sudo."
fi

require_cmd sudo

#---------------------------
# Hostname / timezone / QoL
#---------------------------

if [[ "$(hostname)" != "$HOSTNAME_DEFAULT" ]]; then
  log "Setting hostname to $HOSTNAME_DEFAULT"
  sudo hostnamectl set-hostname "$HOSTNAME_DEFAULT"
else
  log "Hostname already set to $HOSTNAME_DEFAULT"
fi

log "Setting timezone to Asia/Singapore"
if ! sudo timedatectl set-timezone Asia/Singapore; then
  warn "Failed to set timezone (non-fatal)."
fi

log "Updating apt package index..."
sudo apt-get update -y

log "Installing base tools (bash-completion, binutils, vim)..."
sudo apt-get install -y bash-completion binutils vim

# .vimrc and .bashrc tweaks for the CURRENT user (not root)
append_if_missing 'colorscheme ron'        "$HOME/.vimrc"
append_if_missing 'set tabstop=2'          "$HOME/.vimrc"
append_if_missing 'set shiftwidth=2'       "$HOME/.vimrc"
append_if_missing 'set expandtab'          "$HOME/.vimrc"

append_if_missing 'force_color_prompt=yes' "$HOME/.bashrc"
append_if_missing 'alias k=kubectl'        "$HOME/.bashrc"
append_if_missing 'alias c=clear'          "$HOME/.bashrc"
append_if_missing 'source <(kubectl completion bash)' "$HOME/.bashrc"
append_if_missing 'complete -F __start_kubectl k'    "$HOME/.bashrc"

#---------------------------
# Disable swap (required by kubeadm)
#---------------------------

log "Disabling swap..."
if sudo swapon --show | grep -q .; then
  sudo swapoff -a
else
  log "Swap already disabled."
fi

# Comment out any swap entries in /etc/fstab
if sudo grep -qE '^[^#].*\sswap\s' /etc/fstab; then
  sudo cp /etc/fstab /etc/fstab.bak.$(date +%s) || true
  sudo sed -i '/\sswap\s/s/^\(.*\)$/# \1/' /etc/fstab || true
fi

#---------------------------
# Kernel modules & sysctl for Kubernetes networking
#---------------------------

log "Configuring kernel modules for Kubernetes networking..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF

sudo modprobe overlay || warn "modprobe overlay failed (non-fatal)."
sudo modprobe br_netfilter || warn "modprobe br_netfilter failed (non-fatal)."

log "Configuring sysctl parameters for Kubernetes..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system >/dev/null

#---------------------------
# Container runtime: containerd
#---------------------------

log "Installing containerd (if not already present)..."
if ! command -v containerd >/dev/null 2>&1; then
  sudo apt-get install -y containerd
else
  log "containerd already installed."
fi

log "Configuring containerd with SystemdCgroup = true..."
sudo mkdir -p /etc/containerd
if [ ! -f /etc/containerd/config.toml ]; then
  sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
fi

# Ensure SystemdCgroup = true
sudo sed -i -E 's/^(\s*SystemdCgroup\s*=\s*)false/\1true/' /etc/containerd/config.toml

sudo systemctl restart containerd
sudo systemctl enable containerd >/dev/null

#---------------------------
# Kubernetes apt repo (pkgs.k8s.io) & packages
#---------------------------

log "Installing Kubernetes apt prerequisites..."
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

log "Configuring Kubernetes apt repository for ${K8S_MINOR_VERSION}..."
sudo mkdir -p -m 755 /etc/apt/keyrings

# According to upstream kubeadm docs for v1.34 on Debian/Ubuntu
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${K8S_MINOR_VERSION}/deb/Release.key" \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Overwrite kubernetes.list safely
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${K8S_MINOR_VERSION}/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

log "Installing kubelet, kubeadm, kubectl..."
sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# Kubelet will be started by systemd and will wait for kubeadm to configure it
sudo systemctl enable --now kubelet || warn "Failed to enable kubelet (may already be running)."

#---------------------------
# kubeadm init (control-plane)
#---------------------------

if [ ! -f /etc/kubernetes/admin.conf ]; then
  log "Initializing Kubernetes control-plane with kubeadm (single-node)..."
  # Pod CIDR 192.168.0.0/16 matches Calico defaults and kubeadm examples
  sudo kubeadm init \
    --pod-network-cidr=192.168.0.0/16 \
    --node-name="$(hostname)"

  log "kubeadm init completed."
else
  warn "/etc/kubernetes/admin.conf already exists; skipping kubeadm init (cluster already initialized)."
fi

#---------------------------
# kubeconfig for current user
#---------------------------

log "Configuring kubectl for user: $USER ..."
mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

#---------------------------
# Calico CNI (latest)
#---------------------------

log "Installing Calico CNI (latest from docs.tigera.io)..."
# Calico 3.31+ supports recent Kubernetes versions and autodetects CIDR for kubeadm clusters.
kubectl apply -f "https://docs.tigera.io/calico/latest/manifests/calico.yaml"

#---------------------------
# Make this a schedulable single-node cluster
#---------------------------

log "Removing control-plane taint so workloads can run on this node..."
NODE_NAME="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"

if [ -n "$NODE_NAME" ]; then
  kubectl taint nodes "$NODE_NAME" node-role.kubernetes.io/control-plane:NoSchedule- || true
else
  warn "Could not determine node name to untaint (kubectl get nodes returned empty)."
fi

log "Cluster nodes:"
kubectl get nodes -o wide

log "Setup complete. Open a new shell to load updated .bashrc aliases and kubectl completion."

