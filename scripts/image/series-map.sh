#!/usr/bin/env bash
set -euo pipefail

series_to_url() {
	local s="$1"
	echo "https://cloud-images.ubuntu.com/${s}/current/${s}-server-cloudimg-amd64.img"
}
