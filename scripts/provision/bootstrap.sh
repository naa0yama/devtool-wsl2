#!/usr/bin/env bash
set -euo pipefail

# Logger
log_info() { echo -e "\033[0;36m[INFO]\033[0m $*" >&2; }
log_warn() { echo -e "\033[0;33m[WARN]\033[0m $*" >&2; }
log_erro() { echo -e "\033[0;31m[ERRO]\033[0m $*" >&2; }

# --- Seam overrides (for bats testing) ---
DEVTOOL_PROC_VERSION_FILE="${DEVTOOL_PROC_VERSION_FILE:-/proc/version}"
DEVTOOL_DOCKERENV_FILE="${DEVTOOL_DOCKERENV_FILE:-/.dockerenv}"
DEVTOOL_CGROUP_FILE="${DEVTOOL_CGROUP_FILE:-/proc/1/cgroup}"

# --- Environment detection ---
is_wsl2() {
	local proc_version_file="${DEVTOOL_PROC_VERSION_FILE}"
	[[ -f "${proc_version_file}" ]] || return 1
	grep -qiE "microsoft|WSL" "${proc_version_file}"
}

is_container() {
	local dockerenv_file="${DEVTOOL_DOCKERENV_FILE}"
	local cgroup_file="${DEVTOOL_CGROUP_FILE}"
	[[ -f "${dockerenv_file}" ]] && return 0
	[[ -f "${cgroup_file}" ]] && grep -qE "docker|containerd|lxc" "${cgroup_file}" && return 0
	return 1
}

is_vm() {
	if command -v systemd-detect-virt > /dev/null 2>&1; then
		local virt
		virt="$(systemd-detect-virt 2>/dev/null || true)"
		case "${virt}" in
			kvm|qemu|vmware|xen|hyperv|parallels) return 0 ;;
		esac
	fi
	local dmi_file="/sys/class/dmi/id/product_name"
	if [[ -f "${dmi_file}" ]]; then
		grep -qiE "kvm|qemu|vmware|virtualbox" "${dmi_file}" && return 0
	fi
	return 1
}

detect_env() {
	if is_container; then
		echo "container"
	elif is_wsl2; then
		echo "wsl2"
	elif is_vm; then
		echo "vm"
	else
		echo "bare"
	fi
}

_stage0_provision_fetch() {
	log_info "Fetching provision asset to ${DEVTOOL_PROVISION_DIR}"
	mkdir -p "${DEVTOOL_PROVISION_DIR}"
	curl -fsSL "${PROVISION_ASSET_URL}" | tar -xz --strip-components=1 -C "${DEVTOOL_PROVISION_DIR}"
	chmod -R a+rX "${DEVTOOL_PROVISION_DIR}"
}

