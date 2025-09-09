terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      version = "0.81.0"
    }
  }
}

// Variable for the router name
variable "name" {
  type = string
}

// Variable for the VM ID
variable "vm_id" {
  type = string
}

// Variable for the router's IP address
variable "ip" {
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

variable "bridge" {
  type = string
}

variable "node" {
  type = string
}

variable "dns_servers" {
  type = list(string)
}

// Variable for the first network configuration
variable "net" {
  type = object({
    vlan = string
    cidr = string
  })
}

variable "tags" {
  type = list(string)
}

// Resource to define the first VLAN for the router
resource "proxmox_virtual_environment_network_linux_vlan" "lan" {
  name     = "${var.bridge}.${var.net.vlan}"
  node_name = var.node
  comment   = "${var.name}-lan"
}

// Resource to define the router VM with its configuration
resource "proxmox_virtual_environment_vm" "proxy" {
  depends_on = [ 
    proxmox_virtual_environment_network_linux_vlan.lan,
  ]
  name        = var.name
  description = var.name
  tags        = var.tags

  // Node where the VM will be created
  node_name   = var.node
  vm_id       = var.vm_id

  // Memory configuration for the VM
  memory {
    dedicated = 2 * 1024
  }

  // CPU configuration for the VM
  cpu {
    cores = 2
    sockets = 1
  }

  // Configuration for the Qemu guest agent
  agent {
    // read 'Qemu guest agent' section, change to true only when ready
    enabled = false
  }

  // If agent is not enabled, the VM may not be able to shutdown properly, and may need to be forced off
  stop_on_destroy = true

  // Startup configuration for the VM
  startup {
    order      = 1
    up_delay   = "60"
    down_delay = "60"
  }

  // Disk configuration for the VM
  disk {
    datastore_id = "local-lvm"
    file_id      = var.cloudimg[var.node]
    interface    = "scsi0"
    size         = 20
  }

  // Network device configuration for the VM
  network_device {
    bridge   = var.bridge
  }

  network_device {
    bridge   = var.bridge
    vlan_id  =  var.net.vlan
  }

  // Operating system configuration for the VM
  operating_system {
    type = "l26"
  }

  // TPM state configuration for the VM
  tpm_state {
    version = "v2.0"
  }

  // Serial device configuration for the VM
  serial_device {}

  // Initialization configuration for the VM
  initialization {
    // IP configuration for the VM
    ip_config {
      ipv4 {
        address = "${var.ip}/24"
        gateway = "${var.gateway}"
      }
    }

    ip_config {
      ipv4 {
        address = var.net.cidr
      }
    }

    // DNS configuration for the VM
    dns {
      servers = var.dns_servers
    }

    // User account configuration for the VM
    user_account {
      keys     = [trimspace(tls_private_key.vm_key.public_key_openssh)]
      password = random_password.vm_password.result
      username = "alpine"
    }
  }
}

// Resource to generate a random password for the VM
resource "random_password" "vm_password" {
  length           = 32
  override_special = "_%@"
  special          = true
}

// Resource to generate an RSA private key for the VM
resource "tls_private_key" "vm_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

// Output sensitive access information for the router VM
output "access" {
  value     = {
    os           = "alpine"
    name         = var.name,
    ip_address   = var.ip,
    password     = random_password.vm_password.result,
    private_key  = tls_private_key.vm_key.private_key_openssh
    public_key   = tls_private_key.vm_key.public_key_openssh
  }
  sensitive = true
}

