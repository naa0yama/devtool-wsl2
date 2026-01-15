#!/usr/bin/env bash

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

# Env
USERPROFILE="$(wslpath -u $(powershell.exe -c '$env:USERPROFILE' | tr -d '\r'))"

# Copy "~/.gitconfig" from Windows if it doesn't exist
# File
if [ ! -f "${HOME}/.gitconfig" -a -f "${USERPROFILE}/.gitconfig" ]; then
	log_info "Copy .gitconfig from Windows"
	cp -v "${USERPROFILE}/.gitconfig" "${HOME}"
	chmod 0644 "${HOME}/.gitconfig"
fi
if [ ! -f "${HOME}/.gitignore_global" -a -f "${USERPROFILE}/.gitignore_global" ]; then
	log_info "Copy .gitignore_global from Windows"
	cp -v "${USERPROFILE}/.gitignore_global" "${HOME}"
	chmod 0644 "${HOME}/.gitignore_global"
fi

# Directory
if [ ! -d "${HOME}/.gitconfig.d" -a -d "${USERPROFILE}/.gitconfig.d" ]; then
	log_info "Copy .gitconfig.d from Windows"
	cp -Rv "${USERPROFILE}/.gitconfig.d" "${HOME}"
	find "${HOME}/.gitconfig.d" -type d -exec chmod 0755 {} \;
	find "${HOME}/.gitconfig.d" -type f -exec chmod 0644 {} \;
fi
