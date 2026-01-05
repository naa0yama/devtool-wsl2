#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2016 # $env:USERPROFILE is intentionally passed to PowerShell
__WSL2_DIR="$(wslpath -u "$(powershell.exe -c '$env:USERPROFILE' | tr -d '\r')")/Documents/WSL2"
__LAST_DUMP="$(find "${__WSL2_DIR}/Backups/" -maxdepth 1 -type f -printf '%T@ %f\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-)"

if [ -n "${__LAST_DUMP}" ]; then
	echo "# =============================================================================="
	echo "# devtool-wsl2 restore tools"
	echo "#"
	echo "# WSL2 Directory: \"${__WSL2_DIR}\""
	echo "# Last Dump     : \"${__LAST_DUMP}\""
	echo "# =============================================================================="

	pv "${__WSL2_DIR}/Backups/${__LAST_DUMP}" | tar xf - -C "${HOME}" --strip-components=2
	date '+%Y-%m-%dT%H%M%S%z' > "${HOME}/.devtool-wsl2.lock"
	echo "Restore completed: ${__LAST_DUMP}"
fi
