#!/usr/bin/env python3
"""
PaaS Platform MVP - Container Deployment Application
A simple platform that allows users to provision Docker containers on demand.
"""

import os
import random
import shutil
from pathlib import Path
from flask import Flask, render_template, redirect, url_for, flash, request, send_from_directory
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from flask_sqlalchemy import SQLAlchemy
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
import docker
from datetime import datetime

# Initialize Flask app
app = Flask(__name__)
app.config['SECRET_KEY'] = os.environ.get('SECRET_KEY', 'dev-secret-key-change-in-production')
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///paas_platform.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['UPLOAD_FOLDER'] = '/opt/my-paas/user_files'
app.config['MAX_CONTENT_LENGTH'] = 50 * 1024 * 1024  # 50MB max file size
app.config['ALLOWED_EXTENSIONS'] = {'html', 'css', 'js', 'jpg', 'jpeg', 'png', 'gif', 'txt', 'md', 'json'}

# Create upload folder if it doesn't exist
os.makedirs(app.config['UPLOAD_FOLDER'], exist_ok=True)

# Available container images
AVAILABLE_IMAGES = {
    'nginx': {
        'name': 'nginx:alpine',
        'port': 80,
        'description': 'Lightweight web server (perfect for static sites)',
        'category': 'Web Server'
    },
    'apache': {
        'name': 'httpd:alpine',
        'port': 80,
        'description': 'Apache HTTP Server',
        'category': 'Web Server'
    },
    'node': {
        'name': 'node:18-alpine',
        'port': 3000,
        'description': 'Node.js runtime environment',
        'category': 'Runtime'
    },
    'python': {
        'name': 'python:3.11-alpine',
        'port': 8000,
        'description': 'Python runtime with built-in HTTP server',
        'category': 'Runtime'
    },
    'wordpress': {
        'name': 'wordpress:latest',
        'port': 80,
        'description': 'WordPress CMS (requires database)',
        'category': 'CMS'
    },
    'redis': {
        'name': 'redis:alpine',
        'port': 6379,
        'description': 'Redis in-memory data store',
        'category': 'Database'
    },
    'mysql': {
        'name': 'mysql:8',
        'port': 3306,
        'description': 'MySQL database server',
        'category': 'Database'
    },
    'postgres': {
        'name': 'postgres:alpine',
        'port': 5432,
        'description': 'PostgreSQL database server',
        'category': 'Database'
    }
}

# Initialize extensions
db = SQLAlchemy(app)
login_manager = LoginManager(app)
login_manager.login_view = 'login'
login_manager.login_message = 'Please log in to access this page.'

# Initialize Docker client
try:
    docker_client = docker.from_env()
except Exception as e:
    print(f"Warning: Could not connect to Docker: {e}")
    docker_client = None

# Database Models
class User(UserMixin, db.Model):
    """User model for authentication"""
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(200), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    containers = db.relationship('Container', backref='owner', lazy=True, cascade='all, delete-orphan')
    
    def set_password(self, password):
        """Hash and set the user password"""
        self.password_hash = generate_password_hash(password)
    
    def check_password(self, password):
        """Verify the user password"""
        return check_password_hash(self.password_hash, password)
    
    def __repr__(self):
        return f'<User {self.username}>'


class Container(db.Model):
    """Container model to track user's deployed containers"""
    id = db.Column(db.Integer, primary_key=True)
    container_id = db.Column(db.String(64), unique=True, nullable=False)
    name = db.Column(db.String(100), nullable=True)  # User-friendly name
    image_name = db.Column(db.String(100), nullable=False)
    image_type = db.Column(db.String(50), nullable=False, default='nginx')
    status = db.Column(db.String(20), nullable=False)
    host_port = db.Column(db.Integer, nullable=False)
    container_port = db.Column(db.Integer, nullable=False)
    has_custom_files = db.Column(db.Boolean, default=False)
    from_pool = db.Column(db.Boolean, default=True)  # Track if container is from pool
    pool_name = db.Column(db.String(100), nullable=True)  # Original pool container name
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    def __repr__(self):
        return f'<Container {self.container_id[:12]}>'


@login_manager.user_loader
def load_user(user_id):
    """Load user by ID for Flask-Login"""
    return User.query.get(int(user_id))


# Helper Functions
def allowed_file(filename):
    """Check if file extension is allowed"""
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in app.config['ALLOWED_EXTENSIONS']


