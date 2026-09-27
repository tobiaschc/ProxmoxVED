#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tobias Chavarria
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/finanze/finanze

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt install -y \
  build-essential \
  libssl-dev \
  libffi-dev \
  nginx
msg_ok "Installed Dependencies"

fetch_and_deploy_gh_release "finanze" "finanze/finanze" "tarball"

msg_info "Installing Backend"
PYTHON_VERSION="3.14" setup_uv
$STD uv venv --python 3.14 /opt/finanze/.venv
$STD uv pip install -p /opt/finanze/.venv/bin/python -r /opt/finanze/requirements.txt
mkdir -p /opt/finanze/.storage
msg_ok "Installed Backend"

PNPM_VERSION=$(sed -n 's/.*"packageManager": "pnpm@\([^"+]*\).*/\1/p' /opt/finanze/frontend/app/package.json)
NODE_VERSION="24" NODE_MODULE="pnpm@${PNPM_VERSION:-11}" setup_nodejs

msg_info "Building Frontend"
cd /opt/finanze/frontend/app
$STD pnpm install --frozen-lockfile
$STD pnpm run build
cp -r dist /opt/finanze-frontend
cat <<EOF >/opt/finanze-frontend/env-config.js
window.runtimeVariables = {
  BASE_URL: 'http://${LOCAL_IP}:7592',
};
EOF
msg_ok "Built Frontend"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/finanze.service
[Unit]
Description=Finanze
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/finanze/finanze
ExecStart=/opt/finanze/.venv/bin/python /opt/finanze/finanze/__main__.py --port 7592 --data-dir /opt/finanze/.storage --log-dir /opt/finanze/.storage/logs --log-level INFO
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now finanze
msg_ok "Created Service"

msg_info "Configuring Nginx"
cat <<EOF >/etc/nginx/sites-available/finanze
server {
  listen 8080;
  server_name _;
  root /opt/finanze-frontend;
  index index.html;

  location / {
    try_files \$uri \$uri/ /index.html;
  }
}
EOF
nginx_enable_site "finanze"
msg_ok "Configured Nginx"

motd_ssh
customize
cleanup_lxc
