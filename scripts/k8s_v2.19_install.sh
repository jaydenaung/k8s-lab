#!/bin/bash
# THIS WORKS ON UBUNTU 22.04 LTS 64bit
# Author: Jayden Aung
# Email: jaydenaung@protonmail.com
# Date: 26 April 2024

VERSION="1.29.1-00"

# ANSI color codes
#RED='\033[0;31m'
#GREEN='\033[0;32m'
#NC='\033[0m' # No color

echo "This script will install Kubernetes on your Ubuntu server - Jayden." 
echo "[Install Helper] Running Prerequisites.."
sudo timedatectl set-timezone Asia/Singapore

sudo apt-get update && apt-get install -y bash-completion binutils
sudo apt-get net-tools
echo 'colorscheme ron' >> ~/.vimrc
echo 'set tabstop=2' >> ~/.vimrc
echo 'set shiftwidth=2' >> ~/.vimrc
echo 'set expandtab' >> ~/.vimrc
sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc

echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'alias c=clear' >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc

echo "[Install Helper] Creating configuration file for containerd.."
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

echo "[Install Helper] Loading modules.."
sudo modprobe overlay
sudo modprobe br_netfilter

echo "[Install Helper] Setting system configurations for Kubernetes networking."
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

echo "[Install Helper] Applying the settings."
sudo sysctl --system

echo "[Install Helper] Installing containerd."
sudo apt-get update && sudo apt-get install -y containerd

echo "[Install Helper] Create default config file for containerd"
sudo mkdir -p /etc/containerd

echo "[Install Helper] Generating default containerd configuration and save to the newly created default file."
sudo containerd config default | sudo tee /etc/containerd/config.toml

echo "[Install Helper] Restarting Restart containerd to ensure new configuration file usage."
sudo systemctl restart containerd
sudo systemctl enable containerd

echo "[Install Helper] Disabling SWAP."
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "Installing dependencies."
sudo apt-get update && sudo apt-get install -y apt-transport-https curl gpg

echo "[Install Helper] Creating keyrings and Downloading the public signing key for the Kubernetes package repositories.."
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "[Install Helper] Adding Repos.."
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list


echo "[Install Helper] Doing Pre-install."
sudo apt-get update

echo "[Install Helper] Installing kubelet kubeadm and kubectl.."
sudo apt-get install -y kubelet kubeadm kubectl

#sudo apt install -y kubelet=$VERSION kubeadm=$VERSION kubectl=$VERSION
sudo apt-mark hold kubelet kubeadm kubectl

#Optional
sudo systemctl enable --now kubelet

#sudo kubeadm init --pod-network-cidr 192.168.0.0/16 --apiserver-advertise-address 10.0.0.71


mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
