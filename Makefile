.PHONY: help run sync upgrade clean

help:
	@echo "Available commands:"
	@echo "  make run      - Start the server"
	@echo "  make sync     - Install/sync dependencies"
	@echo "  make upgrade  - Upgrade dependencies to latest versions"
	@echo "  make clean    - Clean up cache and temp files"

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
