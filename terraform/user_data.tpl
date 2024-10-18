#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.cassandra.local
ssh_pwauth: false
disable_root: true

users:
  - name: rocky
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDXpoj6c4QnyI49t8MT5BHqA3w0klyWNo4sqHb0YlypT05kiVC9mEkPHBiFRlyrwPqDsNRCUDoLL/GK/sQ+nAKveeN4R2TzkBq7e5qbb7UtyWBFWcEH+sqzhdRtGnIcW5/F186xiqt5IC4Mol7/E2jeFRDTM+TS/hReKuCfkSYBsInERuHcLdF1JeJDFEQVrs/N2hGe5wqscGXuhNPlWMX6iXPyIVee+Y/eO9k3cPPZmUK1UnPU37Fbsc6iVDh/8pWMqle1vSolhihaEq6ZkB/aR6fUgmZlyA7BFGvAEF7sEMX+7+uQETLCQJlRFpYi67O/Hw66Ql/DHzswCIywC7Gp0AIZ4KwIFp2G/xqzdmLkIeS5bxV7Up4f1d5Em+YFwtJW/Sf+bN0RpnrzAzvRjS0mPF1szrERcHWXA+pGRn5oE8DOW62FVhABO2nSvZegauXgHrB1nrwRxbQc0GmROR7WArezAoB3k2n0C3YkjpB3Z020myc3012AWn5RcjfjJo8= oyuksel@X-Latitude-5540

write_files:
  - path: /etc/sysconfig/network-scripts/ifcfg-eth0
    content: |
      TYPE=Ethernet
      BOOTPROTO=static
      IPADDR=${ip_address}
      PREFIX=24
      GATEWAY=192.168.122.1
      DNS1=8.8.8.8
      DEFROUTE=yes
      IPV4_FAILURE_FATAL=no
      IPV6INIT=no
      NAME=eth0
      DEVICE=eth0
      ONBOOT=yes

runcmd:
  - systemctl restart NetworkManager
  - sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
  - sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
  - systemctl restart sshd
  - echo "SSH key setup complete" >> /var/log/cloud-init-output.log

output:
  all: '| tee -a /var/log/cloud-init-output.log'