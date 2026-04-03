variable "workers" {
  description = "Map of worker VMs to create. Key = VM/node name."
  type = map(object({
    vcpus   = number
    ram_mb  = number
    disk_gb = number
  }))
}

variable "base_image_path" {
  description = "Absolute path to the Ubuntu cloud image on the host."
  type        = string
  default     = "/home/yibofu/vms/images/ubuntu-24.04-server-cloudimg-amd64.img"
}

variable "pool_dir" {
  description = "Directory for the libvirt storage pool used by Terraform-managed VMs."
  type        = string
  default     = "/var/lib/libvirt/k8s-workers"
}

variable "bridge_name" {
  description = "Host bridge interface to attach VMs to."
  type        = string
  default     = "br0"
}

variable "ssh_user" {
  description = "Username created inside each VM via cloud-init."
  type        = string
  default     = "yibofu"
}

variable "ssh_public_key" {
  description = "SSH public key injected into each VM."
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key (used by the sync script, not by Terraform directly)."
  type        = string
  default     = "/home/yibofu/.ssh/id_ed25519"
}

variable "k8s_version" {
  description = "Kubernetes minor version for the apt repo (e.g. '1.35')."
  type        = string
  default     = "1.35"
}

variable "control_plane_ip" {
  description = "IP address of the Kubernetes control plane."
  type        = string
  default     = "192.168.15.10"
}

variable "control_plane_user" {
  description = "SSH user on the control plane node (for token generation)."
  type        = string
  default     = "yibofu"
}

variable "node_labels" {
  description = "Labels applied to every worker node after join."
  type        = map(string)
  default     = { nodepool = "compute" }
}
