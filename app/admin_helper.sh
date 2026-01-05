#!/bin/bash
# Admin Helper Script for Container Pool Management

SCRIPT_DIR="/opt/my-paas"
CONFIG_FILE="$SCRIPT_DIR/pool_config.txt"

# Default pool configuration
DEFAULT_NGINX=5
DEFAULT_APACHE=3
DEFAULT_PYTHON=3
DEFAULT_NODE=2
DEFAULT_SSH=2

# Load or create pool config
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        NGINX_COUNT=$DEFAULT_NGINX
        APACHE_COUNT=$DEFAULT_APACHE
        PYTHON_COUNT=$DEFAULT_PYTHON
        NODE_COUNT=$DEFAULT_NODE
        SSH_COUNT=$DEFAULT_SSH
        save_config
    fi
}

save_config() {
    cat > "$CONFIG_FILE" << EOF
NGINX_COUNT=$NGINX_COUNT
APACHE_COUNT=$APACHE_COUNT
PYTHON_COUNT=$PYTHON_COUNT
NODE_COUNT=$NODE_COUNT
SSH_COUNT=$SSH_COUNT
EOF
}

show_menu() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         Container Pool Admin Helper                           ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo " USER MANAGEMENT:"
    echo "  1) List all users"
    echo "  2) Delete user by username"
    echo ""
    echo " CONTAINER MANAGEMENT:"
    echo "  3) Show pool status"
    echo "  4) Show all assigned containers (with details)"
    echo "  5) Release container (reset to pool)"
    echo "  6) Delete container permanently"
    echo "  7) Release all containers from a user"
    echo ""
    echo " POOL MANAGEMENT:"
    echo "  8) Add containers to pool (incremental)"
    echo "  9) Configure pool sizes"
    echo " 10) Reinitialize entire pool"
    echo ""
    echo " SYSTEM:"
    echo " 11) Show detailed system status"
    echo " 12) Exit"
    echo ""
}

list_users() {
    cd $SCRIPT_DIR
    source venv/bin/activate
    python << 'PYTHON_END'
from app import app, db, User
with app.app_context():
    users = User.query.all()
    print(f'Total users: {len(users)}\n')
    print('{:<5} {:<20} {:<35} {:<12} {:<20}'.format('ID', 'Username', 'Email', 'Containers', 'Created'))
    print('='*95)
    for user in users:
        container_count = len(user.containers)
        created = user.created_at.strftime('%Y-%m-%d %H:%M')
        print('{:<5} {:<20} {:<35} {:<12} {:<20}'.format(user.id, user.username, user.email, container_count, created))
PYTHON_END
}

delete_user() {
    echo -n "Enter username to delete: "
    read username
    
    if [ -z "$username" ]; then
        echo "No username entered"
        return
    fi
    
    cd $SCRIPT_DIR
    source venv/bin/activate
    
    # First, check if user exists and show details
    python << PYTHON_END
from app import app, db, User
import sys

with app.app_context():
    user = User.query.filter_by(username='$username').first()
    if user:
        print(f'User found: {user.username} (ID: {user.id})')
        print(f'Email: {user.email}')
        print(f'Containers: {len(user.containers)}')
        print(f'Created: {user.created_at.strftime("%Y-%m-%d %H:%M")}')
    else:
        print('User not found')
        sys.exit(1)
PYTHON_END
    
    if [ $? -ne 0 ]; then
        return
    fi
    
    # Ask for confirmation in bash
    echo ""
    echo -n "Delete this user? (yes/no): "
    read confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        return
    fi
    
    # Now perform the deletion
    python << PYTHON_END
from app import app, db, User

with app.app_context():
    user = User.query.filter_by(username='$username').first()
    if user:
        db.session.delete(user)
        db.session.commit()
        print('[OK] User deleted successfully')
    else:
        print('[ERROR] User not found')
PYTHON_END
}

show_pool_status() {
    cd $SCRIPT_DIR
    source venv/bin/activate
    python pool_manager.py --status
}

