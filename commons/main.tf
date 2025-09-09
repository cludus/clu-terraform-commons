
terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.81.0"
    }
  }
}

variable "nodes" {
  type = list(string)
}

// Resource to download the Alpine Linux cloud image
resource "proxmox_virtual_environment_download_file" "alpine" {
  for_each     = toset(var.nodes)
  content_type = "iso"
  datastore_id = "local"
  node_name    = each.value
  url          = "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/cloud/nocloud_alpine-3.22.1-x86_64-bios-cloudinit-r0.qcow2"
  file_name    = "alpine.img"
}

// Resource to download the Ubuntu cloud image
resource "proxmox_virtual_environment_download_file" "ubuntu" {
  for_each     = toset(var.nodes)
  content_type = "iso"
  datastore_id = "local"
  node_name    = each.value
  url          = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
  file_name    = "ubuntu.img"
}

// Output the IDs of the downloaded cloud images
output "cloudimg" {
  value = {
    alpine = proxmox_virtual_environment_download_file.alpine[*].id,
    ubuntu = proxmox_virtual_environment_download_file.ubuntu[*].id
  }
}
