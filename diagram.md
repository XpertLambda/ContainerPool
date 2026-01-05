# Container Pool PaaS Platform - Architecture Diagrams

## 1. High-Level System Architecture

```mermaid
graph TB
    subgraph "Host Machine (Linux)"
        Vagrant[Vagrant]
        Ansible[Ansible]
        KVM[libvirt/KVM]
    end

    subgraph "Virtual Machine (Ubuntu 22.04)"
        subgraph "System Services"
            systemd[systemd]
            Flask[Flask App<br/>:5000]
            Monitor[Container Monitor<br/>Timer: 30s]
        end
        
        subgraph "Data Layer"
            SQLite[(SQLite DB)]
            UserFiles[/User Files<br/>/opt/my-paas/user_files/]
        end
        
        subgraph "Docker Engine"
            Docker[Docker Daemon]
            
            subgraph "Container Pool"
                nginx1[nginx:8000]
                nginx2[nginx:8001]
                apache1[apache:8100]
                python1[python:8200]
                node1[node:8300]
                ssh1[ubuntu-ssh:2200]
            end
        end
    end

    subgraph "Users"
        Browser[Web Browser]
        SSH_Client[SSH Client]
    end

    Browser -->|HTTP :5000| Flask
    SSH_Client -->|SSH :2200-2210| ssh1
    Browser -->|HTTP :8000-8399| nginx1

    Vagrant -->|Provision| KVM
    Ansible -->|Configure| KVM
    KVM -->|Creates| systemd

    Flask -->|Manages| Docker
    Flask -->|Read/Write| SQLite
    Flask -->|Store| UserFiles
    Monitor -->|Health Check| Docker
    Monitor -->|Update| SQLite

    Docker -->|Runs| nginx1
    Docker -->|Runs| nginx2
    Docker -->|Runs| apache1
    Docker -->|Runs| python1
    Docker -->|Runs| node1
    Docker -->|Runs| ssh1
```

## 2. Container Pool Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Available: Pool Initialization
    
    Available --> Assigned: User Launches Container
    Assigned --> Available: User Releases Container
    Assigned --> Failed: Container Crashes
    Failed --> Available: Monitor Recovers
    
    Available --> Stopped: Docker Issue
    Stopped --> Available: Monitor Restarts
    
    note right of Available : Labels: pool=true, status=available"
    note right of Assigned : Labels: pool=true, status=assigned", user_id=X
    note right of Failed : Container missing from Docker
```

## 3. User Request Flow

```mermaid
sequenceDiagram
    actor User
    participant Browser
    participant Flask as Flask App
    participant DB as SQLite
    participant Docker as Docker Daemon
    participant Container as Pool Container

    User->>Browser: Navigate to /dashboard
    Browser->>Flask: GET /dashboard
    Flask->>DB: Query user containers
    DB-->>Flask: Container list
    Flask-->>Browser: Render dashboard

    User->>Browser: Click "Launch Container"
    Browser->>Flask: POST /launch (type=nginx)
    Flask->>Docker: List available pool containers
    Docker-->>Flask: Available container found
    Flask->>Docker: Stop container
    Flask->>Docker: Remove container
    Flask->>Docker: Run with assigned labels
    Docker-->>Flask: New container ID
    Flask->>DB: INSERT container record
    Flask-->>Browser: Redirect to dashboard
    
    User->>Browser: Access container
    Browser->>Container: HTTP request :8000
    Container-->>Browser: Response
```

## 4. Container Recovery Flow

```mermaid
sequenceDiagram
    participant Timer as systemd Timer
    participant Monitor as container_monitor.py
    participant DB as SQLite
    participant Docker as Docker Daemon
    participant Pool as Pool Container

    Timer->>Monitor: Trigger (every 30s)
    Monitor->>DB: SELECT all containers
    DB-->>Monitor: Container list
    
    loop For each container
        Monitor->>Docker: Get container status
        alt Container Running
            Docker-->>Monitor: Status: running
            Monitor->>Monitor: Mark healthy
        else Container Missing
            Docker-->>Monitor: NotFound Error
            Monitor->>Docker: Find available pool container
            Docker-->>Monitor: Available container
            Monitor->>Docker: Stop & Remove
            Monitor->>Docker: Run with user config
            Docker-->>Monitor: New container ID
            Monitor->>DB: UPDATE container record
            Monitor->>Monitor: Log recovery
        end
    end
    
    Monitor->>Monitor: Log summary
