# ---------------------------------------------------------------------------
# Storage pool — dedicated directory for Terraform-managed VM disks
# ---------------------------------------------------------------------------
resource "libvirt_pool" "k8s" {
  name = "k8s-workers"
  type = "dir"
  path = var.pool_dir
}

# ---------------------------------------------------------------------------
# Base volume — uploaded once from the local cloud image
# ---------------------------------------------------------------------------
resource "libvirt_volume" "base" {
  name   = "ubuntu-24.04-base.qcow2"
  pool   = libvirt_pool.k8s.name
  source = var.base_image_path
  format = "qcow2"
}

# ---------------------------------------------------------------------------
# Per-worker overlay volume (copy-on-write from base)
# ---------------------------------------------------------------------------
resource "libvirt_volume" "worker" {
  for_each       = var.workers
  name           = "${each.key}.qcow2"
  pool           = libvirt_pool.k8s.name
  base_volume_id = libvirt_volume.base.id
  size           = each.value.disk_gb * 1073741824
  format         = "qcow2"
}

# ---------------------------------------------------------------------------
# Cloud-init ISO per worker (user-data + meta-data)
# ---------------------------------------------------------------------------
resource "libvirt_cloudinit_disk" "worker" {
  for_each = var.workers
  name     = "${each.key}-cloudinit.iso"
  pool     = libvirt_pool.k8s.name

  user_data = templatefile("${path.module}/templates/user-data.tpl", {
    hostname       = each.key
    ssh_user       = var.ssh_user
    ssh_public_key = var.ssh_public_key
    k8s_version    = var.k8s_version
  })

  meta_data = templatefile("${path.module}/templates/meta-data.tpl", {
    hostname = each.key
  })
}

# ---------------------------------------------------------------------------
# VM domain per worker
# ---------------------------------------------------------------------------
resource "libvirt_domain" "worker" {
  for_each  = var.workers
  name      = each.key
  vcpu      = each.value.vcpus
  memory    = each.value.ram_mb
  autostart = true
  qemu_agent = true

  cloudinit = libvirt_cloudinit_disk.worker[each.key].id

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.worker[each.key].id
  }

  network_interface {
    bridge         = var.bridge_name
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  lifecycle {
    ignore_changes = [
      # cloud-init ISO is consumed on first boot; avoid spurious diffs
      # when only the template rendering changes whitespace
    ]
  }
}
