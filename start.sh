#!/bin/bash

# Kirill API - Docker stack launcher
# Поднимает API и MongoDB из docker-compose.

echo "Сборка и запуск backend + MongoDB..."
docker compose up --build
