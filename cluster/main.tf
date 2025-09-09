terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.81.0"
    }
  }
}

// Variable for the base VM ID
variable "base_vm_id" {
  type = number
}

// Variable for the cluster name
variable "cluster" {
  type = string
}

// Variable for the cluster network base address
variable "cluster_net" {
  type = string
}

// Variable for the cloud image to use
variable "cloudimg" {
  type = map(string)
}

// Variable for the network gateway
variable "gateway" {
  type = string
}

// Variable for the VLAN ID
variable "vlan" {
  type = number
}

// Variable for the network bridge to use
variable "bridge" {
  type = string
}

// Variable for the dns servers
variable "dns_servers" {
  type = list(string)
}

// Variable for the list of VM configurations
variable "vms" {
  type = map(object({
    ordinal    = number
    kube_type  = string
    memory     = number
    cpus       = number
    sockets    = number
    disk_id    = string
    disk_size  = number
    node       = string
    tags       = list(string)
  }))
}

// Resource to define VMs in the cluster
resource "proxmox_virtual_environment_vm" "vm" {
  for_each    = var.vms
  name        = "${var.cluster}${each.key}-${each.value.kube_type}"
  description = "${var.cluster}${each.key} ${each.value.kube_type}"
  tags        = each.value.tags

  node_name   = each.value.node
  vm_id       = var.base_vm_id + each.value.ordinal

  memory {
    dedicated = each.value.memory
  }

  cpu {
    cores = each.value.cpus
    sockets = each.value.sockets
  }

  agent {
    // read 'Qemu guest agent' section, change to true only when ready
    enabled = false
  }

  // if agent is not enabled, the VM may not be able to shutdown properly, and may need to be forced off
  stop_on_destroy = true

  startup {
    order      = each.value.ordinal
    up_delay   = "60"
    down_delay = "60"
  }

  disk {
    datastore_id = each.value.disk_id
    file_id      = var.cloudimg[each.value.node]
    interface    = "scsi0"
    size         = each.value.disk_size
  }

  network_device {
    bridge   = var.bridge
    vlan_id  = var.vlan
  }

  operating_system {
    type = "l26"
  }

  tpm_state {
    version = "v2.0"
  }

  serial_device {}

  initialization {
    ip_config {
      ipv4 {
        address = "${var.cluster_net}.${each.value.ordinal+30}/23"
        gateway = "${var.gateway}"
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      keys     = [trimspace(tls_private_key.vm_key[each.key].public_key_openssh)]
      password = random_password.vm_password[each.key].result
      username = "alpine"
    }
  }
}

// Resource to generate random cluster token
resource "random_password" "cluster_token" {
  length           = 64
  special          = false
}

// Resource to generate random passwords for the VMs
resource "random_password" "vm_password" {
  for_each         = var.vms
  length           = 32
  override_special = "_%@"
  special          = true
}

// Resource to generate RSA private keys for the VMs
resource "tls_private_key" "vm_key" {
  for_each    = var.vms
  algorithm   = "RSA"
  rsa_bits    = 2048
}

// Output sensitive access information for the cluster VMs
output "access" {
  value     = {
    os            = [for k, v in var.vms : "alpine"]
    server_type   = [for k, v in var.vms : "${v.kube_type}"]
    name          = [for k, v in var.vms : "${var.cluster}${k}"]
    cluster_name  = [for k, v in var.vms : "${var.cluster}"]
    cluster_token = [for k, v in var.vms : random_password.cluster_token.result]
    ip_address    = [for k, v in var.vms : "${var.cluster_net}.${v.ordinal+100}"]
    password      = [for k, v in var.vms : random_password.vm_password[k].result]
    public_key    = [for k, v in var.vms : tls_private_key.vm_key[k].public_key_openssh]
    private_key   = [for k, v in var.vms : tls_private_key.vm_key[k].private_key_openssh]
    disk_type     = [for k, v in var.vms : "${v.disk_id}"]
  }
  sensitive = true
}

