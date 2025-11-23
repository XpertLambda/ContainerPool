#!/bin/bash
# Script to fix architecture issues in the boxed VM
# Run this INSIDE the VM after importing the box

set -e

echo "================================================"
echo "Fixing Docker Container Architecture Issues"
echo "================================================"
echo ""

# Detect architecture
ARCH=$(uname -m)
echo "Detected architecture: $ARCH"
echo ""

# Stop all containers
echo "Stopping all containers..."
docker stop $(docker ps -aq) 2>/dev/null || true
docker rm $(docker ps -aq) 2>/dev/null || true

# Remove old images
echo "Removing old images..."
docker rmi nginx:alpine httpd:alpine node:18-alpine python:3.11-alpine redis:alpine 2>/dev/null || true

# Pull images for current architecture
echo "Pulling images for $ARCH architecture..."
docker pull --platform linux/$([[ "$ARCH" == "x86_64" ]] && echo "amd64" || echo "arm64") nginx:alpine
docker pull --platform linux/$([[ "$ARCH" == "x86_64" ]] && echo "amd64" || echo "arm64") httpd:alpine
docker pull --platform linux/$([[ "$ARCH" == "x86_64" ]] && echo "amd64" || echo "arm64") node:18-alpine
docker pull --platform linux/$([[ "$ARCH" == "x86_64" ]] && echo "amd64" || echo "arm64") python:3.11-alpine
docker pull --platform linux/$([[ "$ARCH" == "x86_64" ]] && echo "amd64" || echo "arm64") redis:alpine

echo ""
echo "✅ Images updated for $ARCH architecture"
echo ""

# Restart the PaaS app service
echo "Restarting PaaS application..."
sudo systemctl restart paas-app

echo ""
echo "✅ Fix completed! Container pool will be recreated."
