#!/usr/bin/env bash
set -euo pipefail

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

# shellcheck disable=SC2016 # $env:USERPROFILE is intentionally passed to PowerShell
WSL2_DIR="$(wslpath -u "$(powershell.exe -c '$env:USERPROFILE' | tr -d '\r')")/Documents/WSL2"
FILENAME_DUMP="$(date '+%Y-%m-%dT%H%M%S')_devtool-wsl2.tar"

# Cleanup on error
cleanup() {
	local exit_code=$?
	if [[ ${exit_code} -ne 0 ]]; then
		log_erro "Backup failed (exit code: ${exit_code}), cleaning up..."
		rm -f "/tmp/${FILENAME_DUMP}" "${WSL2_DIR}/Backups/${FILENAME_DUMP}" 2>/dev/null || true
	fi
	exit "${exit_code}"
}
trap cleanup EXIT INT TERM HUP
EXCLUDE_DIRS=(
	".asdf"
	".bashrc.d/devtool"
	".cache"
	".docker"
	".local/share/mise"
	".local/state/mise"
	".dotnet"
	".vscode-remote-containers"
	".vscode-server"
)

EXCLUDE_ARGS=()
for dir in "${EXCLUDE_DIRS[@]}"; do
	EXCLUDE_ARGS+=("--exclude=${dir}")
done

cat <<__EOF__> /dev/stdout
# ==============================================================================
# devtool-wsl2 backup tools
#
# WSL2 Directory: "${WSL2_DIR}"
# Filename      : "${FILENAME_DUMP}"
# Excludes      : "${EXCLUDE_ARGS[@]}"
# ==============================================================================

__EOF__

log_info "Calculating directory size..."
TOTAL_SIZE=$(du -sb "${HOME}" \
	"${EXCLUDE_ARGS[@]}" \
	2>/dev/null | cut -f1) || true

log_info "Starting backup: $(numfmt --to=iec "${TOTAL_SIZE}") to compress"
mkdir -p "${WSL2_DIR}/Backups"
tar -c \
	"${EXCLUDE_ARGS[@]}" \
	"${HOME}" | pv -p -t -e -r -a -s "${TOTAL_SIZE}" > "/tmp/${FILENAME_DUMP}"

rsync -avP "/tmp/${FILENAME_DUMP}" "${WSL2_DIR}/Backups"
log_info "Backup completed: ${WSL2_DIR}/Backups/${FILENAME_DUMP}"
