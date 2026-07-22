#!/usr/bin/env bats
# Tests for scripts/image/series-map.sh (series → cloud image url mapping)

load '../helpers/common'

SERIES_MAP_SH="${BATS_TEST_DIRNAME}/../../scripts/image/series-map.sh"

_source_series_map() {
	# shellcheck source=/dev/null
	source "${SERIES_MAP_SH}"
}

@test "series_to_url_returns_noble_url_when_series_is_noble" {
	_source_series_map
	run series_to_url "noble"
	assert_success
	assert_output "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
}

@test "series_to_url_returns_resolute_url_when_series_is_resolute" {
	_source_series_map
	run series_to_url "resolute"
	assert_success
	assert_output "https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img"
}
