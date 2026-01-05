.PHONY: help setup up halt reload provision ssh destroy logs status clean check test verify

help: ## Show this help message
	@echo "PaaS Platform - Make Commands"
	@echo "=============================="
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

test: ## Run comprehensive diagnostic tests
	@./test.sh

verify: ## Verify platform is working correctly
	@./verify.sh

check: ## Check prerequisites (quick)
	@echo "Checking prerequisites..."
	@./setup.sh

setup: check ## Run setup script
	@echo "Setup complete!"

up: ## Start the VM and deploy the platform
	@echo "Starting VM and deploying platform..."
	cd infrastructure && vagrant up

halt: ## Stop the VM
	@echo "Stopping VM..."
	cd infrastructure && vagrant halt

reload: ## Restart the VM
	@echo "Restarting VM..."
	cd infrastructure && vagrant reload

provision: ## Re-run Ansible provisioning
	@echo "Re-provisioning VM..."
	cd infrastructure && vagrant provision

ssh: ## SSH into the VM
	cd infrastructure && vagrant ssh

destroy: ## Destroy the VM
	@echo "Destroying VM..."
	@./teardown.sh

logs: ## View Flask app logs
	cd infrastructure && vagrant ssh -c "sudo journalctl -u paas-app -f"

status: ## Check VM status
	cd infrastructure && vagrant status

clean: destroy ## Clean everything (destroy VM)
	@echo "Cleanup complete!"

# Development targets
dev-install: ## Install Python dependencies locally
	cd app && python3 -m venv venv && \
	. venv/bin/activate && \
	pip install -r requirements.txt

dev-run: ## Run Flask app locally
	cd app && \
	. venv/bin/activate && \
	python app.py

# Docker commands (run inside VM)
docker-ps: ## Show running containers
	cd infrastructure && vagrant ssh -c "docker ps"

docker-ps-all: ## Show all containers
	cd infrastructure && vagrant ssh -c "docker ps -a"

docker-images: ## Show Docker images
	cd infrastructure && vagrant ssh -c "docker images"

# Service management
service-status: ## Check Flask app service status
	cd infrastructure && vagrant ssh -c "sudo systemctl status paas-app"

service-restart: ## Restart Flask app service
	cd infrastructure && vagrant ssh -c "sudo systemctl restart paas-app"

service-stop: ## Stop Flask app service
	cd infrastructure && vagrant ssh -c "sudo systemctl stop paas-app"

service-start: ## Start Flask app service
	cd infrastructure && vagrant ssh -c "sudo systemctl start paas-app"

# Monitoring commands
monitor-status: ## Check container monitor status
	cd infrastructure && vagrant ssh -c "systemctl status container-monitor.timer"

monitor-logs: ## View monitor logs (live)
	cd infrastructure && vagrant ssh -c "tail -f /opt/my-paas/container_monitor.log"

monitor-check: ## Run manual health check
	cd infrastructure && vagrant ssh -c "cd /opt/my-paas && source venv/bin/activate && python container_monitor.py"

monitor-helper: ## Open interactive monitor helper
	cd infrastructure && vagrant ssh -c "sudo bash /opt/my-paas/monitor_helper.sh"

deploy-monitoring: ## Deploy monitoring system to existing installation
	@chmod +x deploy_monitoring.sh
	@./deploy_monitoring.sh
