#!/usr/bin/env bash

eval "$(mise activate bash)"

# Defualt mise.toml install
if [ ! -f "${HOME}/.config/mise/config.toml" ]; then
	mkdir -p "${HOME}/.config/mise"
	curl -sfSL -o "${HOME}/.config/mise/config.toml" \
		https://raw.githubusercontent.com/naa0yama/devtool-wsl2/refs/heads/main/mise.toml
fi

# This requires bash-completion to be installed
if [ ! -f "${HOME}/.local/share/bash-completion/completions/mise" ]; then
	mise use -g usage
	mkdir -p "${HOME}/.local/share/bash-completion/completions/"
	mise completion bash --include-bash-completion-lib > "${HOME}/.local/share/bash-completion/completions/mise"
fi

# This requires fish-completion to be installed
if [ ! -f "${HOME}/.config/fish/completions/mise.fish" ]; then
	mise use -g usage
	mkdir -p "${HOME}/.config/fish/completions"
	mise completion fish > "${HOME}/.config/fish/completions/mise.fish"
fi
