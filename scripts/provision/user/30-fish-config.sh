#!/usr/bin/env bash
set -euxo pipefail

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

DRY_RUN="${DRY_RUN:-}"
read -ra CURL_OPTS <<< "${CURL_OPTS:--sfSL --retry 3 --retry-delay 2 --retry-connrefused}"

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

# --- ~/.config/mise ---
log_info "Create ~/.config/mise"
mkdir --parents "${HOME}/.config/mise"

# --- fisher ---
log_info "Install fisher function"
mkdir --parents "${HOME}/.config/fish/functions"
FISHER_DEST="${HOME}/.config/fish/functions/fisher.fish"
if [[ -f "${FISHER_DEST}" ]]; then
	log_info "fisher.fish already exists, skipping"
else
	if [[ -n "${DRY_RUN}" ]]; then
		echo "[DRY_RUN] curl -sfSL -o ${FISHER_DEST} https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish"
	else
		curl "${CURL_OPTS[@]}" -o "${FISHER_DEST}" \
			https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish
	fi
fi

# --- ~/.config/fish/config.fish ---
log_info "Deploy ~/.config/fish/config.fish"
install -m 0644 "${PROVISION_ROOT}/files/config.fish" "${HOME}/.config/fish/config.fish"

# --- ~/.config/fish/functions/fish_prompt.fish ---
log_info "Deploy ~/.config/fish/functions/fish_prompt.fish"
install -m 0644 "${PROVISION_ROOT}/files/fish_prompt.fish" "${HOME}/.config/fish/functions/fish_prompt.fish"

log_info "30-fish-config.sh done"