show_assigned_containers() {
    cd $SCRIPT_DIR
    source venv/bin/activate
    python << 'PYTHON_END'
from app import app, db, User, Container
import docker

# Initialize Docker client
try:
    docker_client = docker.from_env()
except:
    docker_client = None

with app.app_context():
    containers = Container.query.all()
    if not containers:
        print('No containers assigned')
    else:
        print('╔════════════════════════════════════════════════════════════════╗')
        print('║         Assigned Containers Details                           ║')
        print('╚════════════════════════════════════════════════════════════════╝')
        print()
        for c in containers:
            user = User.query.get(c.user_id)
            pool_name = c.pool_name if c.pool_name else 'N/A'
            
            # Check actual Docker status
            docker_status = 'unknown'
            if docker_client:
                try:
                    dc = docker_client.containers.get(c.container_id)
                    docker_status = dc.status
                except:
                    docker_status = 'missing'
            
            print('Container ID: {} | User: {}'.format(c.id, user.username))
            print('  Name: {}'.format(c.name))
            print('  Type: {}'.format(c.image_type))
            print('  Pool Name: {}'.format(pool_name))
            print('  IP: 192.168.121.183')
            print('  Port: {}'.format(c.host_port))
            if c.image_type == 'ubuntu-ssh':
                print('  SSH: ssh devuser@192.168.121.183 -p {} (password: devpass123)'.format(c.host_port))
            else:
                print('  URL: http://192.168.121.183:{}'.format(c.host_port))
            print('  DB Status: {} | Docker Status: {}'.format(c.status, docker_status))
            print('  From Pool: {}'.format('Yes' if c.from_pool else 'No'))
            print('-' * 70)
PYTHON_END
}

release_container() {
    show_assigned_containers
    echo ""
    echo -n "Enter container ID to release back to pool: "
    read container_id
    
    # First, check if container exists and show details
    cd $SCRIPT_DIR
    source venv/bin/activate
    python << PYTHON_END
from app import app, db, Container, User
import sys

with app.app_context():
    container = Container.query.get($container_id)
    if not container:
        print('[ERROR] Container not found')
        sys.exit(1)
    
    user = User.query.get(container.user_id)
    print()
    print('╔════════════════════════════════════════════════════════════════╗')
    print('║         Container Release Details                             ║')
    print('╚════════════════════════════════════════════════════════════════╝')
    print()
    print('Container: {}'.format(container.name))
    print('User: {}'.format(user.username))
    print('Type: {}'.format(container.image_type))
    print('IP: 192.168.121.183')
    print('Port: {}'.format(container.host_port))
    print('Pool Name: {}'.format(container.pool_name if container.pool_name else 'N/A'))
    print('From Pool: {}'.format('Yes' if container.from_pool else 'No'))
    print()
    
    if not container.from_pool or not container.pool_name:
        print('[WARNING]  This container is not from the pool - cannot release')
        print('   Use option 6 to delete it permanently instead')
        sys.exit(1)
PYTHON_END
    
    if [ $? -ne 0 ]; then
        return
    fi
    
    # Ask for confirmation in bash
    echo ""
    echo -n "Release this container back to pool? (yes/no): "
    read confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        return
    fi
    
    # Now perform the release
    python << PYTHON_END
from app import app, db, Container, User
import docker
import sys

with app.app_context():
    container = Container.query.get($container_id)
    if not container:
        print('[ERROR] Container not found')
        sys.exit(1)
    
    # Release to pool
    client = docker.from_env()
    try:
        docker_container = client.containers.get(container.container_id)
        docker_container.stop()
        docker_container.remove()
        print('[OK] Stopped and removed container')
    except Exception as e:
        print('[WARNING]  Docker container not found: {}'.format(e))
    
    # Recreate pool container with fresh state
    parts = container.pool_name.split('_')
    if len(parts) >= 4:
        image_type = parts[1]
        port = int(parts[3])
        
        # Get image config
        POOL_CONFIG = {
            'nginx': {'image': 'nginx:alpine', 'port': 80},
            'apache': {'image': 'httpd:alpine', 'port': 80},
            'python': {'image': 'python:3.11-alpine', 'port': 8000},
            'node': {'image': 'node:18-alpine', 'port': 3000},
        }
        
        if image_type in POOL_CONFIG:
            config = POOL_CONFIG[image_type]
            container_config = {
                'image': config['image'],
                'detach': True,
                'ports': {'{}/tcp'.format(config['port']): port},
                'name': container.pool_name,
                'labels': {
                    'pool': 'true',
                    'type': image_type,
                    'status': 'available'
                }
            }
            
            if image_type == 'python':
                container_config['command'] = 'python -m http.server 8000'
                container_config['working_dir'] = '/app'
            elif image_type == 'node':
                container_config['command'] = 'sh -c "while true; do sleep 3600; done"'
                container_config['working_dir'] = '/app'
            
            try:
                new_container = client.containers.run(**container_config)
                print('[OK] Recreated pool container: {} (fresh state)'.format(container.pool_name))
            except Exception as e:
                print('[ERROR] Failed to recreate container: {}'.format(e))
    
    # Remove from database
    db.session.delete(container)
    db.session.commit()
    print('[OK] Container released back to pool successfully!')
PYTHON_END
}

