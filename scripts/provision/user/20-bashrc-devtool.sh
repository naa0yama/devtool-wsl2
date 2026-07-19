#!/usr/bin/env bash
set -euxo pipefail

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

DRY_RUN="${DRY_RUN:-}"

_run() {
	if [[ -n "${DRY_RUN}" ]]; then
		echo "[DRY_RUN] $*"
	else
		"$@"
	fi
}

# root 実行禁止 (HOME 依存)
if [[ "${EUID}" -eq 0 ]]; then
	log_erro "This script must not run as root (HOME-dependent)"
	exit 1
fi

# Source directory: relative to this script, or via PROVISION_ROOT
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVISION_ROOT="${PROVISION_ROOT:-${SCRIPT_DIR}/../../..}"
SRC_DIR="${PROVISION_ROOT}/.bashrc.d/devtool"

if [[ ! -d "${SRC_DIR}" ]]; then
	log_erro "Source directory not found: ${SRC_DIR}"
	exit 1
fi

# --- copy .bashrc.d/devtool to HOME ---
log_info "Copy ${SRC_DIR} to ${HOME}/.bashrc.d/devtool/"
_run mkdir -p "${HOME}/.bashrc.d/devtool"
if [[ -n "${DRY_RUN}" ]]; then
	echo "[DRY_RUN] rsync --archive --checksum ${SRC_DIR}/ ${HOME}/.bashrc.d/devtool/"
else
	rsync --archive --checksum "${SRC_DIR}/" "${HOME}/.bashrc.d/devtool/"
fi

log_info "20-bashrc-devtool.sh done"
