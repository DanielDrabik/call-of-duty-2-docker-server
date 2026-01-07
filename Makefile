.PHONY: help up down logs restart build clean

help:
	@echo "Available commands:"
	@echo "  make up       - Start server in detached mode"
	@echo "  make down     - Stop server"
	@echo "  make logs     - View server logs"
	@echo "  make restart  - Restart server"
	@echo "  make build    - Build server image"
	@echo "  make clean    - Stop and remove containers, networks, volumes"

up:
	@if [ -f docker-compose.override.yml ]; then \
		echo "Starting with override file..."; \
		docker compose -f docker-compose.yaml -f docker-compose.override.yml up -d; \
	else \
		echo "Starting without override file..."; \
		docker compose up -d; \
	fi

down:
	@if [ -f docker-compose.override.yml ]; then \
		docker compose -f docker-compose.yaml -f docker-compose.override.yml down; \
	else \
		docker compose down; \
	fi

logs:
	@if [ -f docker-compose.override.yml ]; then \
		docker compose -f docker-compose.yaml -f docker-compose.override.yml logs -f; \
	else \
		docker compose logs -f; \
	fi

restart:
	@if [ -f docker-compose.override.yml ]; then \
		docker compose -f docker-compose.yaml -f docker-compose.override.yml restart; \
	else \
		docker compose restart; \
	fi

build:
	@if [ -f docker-compose.override.yml ]; then \
		docker compose -f docker-compose.yaml -f docker-compose.override.yml build; \
	else \
		docker compose build; \
	fi

clean:
	@if [ -f docker-compose.override.yml ]; then \
		docker compose -f docker-compose.yaml -f docker-compose.override.yml down -v; \
	else \
		docker compose down -v; \
	fi
