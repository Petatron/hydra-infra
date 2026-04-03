#cloud-config
hostname: ${hostname}
manage_etc_hosts: true

users:
  - name: ${ssh_user}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_public_key}

ssh_pwauth: false
package_update: true

packages:
  - qemu-guest-agent
  - containerd
  - apt-transport-https
  - ca-certificates
  - curl
  - gpg

write_files:
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter
  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1

runcmd:
  # --- guest agent (gives Terraform the VM IP) ---
  - systemctl enable --now qemu-guest-agent

  # --- swap off ---
  - swapoff -a
  - sed -i '/ swap / s/^/#/' /etc/fstab
  - sed -i '/swap.img/ s/^/#/' /etc/fstab || true

  # --- kernel modules + sysctl ---
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system

  # --- containerd config (systemd cgroup driver) ---
  - mkdir -p /etc/containerd
  - containerd config default > /etc/containerd/config.toml
  - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  - systemctl restart containerd
  - systemctl enable containerd

  # --- kubernetes apt repo (v${k8s_version}) ---
  - mkdir -p -m 755 /etc/apt/keyrings
  - "curl -fsSL https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
  - chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - "echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${k8s_version}/deb/ /' > /etc/apt/sources.list.d/kubernetes.list"
  - chmod 644 /etc/apt/sources.list.d/kubernetes.list

  # --- install kubeadm suite ---
  - apt-get update
  - apt-get install -y kubelet kubeadm kubectl
  - apt-mark hold kubelet kubeadm kubectl
