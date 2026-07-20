#!/usr/bin/env bash
set -euo pipefail

series_to_url() {
	local s="$1"
	echo "https://cloud-images.ubuntu.com/${s}/current/${s}-server-cloudimg-amd64.img"
}

series_to_asset_name() {
	local s="$1"
	local sha="$2"
	echo "devtool-${s}-amd64-${sha}.qcow2"
}
