#!/usr/bin/env bash
set -euo pipefail

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

# --- 1. cloud-init clean ---
log_info "cloud-init clean"
if command -v cloud-init > /dev/null 2>&1; then
	_run cloud-init clean --logs --seed
else
	log_warn "cloud-init not found, skipping"
fi

# --- 2. machine-id truncate ---
log_info "truncate machine-id"
_run truncate --size=0 /etc/machine-id
if [[ -f /var/lib/dbus/machine-id ]]; then
	_run truncate --size=0 /var/lib/dbus/machine-id
fi

# --- 3. SSH host keys ---
log_info "remove SSH host keys"
if [[ -n "${DRY_RUN}" ]]; then
	echo "[DRY_RUN] find /etc/ssh -maxdepth 1 -name ssh_host_* -delete"
else
	find /etc/ssh -maxdepth 1 -name 'ssh_host_*' -delete
fi

# --- 4. apt cache clean ---
log_info "apt cache clean"
_run apt-get clean
if [[ -n "${DRY_RUN}" ]]; then
	echo "[DRY_RUN] rm -rf /var/lib/apt/lists/*"
else
	rm -rf /var/lib/apt/lists/*
fi

# --- 5. truncate log files ---
log_info "truncate log files"
if [[ -n "${DRY_RUN}" ]]; then
	echo "[DRY_RUN] find /var/log -type f -exec truncate --size=0 {} +"
else
	find /var/log -type f -exec truncate --size=0 {} +
fi

# --- 6. bash history / cloud-init instance-id / tmp ---
log_info "clear history / cloud-init instances / tmp"
if [[ -n "${DRY_RUN}" ]]; then
	echo "[DRY_RUN] rm -f /root/.bash_history"
	echo "[DRY_RUN] find /home -maxdepth 2 -name .bash_history -delete"
	echo "[DRY_RUN] rm -rf /var/lib/cloud/instances/*"
	echo "[DRY_RUN] find /tmp /var/tmp -mindepth 1 -delete"
else
	rm -f /root/.bash_history
	find /home -maxdepth 2 -name '.bash_history' -delete
	rm -rf /var/lib/cloud/instances/*
	find /tmp /var/tmp -mindepth 1 -delete
fi

# WHY-NOT: virt-sparsify — image 外部で virt-customize 完了後に別途実行するため
# スクリプト内では実行しない

log_info "finalize.sh complete"
