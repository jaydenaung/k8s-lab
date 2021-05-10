# k8s-lab
Kubernetes Lab

# Set up K8s on Ubuntu 20.04 on VM
### Master

```bash
sudo hostnamectl set-hostname controller
sudo timedatectl set-timezone Asia/Singapore
```

### Worker 1
```bash
sudo hostnamectl set-hostname worker1
```

### Worker 2
```bash
sudo hostnamectl set-hostname worker2
```

```bash
cat >>/etc/hosts<<EOF
10.2.2.5 controller.k8 controller
10.2.2.6 worker1.k8 worker1
10.2.2.7 worker2.k8 worker2
EOF
```
## Create configuration file for docker
```bash
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
```
### Load modules
```
sudo modprobe overlay
sudo modprobe br_netfilter
```
### Set system configurations for Kubernetes networking
```bash
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
```

# Apply the settings immediately
```bash
sudo sysctl --system
```

# Prerequisites Docker
```bash
sudo apt-get update && \
sudo apt-get install -y apt-transport-https ca-certificates curl lsb-release gnupg
```

# Install Docker
```bash
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
```

```bash
echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
```
```bash
sudo apt-get update -y
sudo apt-get install docker-ce docker-ce-cli containerd.io -y
```

### Disable SWAP
```
sudo swapoff -a
```
### For Ubuntu 20.04
```bash
sudo sed -i '/swap.img/d' /etc/fstab
```

To check SWAP and there should be no output:
```
sudo swapon --show 
```

-  Install dependency packages:

```bash
sudo apt-get update && sudo apt-get install -y apt-transport-https curl
```
**Download the Google Cloud public signing key:**

```bash
sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg \
https://packages.cloud.google.com/apt/doc/apt-key.gpg
```

**Add the Kubernetes apt repository:**
```bash
echo \
"deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

Update package listings:
```
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
```

```
#sudo apt-get update
#sudo apt-get install -y kubelet kubeadm kubectl
#sudo apt-mark hold kubelet kubeadm kubectl

```
Install Kubernetes packages (Note: If you get a dpkg lock message, just wait a minute or two before trying the command again):
#sudo apt-get install -y kubelet=1.20.1-00 kubeadm=1.20.1-00 kubectl=1.20.1-00

Turn off automatic updates
```bash
sudo apt-mark hold kubelet kubeadm kubectl
```
>If you're running docker
```
sudo mkdir /etc/docker
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
```

Note: overlay2 is the preferred storage driver for systems running Linux kernel version 4.0 or higher, or RHEL or CentOS using version 3.10.0-514 and above.

```
sudo systemctl enable docker
sudo systemctl daemon-reload
sudo systemctl restart docker
```
 ## Initialize the Cluster 

 Initialize the Kubernetes cluster on the control plane node using kubeadm (Note: This is only performed on the Control Plane Node):
 sudo kubeadm init --pod-network-cidr 192.168.0.0/16 --apiserver-advertise-address 10.2.2.5


 # Set kubectl access:
 ```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
Test access to cluster:
```
kubectl version
```

###Install the Calico Network Add-On
On the Control Plane Node, install Calico Networking:
```
 kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
```

 Check status of Calico components:

 ```
 kubectl get pods -n kube-system
```

 ## Join the Worker Nodes to the Cluster 
 In the Control Plane Node, create the token and copy the kubeadm join command 
 >(NOTE:The join command can also be found in the output from kubeadm init command):

 ```
 kubeadm token create --print-join-command
 ```

 On both Worker Nodes, paste the kubeadm join command to join the cluster:

> RUN JOIN COMMAND ONLY AS ROOT USER
```
 sudo kubeadm join <join command from previous command>
```
```bash
 kubeadm join 10.0.0.32:6443 --token cffnsb.ct4ek02lc2dujj95 \
	--discovery-token-ca-cert-hash sha256:c571066522b4941e038f6f0e05ab7adaac37ca51b2889f7a639f7c8596619b75 
```

On both Worker Nodes, paste the kubeadm join command to join the cluster:
```
 kubectl get nodes
```

On the Control Plane Node, view cluster status (Note: You may have to wait a few moments to allow the cluster to become ready):

```
 kubectl get nodes
```


 ### Public IP (AWS)

```bash
aws ec2 describe-instances \
--filters Name=tag:project,Values=eksdemo \
--query "Reservations[*].Instances[*].{InstanceId:InstanceId,IPAddress:PublicIpAddress,PrivateIP:PrivateIpAddress}" \
--output table
```

