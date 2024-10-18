terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "vm_names" {
  type    = list(string)
  default = ["cassandra01", "cassandra02", "cassandra03"]
}

variable "vm_ips" {
  type    = list(string)
  default = ["192.168.122.101", "192.168.122.102", "192.168.122.103"]
}

# New variable for the local image path
variable "local_image_path" {
  type    = string
  default = "/var/lib/libvirt/images/Rocky-9-GenericCloud.latest.x86_64.qcow2"
}

resource "libvirt_pool" "cassandra" {
  name = "cassandra"
  type = "dir"
  path = "/var/lib/libvirt/images/cassandra"
}

resource "libvirt_volume" "rocky_qcow2" {
  name   = "rocky_qcow2"
  pool   = libvirt_pool.cassandra.name
  source = var.local_image_path
  format = "qcow2"
}

resource "libvirt_volume" "vm_volume" {
  count          = length(var.vm_names)
  name           = "${var.vm_names[count.index]}.qcow2"
  base_volume_id = libvirt_volume.rocky_qcow2.id
  pool           = libvirt_pool.cassandra.name
  size           = 10737418240  # 10 GB
}

resource "libvirt_cloudinit_disk" "commoninit" {
  count     = length(var.vm_names)
  name      = "${var.vm_names[count.index]}-commoninit.iso"
  pool      = libvirt_pool.cassandra.name
  user_data = templatefile("${path.module}/user_data.tpl", {
    hostname   = var.vm_names[count.index],
    ip_address = var.vm_ips[count.index]
  })
}

variable "existing_network_name" {
  type    = string
  default = "default"  # This is typically the name of the default libvirt network
}

resource "libvirt_domain" "cassandra_vm" {
  count  = length(var.vm_names)
  name   = var.vm_names[count.index]
  memory = "2560"
  vcpu   = 2

  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id

  network_interface {
    network_id = var.existing_network_name
    addresses  = [var.vm_ips[count.index]]
  }

  disk {
    volume_id = libvirt_volume.vm_volume[count.index].id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cat /var/log/cloud-init-output.log",
      "sudo dnf update -y",
      "sudo reboot"
    ]

    connection {
      type        = "ssh"
      user        = "rocky"
      private_key = file("~/.ssh/id_rsa")
      host        = var.vm_ips[count.index]
    }

    on_failure = continue
  }

  provisioner "local-exec" {
    command = "echo 'Waiting for system to reboot...'; sleep 60"
  }
}