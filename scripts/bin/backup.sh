#!/usr/bin/env bash
set -euo pipefail

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

# shellcheck disable=SC2016 # $env:USERPROFILE is intentionally passed to PowerShell
WSL2_DIR="$(wslpath -u "$(powershell.exe -c '$env:USERPROFILE' | tr -d '\r')")/Documents/WSL2"
FILENAME_DUMP="$(date '+%Y-%m-%dT%H%M%S')_devtool-wsl2.tar"
EXCLUDE_DIRS=(
	".asdf"
	".bashrc.d/devtool"
	".cache"
	".docker"
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
	2>/dev/null | cut -f1)

log_info "Starting backup: $(numfmt --to=iec "${TOTAL_SIZE}") to compress"
tar -c \
	"${EXCLUDE_ARGS[@]}" \
	"${HOME}" | pv -p -t -e -r -a -s "${TOTAL_SIZE}" > "/tmp/${FILENAME_DUMP}"

mkdir -p "${WSL2_DIR}/Backups"
rsync -avP "/tmp/${FILENAME_DUMP}" "${WSL2_DIR}/Backups"
log_info "Backup completed: ${WSL2_DIR}/Backups/${FILENAME_DUMP}"
