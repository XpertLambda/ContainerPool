# Container Pool PaaS Platform

A Platform-as-a-Service (PaaS) system with pre-built container pools for instant provisioning. Users can register, get instantly assigned containers from the pool, upload files, and manage their containerized applications.

## Features

### Container Pool System
- **Instant Provisioning**: Pre-built container pools enable assignment in under 1 second
- **Multiple Container Types**: Nginx, Apache, Python, and Node.js
- **Dynamic Pool Management**: Admin tools for pool expansion and configuration
- **Automatic Reset**: Containers return to fresh state when released

### User Features
- Secure authentication (registration and login)
- One-click container provisioning from pool
- File upload for web servers (HTML, CSS, JS, images)
- Real-time container status monitoring
- Access containers via unique ports

### Admin Features
- Interactive admin helper script
- User and container management
- Pool status monitoring and configuration
- Batch operations for container management

## Architecture

| Component | Technology |
|-----------|------------|
| Host OS | Linux (Arch, Debian/Ubuntu, RedHat) |
| Hypervisor | KVM (libvirt) |
| VM | Vagrant with Ubuntu 22.04 LTS |
| Provisioning | Ansible |
| Backend | Flask (Python 3.10+) |
| Database | SQLite |
| Containers | Docker |

### Network Configuration

| Resource | Address/Range |
|----------|---------------|
| VM IP | 192.168.121.183 |
| Flask Port | 5000 |
| Nginx Containers | 8000-8099 |
| Apache Containers | 8100-8199 |
| Python Containers | 8200-8299 |
| Node.js Containers | 8300-8399 |

## Project Structure

```
platform-deployement/
├── infrastructure/
│   ├── Vagrantfile              # VM configuration (libvirt)
│   └── site.yml                 # Ansible provisioning playbook
├── app/
│   ├── app.py                   # Main Flask application
│   ├── pool_manager.py          # Container pool management CLI
│   ├── admin_helper.sh          # Interactive admin script
│   ├── requirements.txt         # Python dependencies
│   └── templates/               # HTML templates
├── requirements.sh              # System requirements installer
├── setup.sh                     # Prerequisites checker
├── admin.sh                     # Admin helper wrapper
├── Makefile                     # Build automation
├── COMMANDS.sh                  # Quick command reference
└── README.md
```

## Installation

### System Requirements

**Supported Operating Systems:**
- Arch Linux
- Debian / Ubuntu
- RedHat / CentOS / Fedora

**Hardware Requirements:**
- CPU with VT-x/AMD-V virtualization support (enabled in BIOS)
- Minimum 4GB RAM (8GB recommended)
- 20GB free disk space
- Active internet connection

### Step 1: Install System Requirements

Run the automated installer for your Linux distribution:

```bash
chmod +x requirements.sh
./requirements.sh
```

**This script automatically installs EVERYTHING needed:**
- Vagrant (VM orchestration)
- Ansible (configuration management)
- libvirt + KVM (virtualization)
- QEMU (hypervisor)
- dnsmasq (networking)
- vagrant-libvirt plugin
- All required networking tools

The script detects your distribution and uses the appropriate package manager (pacman/apt/yum).

> **Important**: Log out and log back in after installation for group membership changes to take effect.

### Step 2: Verify Prerequisites

```bash
chmod +x setup.sh
./setup.sh
```

### Step 3: Deploy the Platform

```bash
cd infrastructure
vagrant up
```

This process takes 5-10 minutes on first run and will:
1. Download Ubuntu 22.04 VM image
2. Create and configure the VM with KVM
3. Install Docker, Python, and dependencies via Ansible
4. Deploy the Flask application
5. Initialize the container pool (13 containers by default)
6. Start the Flask service

## Usage

### Access the Platform

Open your browser and navigate to:
- **VM IP**: http://192.168.121.183:5000
- **Localhost**: http://localhost:5000

### User Workflow

1. **Register** at `/register` with username, email, and password
2. **Login** with your credentials
3. **Launch Container**: Select type from pool and get instant assignment
4. **Upload Files** (optional): Add HTML, CSS, JS, or images for web servers
5. **Access Container**: Use the provided URL with your assigned port
6. **Release Container**: Return to pool when finished

### Admin Management

Run the interactive admin helper:

```bash
./admin.sh
```

Or connect directly to the VM:

```bash
ssh vagrant@192.168.121.183  # Password: vagrant
sudo /opt/my-paas/admin_helper.sh
```

**Available Admin Operations:**

| Category | Operations |
|----------|------------|
| User Management | List users, delete user |
| Container Management | Show pool status, view assigned containers, release/delete containers |
| Pool Management | Add containers, configure sizes, reinitialize pool |
| System | View status, check logs |

### Common Admin Tasks

**View Pool Status:**
```bash
ssh vagrant@192.168.121.183 "cd /opt/my-paas && source venv/bin/activate && python pool_manager.py --status"
```

