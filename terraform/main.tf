terraform {
  required_providers {
    virtualbox = {
      source  = "terra-farm/virtualbox"
      version = "0.2.2-alpha.1"
    }
  }
}

provider "virtualbox" {
  # Configuration options
}

variable "vm_names" {
  type    = list(string)
  default = ["cassandra01", "cassandra02", "cassandra03"]
}

variable "vm_ips" {
  type    = list(string)
  default = ["192.168.56.135", "192.168.56.136", "192.168.56.137"]
}

resource "virtualbox_vm" "cassandra_vm" {
  count     = length(var.vm_names)
  name      = var.vm_names[count.index]
  image     = "https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-Vagrant-Vbox-9.4-20240509.0.x86_64.box"
  cpus      = 2
  memory    = "2.5 gib"
  user_data = templatefile("${path.module}/user_data.tpl", {
    hostname   = var.vm_names[count.index],
    ip_address = var.vm_ips[count.index]
  })

  network_adapter {
    type           = "hostonly"
    host_interface = "vboxnet0"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo dnf update -y",
      "sudo systemctl disable --now firewalld",
      "sudo reboot"
    ]

    connection {
      type        = "ssh"
      user        = "cassandra"
      private_key = file("~/.ssh/id_rsa")  # Adjust this path to your SSH private key
      host        = var.vm_ips[count.index]
    }

    on_failure = continue
  }

  provisioner "local-exec" {
    command = "echo 'Waiting for system to reboot...'; sleep 60"
  }
}