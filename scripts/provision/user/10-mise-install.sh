#!/usr/bin/env bash
set -euxo pipefail

log_info() { echo -e "\033[0;36m[INFO]\033[0m $*"; }

if [[ -x "${HOME}/.local/bin/mise" ]]; then
	log_info "mise already installed at ${HOME}/.local/bin/mise, skipping"
	exit 0
fi

log_info "Installing mise via curl https://mise.run"
curl https://mise.run | sh

log_info "10-mise-install.sh complete"
