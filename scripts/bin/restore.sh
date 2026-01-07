#!/usr/bin/env bash
set -euo pipefail

# Colors
__CLR_INFO='\033[0;36m'   # Cyan
__CLR_WARN='\033[0;33m'   # Yellow
__CLR_RESET='\033[0m'

# shellcheck disable=SC2016 # $env:USERPROFILE is intentionally passed to PowerShell
__WSL2_DIR="$(wslpath -u "$(powershell.exe -c '$env:USERPROFILE' | tr -d '\r')")/Documents/WSL2"

# Skip restore if .restore-skip file exists
if [ -f "${__WSL2_DIR}/.restore-skip" ]; then
	echo -e "${__CLR_INFO}[INFO]${__CLR_RESET}Restore skipped: ${__WSL2_DIR}/.restore-skip exists"
	exit 0
fi

__LAST_DUMP="$(find "${__WSL2_DIR}/Backups/" -name '*_devtool-wsl2.tar' -maxdepth 1 -type f \
	-printf '%T@ %f\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-)"

if [ -n "${__LAST_DUMP}" ]; then
	echo "# =============================================================================="
	echo "# devtool-wsl2 restore tools"
	echo "#"
	echo "# WSL2 Directory: \"${__WSL2_DIR}\""
	echo "# Last Dump     : \"${__LAST_DUMP}\""
	echo "# =============================================================================="

	pv "${__WSL2_DIR}/Backups/${__LAST_DUMP}" | tar xf - -C "${HOME}" --strip-components=2
	date '+%Y-%m-%dT%H%M%S%z' > "${HOME}/.dwsl2-restore.lock"
	echo -e "${__CLR_INFO}[INFO]${__CLR_RESET}Restore completed: ${__LAST_DUMP}"
fi
