#!/usr/bin/env python3
"""
Container Health Monitor and Auto-Recovery System
Automatically detects and recovers lost containers for users
"""

import sys
import logging
from datetime import datetime
from pathlib import Path
import docker
from app import app, db, Container, User

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/opt/my-paas/container_monitor.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger('ContainerMonitor')

# Initialize Docker client
try:
    docker_client = docker.from_env()
except Exception as e:
    logger.error(f"Failed to connect to Docker: {e}")
    sys.exit(1)

# Available container images configuration
AVAILABLE_IMAGES = {
    'nginx': {
        'name': 'nginx:alpine',
        'port': 80,
        'description': 'Lightweight web server (perfect for static sites)',
    },
    'apache': {
        'name': 'httpd:alpine',
        'port': 80,
        'description': 'Apache HTTP Server',
    },
    'node': {
        'name': 'node:18-alpine',
        'port': 3000,
        'description': 'Node.js runtime environment',
    },
    'python': {
        'name': 'python:3.11-alpine',
        'port': 8000,
        'description': 'Python runtime with built-in HTTP server',
    },
    'ubuntu-ssh': {
        'name': 'ubuntu-ssh:latest',
        'port': 22,
        'description': 'Ubuntu Linux with SSH access',
    }
}


def get_user_files_path(user_id, db_container_id):
    """Get the path for user's container files using database container ID"""
    path = Path('/opt/my-paas/user_files') / str(user_id) / f"container_{db_container_id}"
    return path


