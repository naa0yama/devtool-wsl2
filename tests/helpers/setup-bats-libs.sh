#!/usr/bin/env bash
# Clone bats-support and bats-assert into tests/bats/test_helper/
# Run once before executing the test suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${SCRIPT_DIR}/../bats/test_helper"

clone_or_update() {
	local repo="$1"
	local dest="$2"
	if [[ -d "${dest}/.git" ]]; then
		echo "Updating ${dest}"
		git -C "${dest}" pull --ff-only
	else
		echo "Cloning ${repo} → ${dest}"
		git clone --depth=1 "https://github.com/${repo}.git" "${dest}"
	fi
}

clone_or_update "bats-core/bats-support" "${TARGET_DIR}/bats-support"
clone_or_update "bats-core/bats-assert"  "${TARGET_DIR}/bats-assert"

echo "bats libs ready in ${TARGET_DIR}"
