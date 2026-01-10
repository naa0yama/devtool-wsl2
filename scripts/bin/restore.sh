#!/usr/bin/env bash
set -euo pipefail

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

# shellcheck disable=SC2016 # $env:USERPROFILE is intentionally passed to PowerShell
__WSL2_DIR="$(wslpath -u "$(powershell.exe -c '$env:USERPROFILE' | tr -d '\r')")/Documents/WSL2"

# Skip restore if .restore-skip file exists
if [ -f "${__WSL2_DIR}/.restore-skip" ]; then
	log_info "Restore skipped: ${__WSL2_DIR}/.restore-skip exists"
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
	log_info "Restore completed: ${__LAST_DUMP}"
fi
