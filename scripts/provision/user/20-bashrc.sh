#!/usr/bin/env bash
set -euo pipefail
[[ -n "${DEVTOOL_TRACE:-}" ]] && set -x

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

# Must not run as root (HOME-dependent)
if [[ "${EUID}" -eq 0 ]]; then
	log_erro "This script must not run as root (HOME-dependent)"
	exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVISION_ROOT="${PROVISION_ROOT:-${SCRIPT_DIR}/..}"

# --- deploy ~/.bashrc ---
log_info "Deploy ~/.bashrc"
install -m 0644 "${PROVISION_ROOT}/files/bashrc" "${HOME}/.bashrc"

# --- deploy ~/.bashrc.d/devtool ---
SRC_DIR="${PROVISION_ROOT}/files/bashrc.d/devtool"
if [[ -d "${SRC_DIR}" ]]; then
	log_info "Deploy ${SRC_DIR} to ${HOME}/.bashrc.d/devtool/"
	mkdir -p "${HOME}/.bashrc.d/devtool"
	rsync --archive --checksum "${SRC_DIR}/" "${HOME}/.bashrc.d/devtool/"
fi

log_info "20-bashrc.sh done"
