#!/usr/bin/env bash

# Restore dump
if [ ! -f "${HOME}/.dwsl2-restore.lock" ]; then
	/opt/devtool/bin/restore.sh
fi

# Setup
if [ ! -f "${HOME}/.cache/devtool-setup.lock" ]; then
	/opt/devtool/bin/setup.sh
fi
