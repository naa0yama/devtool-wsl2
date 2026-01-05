#!/usr/bin/env bash
set -euo pipefail

# Colors
__CLR_INFO='\033[0;36m'   # Cyan
__CLR_WARN='\033[0;33m'   # Yellow
__CLR_RESET='\033[0m'

# shellcheck disable=SC2016 # $env:USERPROFILE is intentionally passed to PowerShell
WSL2_DIR="$(wslpath -u "$(powershell.exe -c '$env:USERPROFILE' | tr -d '\r')")/Documents/WSL2"
FILENAME_DUMP="$(date '+%Y-%m-%dT%H%M%S')_devtool-wsl2.tar"
EXCLUDE_DIRS=(
	".asdf"
	".cache"
	".docker"
	".dotnet"
	".local"
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

echo "${__CLR_INFO}[INFO]${__CLR_RESET}Calculating directory size..."
TOTAL_SIZE=$(du -sb "${HOME}" \
	"${EXCLUDE_ARGS[@]}" \
	2>/dev/null | cut -f1)

echo "${__CLR_INFO}[INFO]${__CLR_RESET}Starting backup: $(numfmt --to=iec "${TOTAL_SIZE}") to compress"
tar -c \
	"${EXCLUDE_ARGS[@]}" \
	"${HOME}" | pv -p -t -e -r -a -s "${TOTAL_SIZE}" > "/tmp/${FILENAME_DUMP}"

mkdir -p "${WSL2_DIR}/Backups"
rsync -avP "/tmp/${FILENAME_DUMP}" "${WSL2_DIR}/Backups"
echo "${__CLR_INFO}[INFO]${__CLR_RESET}Backup completed: ${WSL2_DIR}/Backups/${FILENAME_DUMP}"
