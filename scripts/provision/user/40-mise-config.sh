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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROVISION_ROOT="${PROVISION_ROOT:-${SCRIPT_DIR}/..}"

# --- ~/.config/mise/config.toml ---
log_info "Deploy ~/.config/mise/config.toml"
mkdir --parents "${HOME}/.config/mise"
install -m 0644 "${PROVISION_ROOT}/files/mise-config.toml" "${HOME}/.config/mise/config.toml"

log_info "40-mise-config.sh done"
