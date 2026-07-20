#!/usr/bin/env bash
set -euo pipefail
[[ -n "${DEVTOOL_TRACE:-}" ]] && set -x

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

_apt_get() {
	if [[ -n "${DRY_RUN}" ]]; then
		echo "[DRY_RUN] apt-get $*"
	else
		apt-get "$@"
	fi
}

# --- fish PPA ---
log_info "Add fish-shell PPA"
if [[ -z "${DRY_RUN}" ]] && compgen -G "/etc/apt/sources.list.d/fish-shell-ubuntu-release-4-*.list" > /dev/null 2>&1; then
	log_info "fish-shell PPA already exists, skipping"
elif [[ -n "${DRY_RUN}" ]]; then
	echo "[DRY_RUN] add-apt-repository ppa:fish-shell/release-4"
else
	add-apt-repository --yes ppa:fish-shell/release-4
fi

# --- apt update + install ---
log_info "apt update + install fish"
_apt_get --yes update
_apt_get --yes install --no-install-recommends \
	fish

# --- verify ---
log_info "Verify fish installation"
_run type -p fish

log_info "40-fish.sh complete"