def get_user_files_path(user_id, db_container_id):
    """Get the path for user's container files using database container ID"""
    path = Path(app.config['UPLOAD_FOLDER']) / str(user_id) / f"container_{db_container_id}"
    path.mkdir(parents=True, exist_ok=True)
    return path


def get_random_port():
    """Generate a random port number between 8000-9000"""
    used_ports = [c.host_port for c in Container.query.all()]
    while True:
        port = random.randint(8000, 9000)
        if port not in used_ports:
            return port


def get_pool_availability():
    """Get the count of available containers in the pool for each type"""
    if not docker_client:
        return {}
    
    availability = {}
    for image_type in ['nginx', 'apache', 'node', 'python']:
        try:
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
            availability[image_type] = len(available)
        except Exception as e:
            print(f"Error getting pool availability for {image_type}: {e}")
            availability[image_type] = 0
    
    return availability


def assign_container_from_pool(image_type='nginx', container_name=None, user_id=None, mount_files=False, db_container_id=None):
    """
    Assign a pre-built container from the pool to a user.
    Returns: tuple (container_id, host_port, status, pool_name) or (None, None, error_message, None)
    """
    if not docker_client:
        return None, None, "Docker client not available", None
    
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
            return None, None, f"No available {image_type} containers in pool. Please contact administrator.", None
        
        # Take the first available container
        container = available[0]
        pool_name = container.name  # Save original pool name
        
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
                'status': 'assigned',  # Mark as assigned!
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
        print(f"Error assigning container from pool: {e}")
        return None, None, str(e), None


def launch_container(image_type='nginx', container_name=None, user_id=None, mount_files=False, db_container_id=None):
    """
    Launch a Docker container - now uses pool system.
    Returns: tuple (container_id, host_port, status, pool_name) or (None, None, error_message, None)
    """
    return assign_container_from_pool(image_type, container_name, user_id, mount_files, db_container_id)


def stop_and_remove_container(container_id):
    """
    Stop and remove a Docker container.
    Returns: True if successful, False otherwise
    """
    if not docker_client:
        return False
    
    try:
        container = docker_client.containers.get(container_id)
        container.stop(timeout=10)
        container.remove()
        return True
    except Exception as e:
        print(f"Error stopping container: {e}")
        return False


def release_container_to_pool(container_id, pool_name):
    """
    Release a container back to the pool by resetting it to available status.
    Returns: True if successful, False otherwise
    """
    if not docker_client:
        return False
    
    try:
        container = docker_client.containers.get(container_id)
        
        # Stop and remove current container
        container.stop(timeout=10)
        container.remove()
        
        # Recreate the original pool container
        # Parse the pool name to extract image type and port
        # Format: pool_<type>_<index>_<port>
        parts = pool_name.split('_')
        if len(parts) >= 4 and parts[0] == 'pool':
            image_type = parts[1]
            port = int(parts[3])
            
            if image_type in AVAILABLE_IMAGES:
                image_config = AVAILABLE_IMAGES[image_type]
                
                container_config = {
                    'image': image_config['name'],
                    'detach': True,
                    'ports': {f"{image_config['port']}/tcp": port},
                    'name': pool_name,
                    'labels': {
                        'pool': 'true',
                        'type': image_type,
                        'status': 'available'
                    }
                }
                
                # Add commands
                if image_type == 'node':
                    container_config['command'] = 'sh -c "while true; do sleep 3600; done"'
                    container_config['working_dir'] = '/app'
                elif image_type == 'python':
                    container_config['command'] = 'python -m http.server 8000'
                    container_config['working_dir'] = '/app'
                
                docker_client.containers.run(**container_config)
                return True
        
        return False
    except Exception as e:
        print(f"Error releasing container to pool: {e}")
        return False


def get_container_status(container_id):
    """
    Get the current status of a container.
    Returns: status string or 'stopped'
    """
    if not docker_client:
        return 'unknown'
    
    try:
        container = docker_client.containers.get(container_id)
        return container.status
    except docker.errors.NotFound:
        return 'stopped'
    except Exception as e:
        print(f"Error getting container status: {e}")
        return 'error'


# Routes
@app.route('/')
def index():
    """Home page - redirect to dashboard if logged in, otherwise to login"""
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))
    return redirect(url_for('login'))