**Add More Containers:**
```bash
./admin.sh
# Select option 8 → Choose type → Enter count
```

**Release All User Containers:**
```bash
./admin.sh
# Select option 7 → Enter username → Confirm
```

## Configuration

### Pool Configuration

Default pool sizes (configurable via admin helper):

| Type | Default Count |
|------|---------------|
| Nginx | 5 |
| Apache | 3 |
| Python | 3 |
| Node.js | 2 |

Configuration stored at `/opt/my-paas/pool_config.txt` on the VM.

### VM Configuration

Edit `infrastructure/Vagrantfile` to adjust memory (default 2048 MB), CPUs (default 2), or network settings. Apply changes with:

```bash
cd infrastructure
vagrant reload --provision
```

## Development

### VM Management

```bash
# SSH into VM
cd infrastructure && vagrant ssh

# View Flask logs
ssh vagrant@192.168.121.183 "cat /opt/my-paas/flask.log"

# Restart Flask
ssh vagrant@192.168.121.183 "sudo pkill -f 'flask run' && cd /opt/my-paas && source venv/bin/activate && nohup flask run --host=0.0.0.0 > flask.log 2>&1 &"
```

### Database Access

```bash
ssh vagrant@192.168.121.183
cd /opt/my-paas && source venv/bin/activate
python
>>> from app import app, db, User, Container
>>> app.app_context().push()
>>> User.query.all()
```

### Backup & Restore

```bash
# Backup
scp vagrant@192.168.121.183:/opt/my-paas/instance/paas_platform.db ./backup.db

# Restore
scp ./backup.db vagrant@192.168.121.183:/tmp/
ssh vagrant@192.168.121.183 "sudo cp /tmp/backup.db /opt/my-paas/instance/paas_platform.db"
```

## Troubleshooting

### VM Won't Start

```bash
# Check and start libvirt service
sudo systemctl status libvirtd
sudo systemctl start libvirtd

# Verify user groups (should include 'libvirt')
groups

# If not in group, add and re-login
sudo usermod -a -G libvirt $USER
```

### Can't Access Web Interface

```bash
# Check Flask is running
ssh vagrant@192.168.121.183 "pgrep -f 'flask run'"

# Check VM IP
cd infrastructure && vagrant ssh -c "ip addr show"

# Restart Flask
ssh vagrant@192.168.121.183 "cd /opt/my-paas && source venv/bin/activate && pkill -f 'flask run'; nohup flask run --host=0.0.0.0 > flask.log 2>&1 &"
```

### Containers Not Available

```bash
# Check pool status
./admin.sh  # Select option 3

# Reinitialize pool
ssh vagrant@192.168.121.183 "cd /opt/my-paas && source venv/bin/activate && python pool_manager.py --init"
```

### Port Conflicts

```bash
# List all Docker containers
ssh vagrant@192.168.121.183 "docker ps -a"

# Clean up stopped containers
ssh vagrant@192.168.121.183 "docker container prune -f"
```

## Architecture Details

### Container Pool System

Containers are tracked using Docker labels:

| Label | Description |
|-------|-------------|
| `pool=true` | Identifies pool containers |
| `type=<nginx\|apache\|python\|node>` | Container type |
| `status=<available\|assigned>` | Current status |
| `pool_index=<N>` | Index within type |
| `user_id=<ID>` | Assigned user |

**Container Naming**: `pool_<type>_<index>_<port>` (e.g., `pool_nginx_0_8000`)

### File Upload System

| Container Type | Host Path | Container Mount |
|----------------|-----------|-----------------|
| Nginx | `/opt/my-paas/user_files/<user_id>/...` | `/usr/share/nginx/html` |
| Apache | `/opt/my-paas/user_files/<user_id>/...` | `/usr/local/apache2/htdocs` |
| Python/Node.js | `/opt/my-paas/user_files/<user_id>/...` | `/app` |

## Quick Reference

```bash
# Install requirements
./requirements.sh

# Check prerequisites
./setup.sh

# Deploy platform
cd infrastructure && vagrant up

# Access admin helper
./admin.sh

# VM commands
cd infrastructure
vagrant status     # Check status
vagrant halt       # Stop VM
vagrant up         # Start VM
vagrant destroy    # Delete VM
vagrant ssh        # SSH into VM
```

## Future Enhancements

- [ ] Custom container images
- [ ] Container resource limits (CPU, memory)
- [ ] Container logs viewing
- [ ] Multi-container applications (Docker Compose)
- [ ] SSL/TLS support
- [ ] User quotas and limits
- [ ] Container persistence and backups
- [ ] Admin panel for system monitoring

## License

This project is provided as-is for educational and development purposes.

---

**Note**: This is an MVP designed for demonstration and learning. For production use, additional security hardening, monitoring, and scalability considerations are required.