#!/bin/bash
# Quick Container Crash Test - Just provide container ID

echo "🧪 Quick Container Crash & Recovery Test"
echo "════════════════════════════════════════"
echo ""

cd /home/xpert/Desktop/Projects/platform-deployement/infrastructure

# Show all containers
echo "Available containers:"
echo "───────────────────────────────────────"
vagrant ssh -c "cd /opt/my-paas && source venv/bin/activate && python3 << 'EOF'
from app import app, db, Container, User
import docker

client = docker.from_env()

with app.app_context():
    containers = Container.query.all()
    if not containers:
        print('No containers found!')
        print()
        print('Please launch a container first:')
        print('  1. Go to: http://192.168.121.183:5000')
        print('  2. Login and click \"Launch Container\"')
        exit(1)
    
    print(f\"{'ID':<4} | {'Name':<15} | {'User':<12} | {'Type':<8} | {'Port':<6} | {'Status'}\")
    print('-' * 75)
    for c in containers:
        user = User.query.get(c.user_id)
        username = user.username if user else 'N/A'
        try:
            dc = client.containers.get(c.container_id)
            status = dc.status
        except:
            status = 'missing'
        
        print(f\"{c.id:<4} | {c.name:<15} | {username:<12} | {c.image_type:<8} | {c.host_port if c.host_port else 'N/A':<6} | {status}\")
EOF
" 2>/dev/null | grep -v "WARNING"

echo ""
echo "Enter container ID to crash:"
echo "───────────────────────────────────────"
read -p "Container ID: " container_id

if [ -z "$container_id" ]; then
    echo "❌ No ID entered!"
    exit 1
fi

# Get container details
echo ""
echo "Fetching container details..."
container_info=$(vagrant ssh -c "cd /opt/my-paas && source venv/bin/activate && python3 << 'EOF'
from app import app, db, Container, User
import docker

client = docker.from_env()

with app.app_context():
    c = Container.query.get($container_id)
    if not c:
        print('ERROR: Container not found')
        exit(1)
    
    user = User.query.get(c.user_id)
    username = user.username if user else 'N/A'
    
    try:
        dc = client.containers.get(c.container_id)
        status = dc.status
    except:
        status = 'missing'
    
    print(f'NAME:{c.name}')
    print(f'USER:{username}')
    print(f'TYPE:{c.image_type}')
    print(f'PORT:{c.host_port}')
    print(f'DOCKER_ID:{c.container_id}')
    print(f'STATUS:{status}')
EOF
" 2>/dev/null | grep -v "WARNING")

if echo "$container_info" | grep -q "ERROR:"; then
    echo "❌ Container ID $container_id not found!"
    exit 1
fi

# Parse container info
container_name=$(echo "$container_info" | grep "NAME:" | cut -d':' -f2)
container_user=$(echo "$container_info" | grep "USER:" | cut -d':' -f2)
container_type=$(echo "$container_info" | grep "TYPE:" | cut -d':' -f2)
old_port=$(echo "$container_info" | grep "PORT:" | cut -d':' -f2)
docker_id=$(echo "$container_info" | grep "DOCKER_ID:" | cut -d':' -f2)
container_status=$(echo "$container_info" | grep "STATUS:" | cut -d':' -f2)

echo ""
echo "Container Details:"
echo "───────────────────────────────────────"
echo "  Name: $container_name"
echo "  User: $container_user"
echo "  Type: $container_type"
echo "  Port: $old_port"
echo "  Docker ID: ${docker_id:0:12}..."
echo "  Status: $container_status"
echo ""

read -p "Crash this container? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Cancelled."
    exit 0
fi

echo ""
echo "💥 Crashing container..."
echo "───────────────────────────────────────"
vagrant ssh -c "docker stop $docker_id 2>/dev/null && docker rm $docker_id 2>/dev/null" 2>/dev/null | grep -v "WARNING"
echo "✓ Container stopped and removed from Docker"

# Verify it's gone
sleep 1
check=$(vagrant ssh -c "docker ps -a --format '{{.ID}}' | grep ${docker_id:0:12}" 2>/dev/null | wc -l)
if [ "$check" = "0" ]; then
    echo "✓ Verified: Container removed successfully"
else
    echo "⚠️  Warning: Container might still exist"
fi

echo ""
echo "Current Containers Status:"
echo "───────────────────────────────────────"
vagrant ssh -c "cd /opt/my-paas && source venv/bin/activate && python3 << 'EOF'
from app import app, db, Container, User

with app.app_context():
    containers = Container.query.all()
    if containers:
        print(f\"{'ID':<4} | {'Name':<15} | {'User':<12} | {'Type':<8} | {'Port':<6} | {'Status'}\")
        print('-' * 75)
        for c in containers:
            user = User.query.get(c.user_id)
            username = user.username if user else 'N/A'
            print(f\"{c.id:<4} | {c.name:<15} | {username:<12} | {c.image_type:<8} | {c.host_port if c.host_port else 'N/A':<6} | {c.status}\")
    else:
        print('No containers found')
EOF
" 2>/dev/null | grep -v "WARNING"

echo ""
echo "Recovery Options:"
echo "───────────────────────────────────────"
echo "  A) Wait for automatic recovery (~2 minutes)"
echo "  B) Trigger manual recovery now (instant)"
echo ""
read -p "Choose (A/B): " recovery_choice

if [ "$recovery_choice" = "B" ] || [ "$recovery_choice" = "b" ]; then
    echo ""
    echo "⚡ Running manual recovery..."
    vagrant ssh -c "cd /opt/my-paas && source venv/bin/activate && python container_monitor.py" 2>/dev/null | grep -E "(Starting|WARNING|Container|recovered|Failed|Summary|Healthy|Recovered)" | grep -v "LegacyAPIWarning"
    echo ""
else
    echo ""
    echo "⏳ Waiting for automatic recovery (checking every 10 seconds)..."
    echo ""
    
    for i in {1..12}; do
        printf "Checking... [%d/12]\r" $i
        sleep 10
        
        # Check if recovered
        status=$(vagrant ssh -c "cd /opt/my-paas && source venv/bin/activate && python3 -c \"from app import app, Container; import docker; client = docker.from_env(); app.app_context().push(); c = Container.query.get($container_id); dc = client.containers.get(c.container_id) if c and c.container_id else None; print(dc.status if dc else 'missing')\" 2>/dev/null" | tail -1)
        
        if [ "$status" = "running" ]; then
            echo ""
            echo "✓ Recovery detected after $((i*10)) seconds!"
            break
        fi
    done
    echo ""
fi

echo ""
echo "Verification:"
echo "───────────────────────────────────────"

recovery_check=$(vagrant ssh -c "cd /opt/my-paas && source venv/bin/activate && python3 << 'EOF'
from app import app, db, Container, User
import docker

client = docker.from_env()

with app.app_context():
    c = Container.query.get($container_id)
    if not c:
        print('❌ Container not found in database!')
        exit(1)
    
    user = User.query.get(c.user_id)
    username = user.username if user else 'N/A'
    
    try:
        dc = client.containers.get(c.container_id)
        docker_status = dc.status
        new_docker_id = c.container_id
    except:
        docker_status = 'missing'
        new_docker_id = 'N/A'
    
    print('Recovery Results:')
    print('─' * 40)
    print(f'Container: {c.name}')
    print(f'User: {username}')
    print(f'Type: {c.image_type}')
    print()
    print(f'Old Docker ID: $docker_id')
    print(f'New Docker ID: {new_docker_id}')
    print()
    print(f'Old Port: $old_port')
    print(f'New Port: {c.host_port}')
    print()
    print(f'Docker Status: {docker_status}')
    print(f'DB Status: {c.status}')
    print()
    
    print(f'RESULT:{docker_status}')
    print(f'NEW_PORT:{c.host_port}')
    print(f'NEW_DOCKER:{new_docker_id}')
EOF
" 2>/dev/null | grep -v "WARNING")

# Parse results
result_status=$(echo "$recovery_check" | grep "RESULT:" | cut -d':' -f2)
new_port=$(echo "$recovery_check" | grep "NEW_PORT:" | cut -d':' -f2)
new_docker_id=$(echo "$recovery_check" | grep "NEW_DOCKER:" | cut -d':' -f2)

echo ""
if [ "$result_status" = "running" ]; then
    echo "╔════════════════════════════════════════╗"
    echo "║    ✅ RECOVERY SUCCESSFUL! ✅          ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "Results:"
    echo "  • Old Docker ID: ${docker_id:0:12}..."
    echo "  • New Docker ID: ${new_docker_id:0:12}..."
    echo "  • Old Port: $old_port"
    echo "  • New Port: $new_port"
    
    if [ "$old_port" != "$new_port" ]; then
        echo "  • ⚠️  Port changed!"
    else
        echo "  • ✓ Port unchanged"
    fi
    
    echo ""
    echo "Access at: http://192.168.121.183:$new_port"
else
    echo "╔════════════════════════════════════════╗"
    echo "║    ❌ RECOVERY FAILED ❌               ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "Status: $result_status"
    echo ""
    echo "Check logs: vagrant ssh -c 'tail -50 /opt/my-paas/container_monitor.log'"
fi

echo ""
echo "═══════════════════════════════════════"
echo "Test Complete!"
echo ""
echo "View logs: vagrant ssh -c 'tail -20 /opt/my-paas/container_monitor.log'"
echo ""
