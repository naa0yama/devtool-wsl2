#!/usr/bin/env bash
set -euxo pipefail

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

read -ra CURL_OPTS <<< "${CURL_OPTS:--sfSL --retry 3 --retry-delay 2 --retry-connrefused}"
DEFAULT_USERNAME="${DEFAULT_USERNAME:-user}"
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

# --- Docker Engine keyring ---
log_info "Install Docker Engine GPG key"
_run install -m 0755 -d /etc/apt/keyrings
# WHY-NOT: curl | gpg --dearmor — pipeline failures are silent; writing to .asc then chmod is safer
_run curl "${CURL_OPTS[@]}" https://download.docker.com/linux/ubuntu/gpg \
	--output /etc/apt/keyrings/docker.asc
_run chmod a+r /etc/apt/keyrings/docker.asc

# --- Docker apt repository ---
log_info "Add Docker apt repository"
if [[ -n "${DRY_RUN}" ]]; then
	echo "[DRY_RUN] write /etc/apt/sources.list.d/docker.list"
else
	# shellcheck source=/dev/null
	echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
		| tee /etc/apt/sources.list.d/docker.list > /dev/null
fi

# --- apt update + install ---
log_info "apt update + install Docker Engine packages"
_apt_get --yes update
_apt_get --yes install --no-install-recommends \
	docker-ce \
	docker-ce-cli \
	containerd.io \
	docker-buildx-plugin \
	docker-compose-plugin

# --- Add user to docker group ---
log_info "Add ${DEFAULT_USERNAME} to docker group"
_run usermod -aG docker "${DEFAULT_USERNAME}"

log_info "20-docker-engine.sh complete"