delete_container() {
    show_assigned_containers
    echo ""
    echo -n "Enter container ID to DELETE permanently: "
    read container_id
    
    # First, check if container exists and show details
    cd $SCRIPT_DIR
    source venv/bin/activate
    python << PYTHON_END
from app import app, db, Container, User
import docker
import sys

with app.app_context():
    container = Container.query.get($container_id)
    if not container:
        print('[ERROR] Container not found')
        sys.exit(1)
    
    user = User.query.get(container.user_id)
    
    # Check Docker status
    docker_status = 'unknown'
    try:
        client = docker.from_env()
        dc = client.containers.get(container.container_id)
        docker_status = dc.status
    except:
        docker_status = 'missing'
    
    print()
    print('╔════════════════════════════════════════════════════════════════╗')
    print('║         Container Deletion Details                            ║')
    print('╚════════════════════════════════════════════════════════════════╝')
    print()
    print('Container: {}'.format(container.name))
    print('User: {}'.format(user.username))
    print('Type: {}'.format(container.image_type))
    print('IP: 192.168.121.183')
    print('Port: {}'.format(container.host_port))
    print('DB Status: {} | Docker Status: {}'.format(container.status, docker_status))
    print('Pool Name: {}'.format(container.pool_name if container.pool_name else 'N/A'))
    print('From Pool: {}'.format('Yes' if container.from_pool else 'No'))
    print()
    print('[WARNING]  WARNING: This will PERMANENTLY delete the container!')
    if container.from_pool:
        print('[WARNING]  This will also remove it from the pool permanently!')
    if docker_status == 'missing':
        print('[INFO] Container already missing from Docker - will only remove from database')
PYTHON_END
    
    # Ask for confirmation in bash
    echo ""
    echo -n "DELETE this container permanently? (yes/no): "
    read confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        return
    fi
    
    # Now perform the deletion
    python << PYTHON_END
from app import app, db, Container
import docker
import sys

with app.app_context():
    container = Container.query.get($container_id)
    if not container:
        print('[ERROR] Container not found')
        sys.exit(1)
    
    # Delete container from Docker
    client = docker.from_env()
    try:
        docker_container = client.containers.get(container.container_id)
        docker_container.stop()
        docker_container.remove()
        print('[OK] Stopped and removed Docker container')
    except Exception as e:
        print('[WARNING]  Docker container not found: {}'.format(e))
    
    # Remove from database
    db.session.delete(container)
    db.session.commit()
    print('[OK] Container deleted permanently!')
PYTHON_END
}