```

## 5. File Upload Flow

```mermaid
sequenceDiagram
    actor User
    participant Browser
    participant Flask as Flask App
    participant FS as File System
    participant Docker as Docker Daemon
    participant Container as User Container

    User->>Browser: Select files to upload
    Browser->>Flask: POST /upload/container_id (files[])
    Flask->>Flask: Validate file extensions
    Flask->>FS: Save files to /opt/my-paas/user_files/user_id/container_id/
    FS-->>Flask: Files saved
    Flask->>Docker: Stop current container
    Flask->>Docker: Remove container
    Flask->>Docker: Run with volume mount
    Note over Docker: Volume: user_files → /usr/share/nginx/html
    Docker-->>Flask: New container ID & port
    Flask->>Flask: Update database
    Flask-->>Browser: Redirect with success message
    
    User->>Browser: Access container
    Browser->>Container: GET /index.html
    Container->>Container: Read from mounted volume
    Container-->>Browser: User's HTML file
```

## 6. Component Dependencies

```mermaid
graph LR
    subgraph "Infrastructure"
        A[Vagrant] --> B[libvirt/KVM]
        B --> C[Ubuntu VM]
        D[Ansible] --> C
    end

    subgraph "Services"
        C --> E[systemd]
        E --> F[paas-app.service]
        E --> G[container-monitor.timer]
        G --> H[container-monitor.service]
    end

    subgraph "Application"
        F --> I[Flask App]
        I --> J[Flask-Login]
        I --> K[Flask-SQLAlchemy]
        I --> L[Docker SDK]
        H --> M[Monitor Script]
        M --> L
    end

    subgraph "Data"
        K --> N[(SQLite)]
        I --> O[User Files]
    end

    subgraph "Containers"
        L --> P[Docker Daemon]
        P --> Q[nginx:alpine]
        P --> R[httpd:alpine]
        P --> S[python:alpine]
        P --> T[node:alpine]
        P --> U[ubuntu-ssh]
    end
```

## 7. Network Architecture

```mermaid
graph TB
    subgraph "External Network"
        Client[Client Browser/SSH]
    end

    subgraph "Host Machine"
        HostPorts[Port Forwarding<br/>5000, 8000-8100, 2200-2210]
    end

    subgraph "VM Network (192.168.121.0/24)"
        VM_IP[VM: 192.168.121.183]
        
        subgraph "Services"
            Flask_Port[Flask :5000]
        end
        
        subgraph "Container Ports"
            Nginx_Ports[Nginx :8000-8099]
            Apache_Ports[Apache :8100-8199]
            Python_Ports[Python :8200-8299]
            Node_Ports[Node :8300-8399]
            SSH_Ports[SSH :2200-2210]
        end
    end

    Client --> HostPorts
    HostPorts --> VM_IP
    VM_IP --> Flask_Port
    VM_IP --> Nginx_Ports
    VM_IP --> Apache_Ports
    VM_IP --> Python_Ports
    VM_IP --> Node_Ports
    VM_IP --> SSH_Ports