def assign_container_from_pool(image_type, user_id, container_name, mount_files=False, db_container_id=None):
    """
    Assign a pre-built container from the pool to a user.
    If no pool container is available, creates a new one dynamically.
    Returns: tuple (container_id, host_port, status, pool_name) or (None, None, error_message, None)
    """
    if image_type not in AVAILABLE_IMAGES:
        return None, None, f"Invalid image type: {image_type}", None
    
    try:
        # Find available container of requested type from pool
        available = docker_client.containers.list(
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
            logger.warning(f"No available {image_type} containers in pool, creating new container...")
            return create_new_container(image_type, user_id, container_name, mount_files, db_container_id)
        
        # Take the first available container
        container = available[0]
        pool_name = container.name
        
        # Get the container's port
        ports = container.ports
        host_port = None
        for port, bindings in ports.items():
            if bindings:
                host_port = int(bindings[0]['HostPort'])
                break
        
        if not host_port:
            return None, None, "Could not determine container port", None
        
        # Get container config for recreation
        image_config = AVAILABLE_IMAGES[image_type]
        container_port = image_config['port']
        
        # Stop the container
        container.stop()
        
        # Prepare volumes if needed
        volumes = {}
        if mount_files and user_id and db_container_id:
            user_files_path = get_user_files_path(user_id, db_container_id)
            
            if user_files_path.exists():
                # Different mount points based on image type
                if image_type in ['nginx', 'apache']:
                    mount_point = '/usr/share/nginx/html' if image_type == 'nginx' else '/usr/local/apache2/htdocs'
                    volumes = {str(user_files_path): {'bind': mount_point, 'mode': 'rw'}}
                elif image_type == 'node':
                    volumes = {str(user_files_path): {'bind': '/app', 'mode': 'rw'}}
                elif image_type == 'python':
                    volumes = {str(user_files_path): {'bind': '/app', 'mode': 'rw'}}
        
        # Remove old container
        container_name_saved = container.name
        container.remove()
        
        # Recreate container with "assigned" label
        container_config = {
            'image': container.image.tags[0] if container.image.tags else image_config['name'],
            'detach': True,
            'ports': {f'{container_port}/tcp': host_port},
            'name': container_name_saved,
            'labels': {
                'pool': 'true',
                'type': image_type,
                'status': 'assigned',
                'user_id': str(user_id)
            }
        }
        
        # Add volumes if any
        if volumes:
            container_config['volumes'] = volumes
        
        # Add commands
        if image_type == 'node':
            container_config['command'] = 'sh -c "while true; do sleep 3600; done"'
            container_config['working_dir'] = '/app'
        elif image_type == 'python':
            container_config['command'] = 'python -m http.server 8000'
            container_config['working_dir'] = '/app'
        
        # Create the assigned container
        container = docker_client.containers.run(**container_config)
        
        return container.id, host_port, 'running', pool_name
    
    except Exception as e:
        logger.error(f"Error assigning container from pool: {e}")
        return None, None, str(e), None


def create_new_container(image_type, user_id, container_name, mount_files=False, db_container_id=None):
    """
    Create a brand new container when pool is empty.
    Returns: tuple (container_id, host_port, status, pool_name) or (None, None, error_message, None)
    """
    if image_type not in AVAILABLE_IMAGES:
        return None, None, f"Invalid image type: {image_type}", None
    
    try:
        image_config = AVAILABLE_IMAGES[image_type]
        container_port = image_config['port']
        
        # Find available port
        host_port = find_available_port(image_type)
        if not host_port:
            return None, None, f"No available ports for {image_type} containers", None
        
        # Prepare volumes if needed
        volumes = {}
        if mount_files and user_id and db_container_id:
            user_files_path = get_user_files_path(user_id, db_container_id)
            user_files_path.mkdir(parents=True, exist_ok=True)
            
            # Different mount points based on image type
            if image_type in ['nginx', 'apache']:
                mount_point = '/usr/share/nginx/html' if image_type == 'nginx' else '/usr/local/apache2/htdocs'
                volumes = {str(user_files_path): {'bind': mount_point, 'mode': 'rw'}}
            elif image_type == 'node':
                volumes = {str(user_files_path): {'bind': '/app', 'mode': 'rw'}}
            elif image_type == 'python':
                volumes = {str(user_files_path): {'bind': '/app', 'mode': 'rw'}}
        
        # Generate container name
        import time
        generated_name = f"{image_type}-{host_port}-{int(time.time())}"
        
        # Build container config
        container_config = {
            'image': image_config['name'],
            'detach': True,
            'ports': {f'{container_port}/tcp': host_port},
            'name': generated_name,
            'labels': {
                'pool': 'true',
                'type': image_type,
                'status': 'assigned',
                'user_id': str(user_id),
                'created_by': 'monitor'
            }
        }
        
        # Add volumes if any
        if volumes:
            container_config['volumes'] = volumes
        
        # Add specific commands based on image type
        if image_type == 'node':
            container_config['command'] = 'sh -c "while true; do sleep 3600; done"'
            container_config['working_dir'] = '/app'
        elif image_type == 'python':
            container_config['command'] = 'python -m http.server 8000'
            container_config['working_dir'] = '/app'
        
        # Create and start the container
        logger.info(f"Creating new {image_type} container on port {host_port}...")
        container = docker_client.containers.run(**container_config)
        
        logger.info(f"✓ Successfully created new container {generated_name}")
        return container.id, host_port, 'running', generated_name
    
    except Exception as e:
        logger.error(f"Error creating new container: {e}")
        return None, None, str(e), None


def find_available_port(image_type):
    """
    Find an available port for the given image type.
    Port ranges:
    - nginx: 8000-8099
    - apache: 8100-8199
    - python: 8200-8299
    - node: 8300-8399
    - ubuntu-ssh: 2200-2210
    """
    port_ranges = {
        'nginx': (8000, 8099),
        'apache': (8100, 8199),
        'python': (8200, 8299),
        'node': (8300, 8399),
        'ubuntu-ssh': (2200, 2210)
    }
    
    if image_type not in port_ranges:
        return None
    
    start_port, end_port = port_ranges[image_type]
    
    # Get all used ports
    used_ports = set()
    all_containers = docker_client.containers.list(all=True)
    for container in all_containers:
        if container.ports:
            for port, bindings in container.ports.items():
                if bindings:
                    for binding in bindings:
                        used_ports.add(int(binding['HostPort']))
    
    # Find first available port
    for port in range(start_port, end_port + 1):
        if port not in used_ports:
            return port
    
    return None



def check_and_recover_containers():
    """
    Check all assigned containers and recover any that are lost or unhealthy
    """
    with app.app_context():
        logger.info("Starting container health check...")
        
        # Get all containers from database
        db_containers = Container.query.all()
        
        if not db_containers:
            logger.info("No containers to monitor")
            return
        
        recovered_count = 0
        failed_count = 0
        healthy_count = 0
        
        for db_container in db_containers:
            user = User.query.get(db_container.user_id)
            if not user:
                logger.warning(f"Container {db_container.id} has no associated user, skipping")
                continue
            
            try:
                # Try to get the container from Docker
                docker_container = docker_client.containers.get(db_container.container_id)
                
                # Check container status
                if docker_container.status == 'running':
                    # Container is healthy
                    if db_container.status != 'running':
                        db_container.status = 'running'
                        db.session.commit()
                        logger.info(f"Updated status for container {db_container.id} (user: {user.username})")
                    healthy_count += 1
                    continue
                else:
                    # Container exists but not running
                    logger.warning(f"Container {db_container.id} (user: {user.username}) is {docker_container.status}, attempting restart...")
                    
                    try:
                        docker_container.restart()
                        db_container.status = 'running'
                        db.session.commit()
                        logger.info(f"Successfully restarted container {db_container.id}")
                        recovered_count += 1
                        continue
                    except Exception as restart_error:
                        logger.error(f"Failed to restart container: {restart_error}, will reassign new container")
                        # Fall through to recovery below
            
            except docker.errors.NotFound:
                # Container doesn't exist in Docker
                logger.warning(f"Container {db_container.id} (user: {user.username}) not found in Docker!")
            except Exception as e:
                logger.error(f"Error checking container {db_container.id}: {e}")
            
            # Container is lost or failed, attempt recovery
            logger.info(f"Attempting to recover container for user {user.username} (type: {db_container.image_type})")
            
            try:
                # Check if user had uploaded files
                has_files = db_container.has_custom_files
                user_files_path = get_user_files_path(user.id, db_container.id)
                
                # Assign new container from pool
                new_container_id, new_host_port, status, pool_name = assign_container_from_pool(
                    image_type=db_container.image_type,
                    user_id=user.id,
                    container_name=db_container.name,
                    mount_files=has_files,
                    db_container_id=db_container.id
                )
                
                if new_container_id:
                    # Update database with new container info
                    old_port = db_container.host_port
                    db_container.container_id = new_container_id
                    db_container.host_port = new_host_port
                    db_container.status = status
                    if pool_name:
                        db_container.pool_name = pool_name
                    
                    db.session.commit()
                    
                    logger.info(f"✓ Successfully recovered container for user {user.username}")
                    logger.info(f"  Old port: {old_port} → New port: {new_host_port}")
                    logger.info(f"  Type: {db_container.image_type}")
                    logger.info(f"  Files preserved: {has_files}")
                    
                    recovered_count += 1
                else:
                    logger.error(f"✗ Failed to recover container for user {user.username}: {status}")
                    db_container.status = 'error'
                    db.session.commit()
                    failed_count += 1
            
            except Exception as recovery_error:
                logger.error(f"✗ Failed to recover container for user {user.username}: {recovery_error}")
                db_container.status = 'error'
                db.session.commit()
                failed_count += 1
        
        # Summary
        logger.info("=" * 70)
        logger.info("Container Health Check Summary:")
        logger.info(f"  Healthy: {healthy_count}")
        logger.info(f"  Recovered: {recovered_count}")
        logger.info(f"  Failed: {failed_count}")
        logger.info(f"  Total checked: {len(db_containers)}")
        logger.info("=" * 70)


def check_pool_health():
    """
    Check pool containers and restart any that are stopped
    """
    try:
        pool_containers = docker_client.containers.list(
            all=True,
            filters={'label': 'pool=true'}
        )
        
        available = 0
        assigned = 0
        stopped = 0
        restarted = 0
        
        for container in pool_containers:
            label_status = container.labels.get('status', 'available')
            docker_status = container.status
            
            if docker_status != 'running':
                stopped += 1
                logger.warning(f"Pool container {container.name} is {docker_status}")
                
                # Try to restart stopped pool containers
                try:
                    logger.info(f"Attempting to restart pool container {container.name}...")
                    container.start()
                    logger.info(f"✓ Successfully restarted pool container {container.name}")
                    restarted += 1
                    
                    # Check if it's available or assigned
                    if label_status == 'assigned':
                        assigned += 1
                    else:
                        available += 1
                        
                except Exception as restart_error:
                    logger.error(f"✗ Failed to restart pool container {container.name}: {restart_error}")
                    
            elif label_status == 'assigned':
                assigned += 1
            else:
                available += 1
        
        logger.info("=" * 70)
        logger.info(f"Pool Status:")
        logger.info(f"  Available: {available}")
        logger.info(f"  Assigned: {assigned}")
        logger.info(f"  Stopped: {stopped}")
        if restarted > 0:
            logger.info(f"  Restarted: {restarted}")
        logger.info("=" * 70)
        
        if stopped > restarted:
            logger.warning(f"⚠ {stopped - restarted} pool containers failed to restart!")
    
    except Exception as e:
        logger.error(f"Error checking pool health: {e}")


if __name__ == '__main__':
    try:
        logger.info("=" * 70)
        logger.info("Container Monitor - Starting health check")
        logger.info("=" * 70)
        
        # Check and restart pool containers first
        check_pool_health()
        
        # Then check and recover user containers
        check_and_recover_containers()
        
        logger.info("Container monitor completed successfully")
        sys.exit(0)
    
    except Exception as e:
        logger.error(f"Container monitor failed: {e}", exc_info=True)
        sys.exit(1)