force_release_user() {
    list_users
    echo ""
    echo -n "Enter username to release all containers: "
    read username
    
    # First check user and show details
    cd $SCRIPT_DIR
    source venv/bin/activate
    python << PYTHON_END
from app import app, db, Container, User
import sys

with app.app_context():
    user = User.query.filter_by(username='$username').first()
    if not user:
        print('[ERROR] User not found')
        sys.exit(1)
    
    containers = user.containers
    if not containers:
        print('User {} has no containers'.format(user.username))
        sys.exit(0)
    
    print('Found {} containers for {}'.format(len(containers), user.username))
    pool_count = sum(1 for c in containers if c.from_pool)
    print('  - {} from pool (will be reset and released)'.format(pool_count))
    print('  - {} not from pool (will be deleted)'.format(len(containers) - pool_count))
PYTHON_END
    
    if [ $? -ne 0 ]; then
        return
    fi
    
    # Ask for confirmation in bash
    echo ""
    echo -n "Release all containers? (yes/no): "
    read confirm
    if [ "$confirm" != "yes" ]; then
        echo "Cancelled"
        return
    fi
    
    # Now perform the release
    python << PYTHON_END
from app import app, db, Container, User
import docker

with app.app_context():
    user = User.query.filter_by(username='$username').first()
    if not user:
        print('[ERROR] User not found')
    else:
        containers = user.containers
        if containers:
            client = docker.from_env()
            
            # Pool config for recreation
            POOL_CONFIG = {
                'nginx': {'image': 'nginx:alpine', 'port': 80},
                'apache': {'image': 'httpd:alpine', 'port': 80},
                'python': {'image': 'python:3.11-alpine', 'port': 8000},
                'node': {'image': 'node:18-alpine', 'port': 3000},
            }
            
            for container in containers[:]:
                print('Processing {}...'.format(container.name))
                try:
                    dc = client.containers.get(container.container_id)
                    dc.stop()
                    dc.remove()
                    print('  [OK] Stopped and removed')
                except:
                    print('  [WARNING]  Docker container not found')
                
                # If from pool, recreate it
                if container.from_pool and container.pool_name:
                    parts = container.pool_name.split('_')
                    if len(parts) >= 4:
                        image_type = parts[1]
                        port = int(parts[3])
                        
                        if image_type in POOL_CONFIG:
                            config = POOL_CONFIG[image_type]
                            container_config = {
                                'image': config['image'],
                                'detach': True,
                                'ports': {'{}/tcp'.format(config['port']): port},
                                'name': container.pool_name,
                                'labels': {'pool': 'true', 'type': image_type, 'status': 'available'}
                            }
                            
                            if image_type == 'python':
                                container_config['command'] = 'python -m http.server 8000'
                                container_config['working_dir'] = '/app'
                            elif image_type == 'node':
                                container_config['command'] = 'sh -c "while true; do sleep 3600; done"'
                                container_config['working_dir'] = '/app'
                            
                            try:
                                client.containers.run(**container_config)
                                print('  [OK] Released to pool')
                            except:
                                print('  [ERROR] Failed to recreate')
                
                db.session.delete(container)
            
            db.session.commit()
            print('[OK] All containers processed!')
PYTHON_END
}

add_containers() {
    load_config
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         Add Containers to Pool                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Current pool configuration:"
    echo "  Nginx: $NGINX_COUNT containers"
    echo "  Apache: $APACHE_COUNT containers"
    echo "  Python: $PYTHON_COUNT containers"
    echo "  Node: $NODE_COUNT containers"
    echo "  Ubuntu SSH: $SSH_COUNT containers"
    echo ""
    echo "Select container type to add:"
    echo "  1) Nginx"
    echo "  2) Apache"
    echo "  3) Python"
    echo "  4) Node"
    echo "  5) Ubuntu SSH"
    echo "  6) Cancel"
    echo ""
    read -p "Choice: " type_choice
    
    case $type_choice in
        1) TYPE="nginx"; BASE_PORT=8000 ;;
        2) TYPE="apache"; BASE_PORT=8100 ;;
        3) TYPE="python"; BASE_PORT=8200 ;;
        4) TYPE="node"; BASE_PORT=8300 ;;
        5) TYPE="ubuntu-ssh"; BASE_PORT=2200 ;;
        6) return ;;
        *) echo "Invalid choice"; return ;;
    esac
    
    echo ""
    read -p "How many $TYPE containers to add? " count
    
    if ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -le 0 ]; then
        echo "Invalid count"
        return
    fi
    
    cd $SCRIPT_DIR
    source venv/bin/activate
    
    python << PYTHON_END
import docker
import sys

client = docker.from_env()

# Get existing containers of this type
existing = client.containers.list(
    all=True,
    filters={'label': ['pool=true', 'type=$TYPE']}
)

# Find next available index
used_indices = []
for container in existing:
    labels = container.labels
    if 'pool_index' in labels:
        used_indices.append(int(labels['pool_index']))

# Sort to find gaps
used_indices.sort()
next_index = 0
for idx in used_indices:
    if idx == next_index:
        next_index += 1
    else:
        break

# Image configs
POOL_CONFIG = {
    'nginx': {'image': 'nginx:alpine', 'port': 80},
    'apache': {'image': 'httpd:alpine', 'port': 80},
    'python': {'image': 'python:3.11-alpine', 'port': 8000},
    'node': {'image': 'node:18-alpine', 'port': 3000},
    'ubuntu-ssh': {'image': 'ubuntu-ssh:latest', 'port': 22},
}

config = POOL_CONFIG['$TYPE']
print('Adding $count $TYPE containers starting from index {}'.format(next_index))
print()

