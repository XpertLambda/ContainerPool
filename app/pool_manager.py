#!/usr/bin/env python3
"""
Container Pool Management System
Pre-creates and manages a pool of containers that can be assigned to users
"""

from app import app, db, Container, User
import docker
import sys

client = docker.from_env()

# Container pool configuration
POOL_CONFIG = {
    'nginx': {'count': 5, 'image': 'nginx:alpine', 'port': 80},
    'apache': {'count': 3, 'image': 'httpd:alpine', 'port': 80},
    'python': {'count': 3, 'image': 'python:3.11-alpine', 'port': 8000},
    'node': {'count': 2, 'image': 'node:18-alpine', 'port': 3000},
    'ubuntu-ssh': {'count': 2, 'image': 'ubuntu-ssh:latest', 'port': 22},
}

def create_pool_container(image_type, pool_index):
    """Create a single container for the pool"""
    config = POOL_CONFIG[image_type]
    
    # Generate unique port based on image type and index
    # nginx: 8000-8004, apache: 8100-8102, python: 8200-8202, node: 8300-8301, ubuntu-ssh: 2200-2201
    type_base_ports = {
        'nginx': 8000,
        'apache': 8100,
        'python': 8200,
        'node': 8300,
        'ubuntu-ssh': 2200
    }
    base_port = type_base_ports.get(image_type, 8000) + pool_index
    
    # Container configuration
    container_config = {
        'image': config['image'],
        'detach': True,
        'ports': {f"{config['port']}/tcp": base_port},
        'name': f'pool_{image_type}_{pool_index}_{base_port}',
        'labels': {
            'pool': 'true',
            'type': image_type,
            'status': 'available',
            'pool_index': str(pool_index)
        }
    }
    
    # Add commands for containers that need them
    if image_type == 'node':
        container_config['command'] = 'sh -c "while true; do sleep 3600; done"'
        container_config['working_dir'] = '/app'
    elif image_type == 'python':
        container_config['command'] = 'python -m http.server 8000'
        container_config['working_dir'] = '/app'
    
    try:
        # Pull image if needed
        try:
            client.images.get(config['image'])
        except:
            print(f"  Pulling {config['image']}...")
            client.images.pull(config['image'])
        
        # Create container
        container = client.containers.run(**container_config)
        print(f"  [OK] Created {image_type} container on port {base_port}")
        return container.id, base_port
    except Exception as e:
        print(f"  [FAILED] Failed to create {image_type} container: {e}")
        return None, None

def initialize_pool():
    """Initialize the container pool"""
    print("╔════════════════════════════════════════════════════════════════╗")
    print("║         Initializing Container Pool                           ║")
    print("╚════════════════════════════════════════════════════════════════╝")
    print()
    
    # Clean up any existing pool containers
    print("Cleaning up existing pool containers...")
    existing = client.containers.list(all=True, filters={'label': 'pool=true'})
    for container in existing:
        try:
            container.stop()
            container.remove()
        except:
            pass
    print(f"  Removed {len(existing)} old pool containers")
    print()
    
    # Create new pool
    total_created = 0
    for image_type, config in POOL_CONFIG.items():
        print(f"Creating {config['count']} {image_type} containers...")
        for i in range(config['count']):
            container_id, port = create_pool_container(image_type, i)
            if container_id:
                total_created += 1
        print()
    
    print(f"[OK] Pool initialized: {total_created} containers ready")
    print()
    return total_created

def show_pool_status():
    """Show current pool status"""
    print("╔════════════════════════════════════════════════════════════════╗")
    print("║         Container Pool Status                                  ║")
    print("╚════════════════════════════════════════════════════════════════╝")
    print()
    
    pool_containers = client.containers.list(all=True, filters={'label': 'pool=true'})
    
    if not pool_containers:
        print("[ERROR] No pool containers found. Run with --init to create pool.")
        return
    
    # Group by type and status
    stats = {}
    for container in pool_containers:
        image_type = container.labels.get('type', 'unknown')
        label_status = container.labels.get('status', 'available')
        docker_status = container.status
        
        if image_type not in stats:
            stats[image_type] = {'available': 0, 'assigned': 0, 'stopped': 0}
        
        if docker_status != 'running':
            stats[image_type]['stopped'] += 1
        elif label_status == 'assigned':
            stats[image_type]['assigned'] += 1
        else:
            stats[image_type]['available'] += 1
    
    print("Type      | Available | Assigned | Stopped | Total")
    print("----------|-----------|----------|---------|-------")
    for image_type in sorted(stats.keys()):
        s = stats[image_type]
        total = s['available'] + s['assigned'] + s['stopped']
        print(f"{image_type:9s} | {s['available']:9d} | {s['assigned']:8d} | {s['stopped']:7d} | {total:5d}")
    
    print()
    
    # Show detailed list
    print("Detailed List:")
    print("-" * 80)
    for container in sorted(pool_containers, key=lambda c: c.name):
        status_icon = "[OK]" if container.status == 'running' else "[FAILED]"
        label_status = container.labels.get('status', 'available')
        ports = container.ports
        port_str = ""
        for port, bindings in ports.items():
            if bindings:
                port_str = f":{bindings[0]['HostPort']}"
        print(f"{status_icon} {container.name:30s} | {label_status:10s} | {container.status:10s} | http://192.168.121.183{port_str}")

def assign_container(image_type, user_id, container_name):
    """Assign a container from the pool to a user"""
    # Find available container of requested type
    available = client.containers.list(
        filters={
            'label': [
                'pool=true',
                f'type={image_type}',
                'status=available'
            ],
            'status': 'running'
        }
    )
    
    if not available:
        print(f"[ERROR] No available {image_type} containers in pool")
        return None
    
    container = available[0]
    
    # Update container labels
    # Note: Docker doesn't support updating labels on running containers
    # We'll track this in the database instead
    
    # Get port
    ports = container.ports
    host_port = None
    for port, bindings in ports.items():
        if bindings:
            host_port = int(bindings[0]['HostPort'])
            break
    
    if not host_port:
        print(f"[ERROR] Could not determine port for container {container.name}")
        return None
    
    print(f"[OK] Assigned {container.name} (port {host_port}) to user {user_id}")
    
    return {
        'container_id': container.id,
        'host_port': host_port,
        'container_port': POOL_CONFIG[image_type]['port'],
        'docker_name': container.name
    }

if __name__ == '__main__':
    if len(sys.argv) > 1:
        if sys.argv[1] == '--init':
            initialize_pool()
        elif sys.argv[1] == '--status':
            show_pool_status()
        elif sys.argv[1] == '--cleanup':
            print("Cleaning up pool containers...")
            containers = client.containers.list(all=True, filters={'label': 'pool=true'})
            for container in containers:
                try:
                    container.stop()
                    container.remove()
                    print(f"  Removed {container.name}")
                except Exception as e:
                    print(f"  Failed to remove {container.name}: {e}")
            print(f"[OK] Removed {len(containers)} containers")
        else:
            print("Usage:")
            print("  python pool_manager.py --init      # Initialize container pool")
            print("  python pool_manager.py --status    # Show pool status")
            print("  python pool_manager.py --cleanup   # Remove all pool containers")
    else:
        with app.app_context():
            show_pool_status()
