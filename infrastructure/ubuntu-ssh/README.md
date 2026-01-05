# Ubuntu SSH Container

This container provides a full Ubuntu 22.04 Linux environment with SSH access.

## Default Credentials

- **Username**: `devuser`
- **Password**: `devpass123`

**⚠️ IMPORTANT**: Change the password after first login using `passwd` command!

## Features

- Full Ubuntu 22.04 LTS environment
- SSH server with password authentication
- Sudo access without password
- Pre-installed development tools:
  - Python 3
  - Node.js & npm
  - Git
  - Vim & Nano
  - curl & wget
  - Build tools (gcc, make, etc.)
  - Network utilities (ping, netstat, etc.)
  - htop, tmux, tree

## Building the Image

```bash
cd infrastructure/ubuntu-ssh
docker build -t ubuntu-ssh:latest .
```

## Running Manually

```bash
docker run -d -p 2222:22 --name my-ssh-container ubuntu-ssh:latest
```

## Connecting via SSH

```bash
ssh devuser@192.168.121.183 -p [PORT]
# Enter password: devpass123
```

## Security Notes

1. **Change the default password** immediately after first connection
2. Consider using SSH key authentication instead of passwords
3. The user has sudo access without password - suitable for development only
4. For production, implement proper user isolation and security hardening