@app.route('/register', methods=['GET', 'POST'])
def register():
    """User registration page"""
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))
    
    if request.method == 'POST':
        username = request.form.get('username')
        email = request.form.get('email')
        password = request.form.get('password')
        confirm_password = request.form.get('confirm_password')
        
        # Validation
        if not all([username, email, password, confirm_password]):
            flash('All fields are required.', 'error')
            return render_template('register.html')
        
        if password != confirm_password:
            flash('Passwords do not match.', 'error')
            return render_template('register.html')
        
        if len(password) < 6:
            flash('Password must be at least 6 characters long.', 'error')
            return render_template('register.html')
        
        # Check if user exists
        if User.query.filter_by(username=username).first():
            flash('Username already exists.', 'error')
            return render_template('register.html')
        
        if User.query.filter_by(email=email).first():
            flash('Email already registered.', 'error')
            return render_template('register.html')
        
        # Create new user
        user = User(username=username, email=email)
        user.set_password(password)
        db.session.add(user)
        db.session.commit()
        
        flash('Registration successful! Please log in.', 'success')
        return redirect(url_for('login'))
    
    return render_template('register.html')


@app.route('/login', methods=['GET', 'POST'])
def login():
    """User login page"""
    if current_user.is_authenticated:
        return redirect(url_for('dashboard'))
    
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        if not all([username, password]):
            flash('Please provide both username and password.', 'error')
            return render_template('login.html')
        
        user = User.query.filter_by(username=username).first()
        
        if user and user.check_password(password):
            login_user(user)
            flash(f'Welcome back, {user.username}!', 'success')
            next_page = request.args.get('next')
            return redirect(next_page) if next_page else redirect(url_for('dashboard'))
        else:
            flash('Invalid username or password.', 'error')
    
    return render_template('login.html')


@app.route('/logout')
@login_required
def logout():
    """Logout the current user"""
    logout_user()
    flash('You have been logged out.', 'info')
    return redirect(url_for('login'))


@app.route('/dashboard')
@login_required
def dashboard():
    """User dashboard showing their containers"""
    # Update container statuses
    for container in current_user.containers:
        current_status = get_container_status(container.container_id)
        if current_status != container.status:
            container.status = current_status
            db.session.commit()
    
    # Get pool availability counts
    pool_availability = get_pool_availability()
    
    return render_template('dashboard.html', 
                         user=current_user,
                         available_images=AVAILABLE_IMAGES,
                         pool_availability=pool_availability)


@app.route('/launch', methods=['POST'])
@login_required
def launch():
    """Launch a new container for the user"""
    if not docker_client:
        flash('Docker is not available. Please contact the administrator.', 'error')
        return redirect(url_for('dashboard'))
    
    # Get form data
    image_type = request.form.get('image_type', 'nginx')
    container_name = request.form.get('container_name', '')
    
    # Launch the container (assign from pool)
    container_id, host_port, status, pool_name = launch_container(
        image_type=image_type,
        container_name=container_name,
        user_id=current_user.id,
        mount_files=False
    )
    
    if container_id:
        image_config = AVAILABLE_IMAGES.get(image_type, AVAILABLE_IMAGES['nginx'])
        
        # Save to database
        container = Container(
            container_id=container_id,
            name=container_name or f"{image_type}-{host_port}",
            image_name=image_config['name'],
            image_type=image_type,
            status=status,
            host_port=host_port,
            container_port=image_config['port'],
            from_pool=True,
            pool_name=pool_name,
            user_id=current_user.id
        )
        db.session.add(container)
        db.session.commit()
        
        flash(f'{image_config["description"]} launched successfully on port {host_port}!', 'success')
    else:
        flash(f'Failed to launch container: {status}', 'error')
    
    return redirect(url_for('dashboard'))


@app.route('/stop/<int:container_id>', methods=['POST'])
@login_required
def stop_container(container_id):
    """Stop and remove a user's container (or release back to pool)"""
    container = Container.query.get_or_404(container_id)
    
    # Verify ownership
    if container.user_id != current_user.id:
        flash('You do not have permission to stop this container.', 'error')
        return redirect(url_for('dashboard'))
    
    # Check if container is from pool
    if container.from_pool and container.pool_name:
        # Release back to pool
        if release_container_to_pool(container.container_id, container.pool_name):
            db.session.delete(container)
            db.session.commit()
            flash('Container released back to pool successfully.', 'success')
        else:
            flash('Failed to release container to pool.', 'warning')
            container.status = 'stopped'
            db.session.commit()
    else:
        # Stop and remove the container (non-pool containers)
        if stop_and_remove_container(container.container_id):
            db.session.delete(container)
            db.session.commit()
            flash('Container stopped and removed successfully.', 'success')
        else:
            flash('Failed to stop container. It may already be stopped.', 'warning')
            container.status = 'stopped'
            db.session.commit()
    
    return redirect(url_for('dashboard'))