created = 0
for i in range($count):
    pool_index = next_index + i
    host_port = $BASE_PORT + pool_index
    
    container_name = 'pool_{}_{}_{}'.format('$TYPE', pool_index, host_port)
    
    # Check if port is in use
    port_used = False
    for c in client.containers.list(all=True):
        if c.ports:
            for port, bindings in c.ports.items():
                if bindings:
                    for binding in bindings:
                        if int(binding['HostPort']) == host_port:
                            print('  [WARNING]  Port {} already in use, skipping'.format(host_port))
                            port_used = True
                            break
    
    if port_used:
        continue
    
    container_config = {
        'image': config['image'],
        'detach': True,
        'ports': {'{}/tcp'.format(config['port']): host_port},
        'name': container_name,
        'labels': {
            'pool': 'true',
            'type': '$TYPE',
            'status': 'available',
            'pool_index': str(pool_index)
        }
    }
    
    if '$TYPE' == 'python':
        container_config['command'] = 'python -m http.server 8000'
        container_config['working_dir'] = '/app'
    elif '$TYPE' == 'node':
        container_config['command'] = 'sh -c "while true; do sleep 3600; done"'
        container_config['working_dir'] = '/app'
    
    try:
        container = client.containers.run(**container_config)
        print('  [OK] Created {} on port {}'.format(container_name, host_port))
        created += 1
    except Exception as e:
        print('  [ERROR] Failed to create container on port {}: {}'.format(host_port, e))

print()
print('[OK] Created {} new $TYPE containers'.format(created))
PYTHON_END
    
    # Update config
    case $TYPE in
        nginx) NGINX_COUNT=$((NGINX_COUNT + count)) ;;
        apache) APACHE_COUNT=$((APACHE_COUNT + count)) ;;
        python) PYTHON_COUNT=$((PYTHON_COUNT + count)) ;;
        node) NODE_COUNT=$((NODE_COUNT + count)) ;;
        ubuntu-ssh) SSH_COUNT=$((SSH_COUNT + count)) ;;
    esac
    save_config
}

configure_pool() {
    load_config
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         Configure Pool Sizes                                  ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Current configuration:"
    echo "  1) Nginx: $NGINX_COUNT containers"
    echo "  2) Apache: $APACHE_COUNT containers"
    echo "  3) Python: $PYTHON_COUNT containers"
    echo "  4) Node: $NODE_COUNT containers"
    echo "  5) Ubuntu SSH: $SSH_COUNT containers"
    echo ""
    echo "Note: This only changes the configuration for future initializations."
    echo "Use 'Add containers' to add to existing pool incrementally."
    echo ""
    read -p "Enter new nginx count [$NGINX_COUNT]: " new_nginx
    read -p "Enter new apache count [$APACHE_COUNT]: " new_apache
    read -p "Enter new python count [$PYTHON_COUNT]: " new_python
    read -p "Enter new node count [$NODE_COUNT]: " new_node
    read -p "Enter new ssh count [$SSH_COUNT]: " new_ssh
    
    [ ! -z "$new_nginx" ] && NGINX_COUNT=$new_nginx
    [ ! -z "$new_apache" ] && APACHE_COUNT=$new_apache
    [ ! -z "$new_python" ] && PYTHON_COUNT=$new_python
    [ ! -z "$new_node" ] && NODE_COUNT=$new_node
    [ ! -z "$new_ssh" ] && SSH_COUNT=$new_ssh
    
    save_config
    
    echo ""
    echo "[OK] Configuration saved:"
    echo "  Nginx: $NGINX_COUNT"
    echo "  Apache: $APACHE_COUNT"
    echo "  Python: $PYTHON_COUNT"
    echo "  Node: $NODE_COUNT"
    echo "  Ubuntu SSH: $SSH_COUNT"
    echo ""
    echo "Use 'Reinitialize entire pool' to apply these settings."
}

