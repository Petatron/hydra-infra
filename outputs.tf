output "worker_ips" {
  description = "Map of worker name → list of IP addresses."
  value = {
    for name, domain in libvirt_domain.worker :
    name => domain.network_interface[0].addresses
  }
}

output "worker_names" {
  description = "List of all managed worker node names."
  value       = keys(libvirt_domain.worker)
}

output "control_plane_ip" {
  description = "Control plane IP (passthrough for scripts)."
  value       = var.control_plane_ip
}

output "ssh_user" {
  value = var.ssh_user
}

output "ssh_private_key_path" {
  value     = var.ssh_private_key_path
  sensitive = true
}

output "control_plane_user" {
  value = var.control_plane_user
}

output "node_labels" {
  value = var.node_labels
}
