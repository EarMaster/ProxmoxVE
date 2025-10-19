#!/usr/bin/env bash

# Copyright (c) 2021-2025 community-scripts ORG
# Author: EarMaster
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://kitchenowl.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  ca-certificates \
  curl
msg_ok "Installed Dependencies"


msg_info "Setup Docker Repository"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list
$STD apt-get update
msg_ok "Setup Docker Repository"

msg_info "Installing Docker"
$STD apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
msg_ok "Installed Docker"

msg_info "Setting up Kitchen Owl"
mkdir -p /opt/kitchenowl/data/postgres
cd /opt/kitchenowl || exit

# Generate secure credentials
DB_PASSWORD=$(openssl rand -base64 18 | tr -dc 'a-zA-Z0-9' | cut -c1-16)
JWT_SECRET=$(openssl rand -base64 32)

# Save credentials to file
cat <<EOF >/root/kitchenowl.creds
Kitchen Owl Credentials
========================
Database User: kitchenowl
Database Password: ${DB_PASSWORD}
Database Name: kitchenowl_db
JWT Secret: ${JWT_SECRET}

Access URL: http://$(hostname -I | awk '{print $1}'):8080
EOF

# Create docker-compose.yml
cat <<EOF >/opt/kitchenowl/docker-compose.yml
services:
  postgres:
    image: postgres:16-alpine
    container_name: kitchenowl_postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: kitchenowl
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: kitchenowl_db
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U kitchenowl"]
      interval: 10s
      timeout: 5s
      retries: 5

  kitchenowl:
    image: tombursch/kitchenowl:latest
    container_name: kitchenowl
    restart: unless-stopped
    ports:
      - "8080:8080"
    environment:
      JWT_SECRET_KEY: ${JWT_SECRET}
      DB_DRIVER: postgresql
      DB_HOST: postgres
      DB_PORT: 5432
      DB_USER: kitchenowl
      DB_PASSWORD: ${DB_PASSWORD}
      DB_NAME: kitchenowl_db
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "curl -f http://localhost:8080 || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
EOF

msg_ok "Created Configuration"

msg_info "Starting Kitchen Owl"
$STD docker compose up -d
msg_ok "Started Kitchen Owl"

msg_info "Waiting for Kitchen Owl to be ready"
sleep 10
until docker exec kitchenowl curl -f http://localhost:8080 >/dev/null 2>&1; do
  sleep 2
done
msg_ok "Kitchen Owl is ready"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt -y autoremove
$STD apt -y autoclean
$STD apt -y clean
msg_ok "Cleaned"
