.PHONY: help run sync upgrade clean docker-build docker-up docker-down docker-logs docker-logs-app docker-logs-redis docker-restart docker-clean docker-shell docker-redis-cli

help:
	@echo "Available commands:"
	@echo ""
	@echo "Local Development:"
	@echo "  make run              - Start the server locally (no Docker)"
	@echo "  make sync             - Install/sync dependencies"
	@echo "  make upgrade          - Upgrade dependencies to latest versions"
	@echo "  make clean            - Clean up cache and temp files"
	@echo ""
	@echo "Docker Development:"
	@echo "  make docker-build     - Build Docker images"
	@echo "  make docker-up        - Start all services (app + Redis)"
	@echo "  make docker-down      - Stop and remove containers"
	@echo "  make docker-logs      - View logs (follow mode)"
	@echo "  make docker-logs-app  - View app logs only"
	@echo "  make docker-logs-redis- View Redis logs only"
	@echo "  make docker-restart   - Restart all services"
	@echo "  make docker-clean     - Remove containers, volumes, and images"
	@echo "  make docker-shell     - Open shell in app container"
	@echo "  make docker-redis-cli - Open Redis CLI for debugging"

# Local Development Commands
run:
	uv run python server.py

sync:
	uv sync

upgrade:
	uv lock --upgrade
	uv sync

clean:
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
	find . -type f -name "*.pyo" -delete 2>/dev/null || true
	find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
	@echo "Cleaned up cache files"

# Docker Commands
docker-build:
	@echo "Building Docker images..."
	docker-compose build

docker-up:
	@echo "Starting services (app + Redis)..."
	docker-compose up -d
	@echo ""
	@echo "Services started! Access the API at: http://localhost:8010"
	@echo "View logs with: make docker-logs"

docker-down:
	@echo "Stopping services..."
	docker-compose down

docker-logs:
	@echo "Following logs (Ctrl+C to stop)..."
	docker-compose logs -f

docker-logs-app:
	@echo "Following app logs (Ctrl+C to stop)..."
	docker-compose logs -f app

docker-logs-redis:
	@echo "Following Redis logs (Ctrl+C to stop)..."
	docker-compose logs -f redis

docker-restart:
	@echo "Restarting services..."
	docker-compose restart
	@echo "Services restarted!"

docker-clean:
	@echo "Removing containers, volumes, and images..."
	docker-compose down -v --rmi all
	@echo "Cleanup complete!"

docker-shell:
	@echo "Opening shell in app container..."
	docker-compose exec app /bin/bash

docker-redis-cli:
	@echo "Opening Redis CLI..."
	docker-compose exec redis redis-cli
