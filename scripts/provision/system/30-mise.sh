#!/usr/bin/env bash
set -euxo pipefail

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

read -ra CURL_OPTS <<< "${CURL_OPTS:--sfSL --retry 3 --retry-delay 2 --retry-connrefused}"
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

# --- mise GPG keyring ---
log_info "Install mise GPG key"
_run install -dm 755 /etc/apt/keyrings
if [[ -z "${DRY_RUN}" ]] && [[ -f /etc/apt/keyrings/mise-archive-keyring.pub ]]; then
	log_info "mise keyring already exists, skipping"
else
	_run curl "${CURL_OPTS[@]}" https://mise.jdx.dev/gpg-key.pub \
		--output /etc/apt/keyrings/mise-archive-keyring.pub
fi

# --- mise apt repository ---
log_info "Add mise apt repository"
if [[ -z "${DRY_RUN}" ]] && [[ -f /etc/apt/sources.list.d/mise.list ]]; then
	log_info "mise apt list already exists, skipping"
elif [[ -n "${DRY_RUN}" ]]; then
	echo "[DRY_RUN] write /etc/apt/sources.list.d/mise.list"
else
	echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.pub arch=amd64] https://mise.jdx.dev/deb stable main" \
		| tee /etc/apt/sources.list.d/mise.list > /dev/null
fi

# --- apt update + install ---
log_info "apt update + install mise"
_apt_get --yes update
_apt_get --yes install --no-install-recommends \
	mise

# --- verify ---
log_info "Verify mise installation"
_run type -p mise

log_info "30-mise.sh complete"
