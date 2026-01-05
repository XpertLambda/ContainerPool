FROM ubuntu:22.04

# Avoid interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install ONLY SSH server and sudo (absolute minimum, no recommended packages)
RUN apt-get update && apt-get install -y --no-install-recommends \
    openssh-server \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Configure SSH
RUN mkdir /var/run/sshd

# Create a default user 'devuser' with password 'devpass123'
# Users will be able to change this password after connecting
RUN useradd -m -s /bin/bash devuser && \
    echo 'devuser:devpass123' | chpasswd && \
    usermod -aG sudo devuser

# Allow devuser to use sudo without password (optional, remove if you want more security)
RUN echo 'devuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Configure SSH to allow password authentication
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    echo 'AllowUsers devuser' >> /etc/ssh/sshd_config

# Create workspace directory for user
RUN mkdir -p /home/devuser/workspace && \
    chown -R devuser:devuser /home/devuser/workspace

# Add welcome message
RUN echo '#!/bin/bash\necho ""\necho "🐧 Welcome to your Linux Development Environment!"\necho ""\necho "User: devuser | Password: devpass123"\necho "Change password: passwd"\necho ""\necho "This is a minimal Ubuntu system. Install what you need:"\necho "  sudo apt update"\necho "  sudo apt install python3 git vim nodejs npm build-essential"\necho ""\necho "You have full sudo access (no password required)"\necho ""' > /etc/profile.d/welcome.sh && \
    chmod +x /etc/profile.d/welcome.sh

# Expose SSH port
EXPOSE 22

# Start SSH service
CMD ["/usr/sbin/sshd", "-D"]
