#!/usr/bin/env bash
set -euo pipefail
[[ -n "${DEVTOOL_TRACE:-}" ]] && set -x

log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }

DEVTOOL_ENV="${DEVTOOL_ENV:-wsl}"

if [[ "${DEVTOOL_ENV}" != "vm" ]]; then
	log_info "DEVTOOL_ENV=${DEVTOOL_ENV}: skip ubuntu user cleanup (vm only)"
	exit 0
fi

log_info "DEVTOOL_ENV=vm: remove ubuntu user and home directory"
# WHY-NOT: hard failure — ubuntu user may not exist in minimal base images; exit non-zero would abort provisioning unnecessarily
userdel --remove ubuntu || true

log_info "40-cleanup-ubuntu.sh complete"
