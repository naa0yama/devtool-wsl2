#!/usr/bin/env bash
# Shared bats helper loaded by all test files under tests/bats/
# BATS_TEST_DIRNAME resolves to the calling test file's directory (tests/bats/).

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

export PROVISION_ROOT="${BATS_TEST_DIRNAME}/../../scripts/provision"

setup() {
	:
}

teardown() {
	:
}