reinitialize_pool() {
    load_config
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         Reinitialize Entire Pool                              ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Current configuration:"
    echo "  Nginx: $NGINX_COUNT containers"
    echo "  Apache: $APACHE_COUNT containers"
    echo "  Python: $PYTHON_COUNT containers"
    echo "  Node: $NODE_COUNT containers"
    echo "  Ubuntu SSH: $SSH_COUNT containers"
    echo ""
    echo "Specify the number of containers for each service:"
    echo ""
    read -p "Enter nginx count [$NGINX_COUNT]: " new_nginx
    read -p "Enter apache count [$APACHE_COUNT]: " new_apache
    read -p "Enter python count [$PYTHON_COUNT]: " new_python
    read -p "Enter node count [$NODE_COUNT]: " new_node
    read -p "Enter ssh count [$SSH_COUNT]: " new_ssh
    
    # Use new values or keep current
    [ ! -z "$new_nginx" ] && NGINX_COUNT=$new_nginx
    [ ! -z "$new_apache" ] && APACHE_COUNT=$new_apache
    [ ! -z "$new_python" ] && PYTHON_COUNT=$new_python
    [ ! -z "$new_node" ] && NODE_COUNT=$new_node
    [ ! -z "$new_ssh" ] && SSH_COUNT=$new_ssh
    
    # Save the new configuration
    save_config
    
    echo ""
    echo "This will:"
    echo "  - Remove ALL pool containers"
    echo "  - Create new pool with:"
    echo "    • Nginx: $NGINX_COUNT"
    echo "    • Apache: $APACHE_COUNT"
    echo "    • Python: $PYTHON_COUNT"
    echo "    • Node: $NODE_COUNT"
    echo "    • Ubuntu SSH: $SSH_COUNT"
    echo "    • Node: $NODE_COUNT"
    echo ""
    echo "[WARNING]  WARNING: Assigned containers will be unaffected but pool will be fresh!"
    echo ""
    read -p "Continue? (yes/no): " confirm
    
    if [ "$confirm" = "yes" ]; then
        cd $SCRIPT_DIR
        source venv/bin/activate
        
        # Update pool_manager.py config temporarily
        python << PYTHON_END
import re

with open('pool_manager.py', 'r') as f:
    content = f.read()

# Update POOL_CONFIG
content = re.sub(
    r"'nginx': {[^}]+},",
    "'nginx': {'count': $NGINX_COUNT, 'image': 'nginx:alpine', 'port': 80},",
    content
)
content = re.sub(
    r"'apache': {[^}]+},",
    "'apache': {'count': $APACHE_COUNT, 'image': 'httpd:alpine', 'port': 80},",
    content
)
content = re.sub(
    r"'python': {[^}]+},",
    "'python': {'count': $PYTHON_COUNT, 'image': 'python:3.11-alpine', 'port': 8000},",
    content
)
content = re.sub(
    r"'node': {[^}]+},",
    "'node': {'count': $NODE_COUNT, 'image': 'node:18-alpine', 'port': 3000},",
    content
)
content = re.sub(
    r"'ubuntu-ssh': {[^}]+},",
    "'ubuntu-ssh': {'count': $SSH_COUNT, 'image': 'ubuntu-ssh:latest', 'port': 22},",
    content
)

with open('pool_manager.py', 'w') as f:
    f.write(content)

print('[OK] Updated pool configuration')
PYTHON_END
        
        python pool_manager.py --init
        echo ""
        echo "[OK] Pool reinitialized successfully!"
    else
        echo "Cancelled"
    fi
}

show_system_status() {
    cd $SCRIPT_DIR
    source venv/bin/activate
    
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║         System Status                                          ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Users
    echo " USERS:"
    python << 'PYTHON_END'
from app import app, db, User
with app.app_context():
    print('   Total: {}'.format(User.query.count()))
PYTHON_END
    echo ""
    
    # Assigned containers
    echo " ASSIGNED CONTAINERS:"
    python << 'PYTHON_END'
from app import app, db, Container
with app.app_context():
    total = Container.query.count()
    from_pool = Container.query.filter_by(from_pool=True).count()
    print('   Total: {} ({} from pool)'.format(total, from_pool))
PYTHON_END
    echo ""
    
    # Pool status
    echo "🏊 POOL STATUS:"
    python pool_manager.py --status | head -12
    echo ""
    
    # Flask app
    echo " FLASK APP:"
    if pgrep -f "flask run" > /dev/null; then
        echo "   Status: [OK] Running"
    else
        echo "   Status: [FAILED] Stopped"
    fi
    echo ""
}

# Main loop
clear
load_config

while true; do
    show_menu
    read -p "Select option: " choice
    echo ""
    
    case $choice in
        1) list_users ;;
        2) delete_user ;;
        3) show_pool_status ;;
        4) show_assigned_containers ;;
        5) release_container ;;
        6) delete_container ;;
        7) force_release_user ;;
        8) add_containers ;;
        9) configure_pool ;;
        10) reinitialize_pool ;;
        11) show_system_status ;;
        12) echo "Goodbye!"; exit 0 ;;
        *) echo "Invalid option" ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    clear
done
