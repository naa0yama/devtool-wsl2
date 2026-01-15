#!/usr/bin/env bash

eval "$(mise activate bash)"

# This requires bash-completion to be installed
if [ ! -f "${HOME}/.local/share/bash-completion/completions/mise" ]; then
	mkdir -p "${HOME}/.local/share/bash-completion/completions/"
	mise completion bash --include-bash-completion-lib > "${HOME}/.local/share/bash-completion/completions/mise"
fi