@app.route('/refresh')
@login_required
def refresh_status():
    """Refresh container statuses"""
    for container in current_user.containers:
        current_status = get_container_status(container.container_id)
        if current_status != container.status:
            container.status = current_status
    db.session.commit()
    flash('Container statuses refreshed.', 'info')
    return redirect(url_for('dashboard'))


@app.route('/upload/<int:container_id>', methods=['GET', 'POST'])
@login_required
def upload_files(container_id):
    """Upload files to a container"""
    container = Container.query.get_or_404(container_id)
    
    # Verify ownership
    if container.user_id != current_user.id:
        flash('You do not have permission to access this container.', 'error')
        return redirect(url_for('dashboard'))
    
    if request.method == 'POST':
        # Check if files were uploaded
        if 'files[]' not in request.files:
            flash('No files selected.', 'error')
            return redirect(request.url)
        
        files = request.files.getlist('files[]')
        uploaded_count = 0
        
        # Get user's container directory using database container ID
        user_files_path = get_user_files_path(current_user.id, container.id)
        
        for file in files:
            if file and file.filename and allowed_file(file.filename):
                filename = secure_filename(file.filename)
                file.save(user_files_path / filename)
                uploaded_count += 1
            elif file and file.filename:
                flash(f'File type not allowed: {file.filename}', 'warning')
        
        if uploaded_count > 0:
            container.has_custom_files = True
            db.session.commit()
            flash(f'{uploaded_count} file(s) uploaded successfully!', 'success')
            
            # Restart container to mount files if it's a web server
            if container.image_type in ['nginx', 'apache', 'python']:
                flash('Restarting container to apply changes...', 'info')
                # Stop old container
                stop_and_remove_container(container.container_id)
                
                # Launch new container with files mounted
                new_container_id, new_host_port, status, pool_name = launch_container(
                    image_type=container.image_type,
                    container_name=container.name,
                    user_id=current_user.id,
                    mount_files=True,
                    db_container_id=container.id  # Pass database container ID
                )
                
                if new_container_id:
                    container.container_id = new_container_id
                    container.host_port = new_host_port  # Update the port!
                    container.status = status
                    if pool_name:
                        container.pool_name = pool_name
                    db.session.commit()
                    flash(f'Container restarted on port {new_host_port}', 'success')
        
        return redirect(url_for('upload_files', container_id=container.id))
    
    # Get list of uploaded files using database container ID
    user_files_path = get_user_files_path(current_user.id, container.id)
    uploaded_files = []
    if user_files_path.exists():
        uploaded_files = [f.name for f in user_files_path.iterdir() if f.is_file()]
    
    return render_template('upload.html', container=container, files=uploaded_files)


@app.route('/delete_file/<int:container_id>/<filename>', methods=['POST'])
@login_required
def delete_file(container_id, filename):
    """Delete a file from a container"""
    container = Container.query.get_or_404(container_id)
    
    # Verify ownership
    if container.user_id != current_user.id:
        flash('You do not have permission to access this container.', 'error')
        return redirect(url_for('dashboard'))
    
    user_files_path = get_user_files_path(current_user.id, container.id)
    file_path = user_files_path / secure_filename(filename)
    
    if file_path.exists() and file_path.is_file():
        file_path.unlink()
        flash(f'File "{filename}" deleted successfully.', 'success')
    else:
        flash(f'File "{filename}" not found.', 'error')
    
    return redirect(url_for('upload_files', container_id=container.id))


# Initialize database
def init_db():
    """Initialize the database"""
    with app.app_context():
        db.create_all()
        print("Database initialized successfully!")


if __name__ == '__main__':
    init_db()
    # Run the Flask app
    # In production, use a proper WSGI server like Gunicorn
    app.run(host='0.0.0.0', port=5000, debug=True)