```

## 8. Database Schema

```mermaid
erDiagram
    USER {
        int id PK
        string username UK
        string email UK
        string password_hash
        datetime created_at
    }
    
    CONTAINER {
        int id PK
        string container_id UK
        string name
        string image_name
        string image_type
        string status
        int host_port
        int container_port
        boolean has_custom_files
        boolean from_pool
        string pool_name
        int user_id FK
        datetime created_at
    }
    
    USER ||--o{ CONTAINER : "owns"
```

## 9. Pool Container Labels

```mermaid
graph TD
    subgraph "Docker Container Labels"
        A[Container] --> B{pool=true}
        B --> C[type]
        C --> D[nginx]
        C --> E[apache]
        C --> F[python]
        C --> G[node]
        C --> H[ubuntu-ssh]
        
        B --> I[status]
        I --> J[available]
        I --> K[assigned]
        
        B --> L[pool_index]
        L --> M[0, 1, 2, ...]
        
        K --> N[user_id]
        N --> O[User ID number]
    end

    subgraph "Naming Convention"
        P[pool_type_index_port]
        Q[pool_nginx_0_8000]
        R[pool_apache_2_8102]
    end
```

## 10. Deployment Pipeline

```mermaid
flowchart TD
    A[Start: make up] --> B[Vagrant reads Vagrantfile]
    B --> C{VM exists?}
    C -->|No| D[Download Ubuntu box]
    C -->|Yes| E[Start existing VM]
    D --> F[Create VM with KVM]
    F --> G[Configure networking]
    G --> H[Sync app directory]
    H --> I[Run Ansible playbook]
    
    subgraph "Ansible Provisioning"
        I --> J[Install system packages]
        J --> K[Install Docker]
        K --> L[Copy app files to /opt/my-paas]
        L --> M[Create Python venv]
        M --> N[Install requirements.txt]
        N --> O[Create systemd services]
        O --> P[Pull Docker images]
        P --> Q[Build ubuntu-ssh image]
        Q --> R[Start Flask service]
        R --> S[Start Monitor timer]
    end
    
    S --> T[Platform Ready]
    E --> T
    
    T --> U{Pool initialized?}
    U -->|No| V[Run pool_manager.py --init]
    V --> W[Create 15 containers]
    W --> X[Ready for users]
    U -->|Yes| X
```

## 11. Admin Operations Flow

```mermaid
flowchart LR
    subgraph "Admin Tools"
        A[admin_helper.sh] --> B{Menu Choice}
        
        B --> C[User Management]
        C --> C1[List Users]
        C --> C2[Delete User]
        
        B --> D[Container Management]
        D --> D1[Pool Status]
        D --> D2[Assigned Containers]
        D --> D3[Release Container]
        D --> D4[Delete Container]
        
        B --> E[Pool Management]
        E --> E1[Add Containers]
        E --> E2[Configure Sizes]
        E --> E3[Reinitialize Pool]
    end

    subgraph "Monitor Tools"
        F[monitor_helper.sh] --> G{Menu Choice}
        
        G --> H[Run Health Check]
        G --> I[View Logs]
        G --> J[Start/Stop Timer]
        G --> K[Change Interval]
    end
```

## 12. Complete System Overview

```mermaid
graph TB
    subgraph "Layer 1: Host"
        Host[Linux Host<br/>Arch/Ubuntu/RHEL]
        Vagrant[Vagrant + libvirt]
        Ansible[Ansible]
    end

    subgraph "Layer 2: Virtual Machine"
        VM[Ubuntu 22.04 VM<br/>192.168.121.183<br/>2GB RAM, 2 CPU]
    end

    subgraph "Layer 3: System Services"
        SD[systemd]
        PaaS[paas-app.service<br/>Flask on :5000]
        Mon[container-monitor.timer<br/>Every 30 seconds]
    end

    subgraph "Layer 4: Application"
        Flask[app.py<br/>Routes, Models, Logic]
        Pool[pool_manager.py<br/>Pool CLI]
        Monitor[container_monitor.py<br/>Health & Recovery]
    end

    subgraph "Layer 5: Data"
        DB[(SQLite<br/>paas_platform.db)]
        Files[/User Files<br/>user_files/]
    end

    subgraph "Layer 6: Docker"
        Docker[Docker Engine]
        
        subgraph "Pool Containers"
            N1[nginx x5<br/>:8000-8004]
            A1[apache x3<br/>:8100-8102]
            P1[python x3<br/>:8200-8202]
            No1[node x2<br/>:8300-8301]
            S1[ubuntu-ssh x2<br/>:2200-2201]
        end
    end

    subgraph "Layer 7: Users"
        Browser[Web Browser]
        SSH[SSH Client]
    end

    Host --> Vagrant
    Host --> Ansible
    Vagrant --> VM
    Ansible --> VM
    VM --> SD
    SD --> PaaS
    SD --> Mon
    PaaS --> Flask
    Mon --> Monitor
    Flask --> DB
    Flask --> Files
    Flask --> Docker
    Monitor --> Docker
    Monitor --> DB
    Pool --> Docker
    Docker --> N1
    Docker --> A1
    Docker --> P1
    Docker --> No1
    Docker --> S1
    Browser --> Flask
    Browser --> N1
    SSH --> S1
```

---

## How to View These Diagrams

1. **VS Code**: Install the "Markdown Preview Mermaid Support" extension
2. **GitHub**: Mermaid diagrams render automatically in markdown files
3. **Online**: Use [Mermaid Live Editor](https://mermaid.live/)
4. **CLI**: Use `mmdc` (mermaid-cli) to generate PNG/SVG files

```bash
# Install mermaid-cli
npm install -g @mermaid-js/mermaid-cli

# Generate PNG
mmdc -i diagram.md -o diagram.png
```
