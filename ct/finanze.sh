#!/usr/bin/env bash
_CS_DEFAULT_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main"
_cs_boot="${COMMUNITY_SCRIPTS_CORE_DIR:-$(dirname "${BASH_SOURCE[0]}")/../../core}/core/build.func"
source "$_cs_boot" 2>/dev/null || source <(curl -fsSL "${COMMUNITY_SCRIPTS_CORE_URL:-https://raw.githubusercontent.com/community-scripts/core/main}/core/build.func")
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Tobias Chavarria
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/finanze/finanze

APP="Finanze"
var_tags="${var_tags:-finance}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-6}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
#var_arm64="${var_arm64:-no}" # unset = ask the user; set yes/no only when verified
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/finanze ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "finanze" "finanze/finanze"; then
    msg_info "Stopping Service"
    systemctl stop finanze
    msg_ok "Stopped Service"

    create_backup /opt/finanze/.storage /opt/finanze-frontend/env-config.js

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release "finanze" "finanze/finanze" "tarball"

    msg_info "Installing Backend"
    PYTHON_VERSION="3.14" setup_uv
    $STD uv venv --clear --python 3.14 /opt/finanze/.venv
    $STD uv pip install -p /opt/finanze/.venv/bin/python -r /opt/finanze/requirements.txt
    msg_ok "Installed Backend"

    PNPM_VERSION=$(sed -n 's/.*"packageManager": "pnpm@\([^"+]*\).*/\1/p' /opt/finanze/frontend/app/package.json)
    NODE_VERSION="24" NODE_MODULE="pnpm@${PNPM_VERSION:-11}" setup_nodejs

    msg_info "Building Frontend"
    cd /opt/finanze/frontend/app
    $STD pnpm install --frozen-lockfile
    $STD pnpm run build
    rm -rf /opt/finanze-frontend
    cp -r dist /opt/finanze-frontend
    msg_ok "Built Frontend"

    restore_backup
    if [[ ! -f /opt/finanze-frontend/env-config.js ]]; then
      cat <<EOF >/opt/finanze-frontend/env-config.js
window.runtimeVariables = {
  BASE_URL: 'http://${LOCAL_IP}:7592',
};
EOF
    fi

    msg_info "Starting Service"
    systemctl start finanze
    msg_ok "Started Service"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:8080${CL}"
