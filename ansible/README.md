# Cassandra Cluster Ansible Automation

This project provides a fully automated, modular, and maintainable Ansible setup for deploying and configuring a multi-node Apache Cassandra cluster. The codebase follows best practices using roles, templates, and variable management for clarity and scalability.

## Directory Structure

```
ansible/
├── ansible.cfg           # Ansible configuration (roles_path)
├── inventory.yaml        # Inventory file (YAML format)
├── group_vars/
│   └── all.yaml          # Global variables (e.g., node IPs)
├── host_vars/            # (Optional) Per-host variables
├── playbooks/
│   └── main.yaml         # Main playbook (entry point)
├── roles/
│   ├── install/          # Role: Install Java & Cassandra
│   │   └── tasks/
│   │       └── main.yaml
│   ├── configure/        # Role: Configure Cassandra
│   │   ├── tasks/
│   │   │   └── main.yaml
│   │   └── templates/
│   │       ├── cassandra.yaml.j2
│   │       ├── jvm-server.options.j2
│   │       └── jvm8-server.options.j2
│   └── service/          # Role: Enable/start service, reboot
│       └── tasks/
│           └── main.yaml
└── files/                # (Optional) Supporting files
```

## Prerequisites
- Ansible 2.9+
- SSH access to all Cassandra nodes (configured in `inventory.yaml`)
- Python installed on target hosts
- Sudo privileges for the Ansible user

## Setup & Usage

1. **Clone the repository and enter the `ansible/` directory:**
   ```bash
   cd ansible
   ```

2. **Review and update the inventory:**
   - Edit `inventory.yaml` to match your environment (hostnames, IP addresses, SSH keys).
   - Update `group_vars/all.yaml` for cluster IPs if needed.

3. **Run the playbook:**
   ```bash
   ansible-playbook -i inventory.yaml playbooks/main.yaml
   ```

## Detailed Usage Examples

### Run with Extra Variables
You can override variables at runtime using `-e`:
```bash
ansible-playbook -i inventory.yaml playbooks/main.yaml -e 'cassandra01_ip=10.0.0.1'
```

### Limit Execution to a Single Host
To run the playbook on just one host:
```bash
ansible-playbook -i inventory.yaml playbooks/main.yaml --limit cassandra01
```

### Run Only a Specific Role (Using Tags)
Add tags to your roles/tasks (see Ansible docs). Example to run only the `configure` role:
```bash
ansible-playbook -i inventory.yaml playbooks/main.yaml --tags configure
```

### Check Playbook Syntax
To check for syntax errors without running tasks:
```bash
ansible-playbook -i inventory.yaml playbooks/main.yaml --syntax-check
```

### Run in Check (Dry-Run) Mode
To see what changes would be made, without applying them:
```bash
ansible-playbook -i inventory.yaml playbooks/main.yaml --check
```

### Increase Verbosity for Debugging
Add `-v`, `-vv`, or `-vvv` for more detailed output:
```bash
ansible-playbook -i inventory.yaml playbooks/main.yaml -vvv
```

### Use a Custom SSH Private Key
If your SSH key is not the default:
```bash
ansible-playbook -i inventory.yaml playbooks/main.yaml --private-key ~/.ssh/your_key
```

## Roles Overview:
- **install:** Installs Java, sets up alternatives, adds Cassandra repo, installs Cassandra.
- **configure:** Configures Cassandra using Jinja2 templates for `cassandra.yaml` and JVM options.
- **service:** Installs `chkconfig`, enables Cassandra service, and reboots nodes.

## Customizing Configuration:
- Edit templates in `roles/configure/templates/` to adjust Cassandra or JVM settings.
- Add or override variables in `group_vars/all.yaml` or `host_vars/<hostname>.yaml`.

## Notes
- The playbook is idempotent: it can be safely re-run.
- Ensure your SSH keys and user permissions are correct in `inventory.yaml`.
- The `ansible.cfg` file ensures roles are found regardless of your working directory.
- For advanced customization, add handlers, additional roles, or expand variable files as needed.

## Troubleshooting
- If roles are not found, ensure you are running from the `ansible/` directory or that `ansible.cfg` is present.
- For debugging, use `-vvv` with `ansible-playbook` for verbose output.

---

**Maintained by:** Your Name / Organization 