main() {
	# --- Resolve DEVTOOL_ENV (auto-detect if unset) ---
	: "${DEVTOOL_ENV:=$(detect_env)}"
	log_info "detected DEVTOOL_ENV=${DEVTOOL_ENV}"

	case "${DEVTOOL_ENV}" in
		wsl2|vm|container|bare) ;;
		*)
			log_erro "DEVTOOL_ENV='${DEVTOOL_ENV}' is invalid. Use: wsl2|vm|container|bare"
			exit 1
			;;
	esac

	# --- Optional environment variables ---
	DEVTOOL_TAG="${DEVTOOL_TAG:-main}"
	DEVTOOL_REPO="${DEVTOOL_REPO:-naa0yama/devtool-wsl2}"
	DRY_RUN="${DRY_RUN:-}"
	DEVTOOL_SKIP_FETCH="${DEVTOOL_SKIP_FETCH:-}"
	PROVISION_ROOT="${PROVISION_ROOT:-}"

	DEFAULT_USERNAME="${DEFAULT_USERNAME:-user}"

	if [[ -n "${PROVISION_ROOT}" ]]; then
		# Test seam: use specified root directly, skip fetch
		src="${PROVISION_ROOT}"
		log_info "PROVISION_ROOT override: ${src}"
	else
		if [[ "${EUID}" -eq 0 ]]; then
			DEVTOOL_CACHE="${DEVTOOL_CACHE:-/var/cache/devtool}"
		else
			DEVTOOL_CACHE="${DEVTOOL_CACHE:-${HOME}/.cache/devtool}"
		fi

		tarball="${DEVTOOL_CACHE}/devtool-${DEVTOOL_TAG}.tar.gz"
		extract_dir="${DEVTOOL_CACHE}/src"
		src="${extract_dir}"

		mkdir -p "${DEVTOOL_CACHE}" "${extract_dir}"

		if [[ -z "${DEVTOOL_SKIP_FETCH}" ]]; then
			read -ra CURL_OPTS <<< "${CURL_OPTS:--sfSL --retry 3 --retry-delay 2 --retry-connrefused}"
			url="https://github.com/${DEVTOOL_REPO}/archive/${DEVTOOL_TAG}.tar.gz"
			log_info "Fetching tarball: ${url}"

			if [[ -n "${DRY_RUN}" ]]; then
				log_info "[DRY_RUN] curl ${CURL_OPTS[*]} -o ${tarball} ${url}"
				log_info "[DRY_RUN] tar -xzf ${tarball} --strip-components=1 -C ${extract_dir}"
			else
				# Compute sha256 of existing tarball before fetch to detect changes
				existing_sha=""
				if [[ -f "${tarball}" ]]; then
					existing_sha="$(sha256sum "${tarball}" | awk '{print $1}')"
				fi

				curl "${CURL_OPTS[@]}" -o "${tarball}.tmp" "${url}"

				new_sha="$(sha256sum "${tarball}.tmp" | awk '{print $1}')"

				if [[ "${existing_sha}" == "${new_sha}" && -d "${extract_dir}/scripts/provision" ]]; then
					log_info "Tarball unchanged (sha256=${new_sha}), skipping extraction"
					rm -f "${tarball}.tmp"
				else
					mv "${tarball}.tmp" "${tarball}"
					log_info "Extracting tarball (sha256=${new_sha})"
					rm -rf "${extract_dir:?}"/*
					tar -xzf "${tarball}" --strip-components=1 -C "${extract_dir}"
				fi
			fi
		else
			log_info "DEVTOOL_SKIP_FETCH=1: using existing ${src}"
			if [[ -z "${DRY_RUN}" && ! -d "${src}/scripts/provision" ]]; then
				log_erro "DEVTOOL_SKIP_FETCH=1 but ${src}/scripts/provision does not exist"
				exit 1
			fi
		fi
	fi

	provision_root="${src}/scripts/provision"

	# --- system layer ---
	log_info "=== system layer (DEVTOOL_ENV=${DEVTOOL_ENV}) ==="

	_run_as_root() {
		if [[ -n "${DRY_RUN}" ]]; then
			log_info "[DRY_RUN] (root) $*"
		elif [[ "${EUID}" -eq 0 ]]; then
			"$@"
		elif command -v sudo > /dev/null 2>&1; then
			sudo "$@"
		else
			log_erro "system layer requires root; sudo not available"
			exit 1
		fi
	}

	while IFS= read -r -d '' script; do
		log_info "system: ${script}"
		_run_as_root env "DEVTOOL_ENV=${DEVTOOL_ENV}" "DRY_RUN=${DRY_RUN}" bash "${script}"
	done < <(find "${provision_root}/system" -maxdepth 1 -name '*.sh' -print0 | sort -z)

	# --- user layer ---
	log_info "=== user layer (uid=${DEFAULT_USERNAME}) ==="

	_run_as_user() {
		if [[ -n "${DRY_RUN}" ]]; then
			log_info "[DRY_RUN] (${DEFAULT_USERNAME}) $*"
		elif [[ "${EUID}" -eq 0 ]]; then
			su - "${DEFAULT_USERNAME}" -c "DEVTOOL_ENV='${DEVTOOL_ENV}' DRY_RUN='${DRY_RUN}' bash '$1'"
		else
			env "DEVTOOL_ENV=${DEVTOOL_ENV}" "DRY_RUN=${DRY_RUN}" bash "$1"
		fi
	}

	while IFS= read -r -d '' script; do
		log_info "user: ${script}"
		_run_as_user "${script}"
	done < <(find "${provision_root}/user" -maxdepth 1 -name '*.sh' -print0 | sort -z)

	log_info "bootstrap complete (DEVTOOL_ENV=${DEVTOOL_ENV}, DEVTOOL_TAG=${DEVTOOL_TAG})"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	DEVTOOL_BOOTSTRAP_SELF="${DEVTOOL_BOOTSTRAP_SELF:-/tmp/devtool-bootstrap.sh}"
	UPSTREAM="${UPSTREAM:-https://raw.githubusercontent.com/naa0yama/devtool-wsl2/main}"
	PROVISION_ASSET_URL="${PROVISION_ASSET_URL:-https://github.com/naa0yama/devtool-wsl2/releases/latest/download/devtool-provision.tar.gz}"
	DEVTOOL_PROVISION_DIR="${DEVTOOL_PROVISION_DIR:-/tmp/devtool-provision}"

	if [[ "${BASH_SOURCE[0]}" != "${DEVTOOL_BOOTSTRAP_SELF}" && ! -f "${DEVTOOL_BOOTSTRAP_SELF}" ]]; then
		log_info "Self-downloading bootstrap to ${DEVTOOL_BOOTSTRAP_SELF}"
		curl -fsSL "${UPSTREAM}/scripts/provision/bootstrap.sh" -o "${DEVTOOL_BOOTSTRAP_SELF}"
		chmod +x "${DEVTOOL_BOOTSTRAP_SELF}"
		exec bash "${DEVTOOL_BOOTSTRAP_SELF}" "$@"
	fi

	_stage0_provision_fetch
	main "$@"
fi
