#!/bin/bash
set -Eeuo pipefail

function cleanup() {
    trap - SIGINT SIGTERM ERR EXIT
    if [ -n "${tmpdir+x}" ]; then
        rm -rf "$tmpdir"
        log "🚽 Deleted temporary working directory $tmpdir"
    fi
}

trap cleanup SIGINT SIGTERM ERR EXIT

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd -P)
[[ ! -x "$(command -v date)" ]] && echo "💥 date command not found." && exit 1
today=$(date +"%Y-%m-%d")

function log() {
    echo >&2 -e "[$(date +"%Y-%m-%d %H:%M:%S")] ${1-}"
}

function die() {
    local msg=$1
    local code=${2-1}
    log "$msg"
    exit "$code"
}

usage() {
    cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-a] [-e] [-u user-data-file] [-m meta-data-file] [-k] [-c] [-r] [-s source-iso-file] [-d destination-iso-file]

💁 This script will create fully-automated Ubuntu 20.04 Focal Fossa installation media.

Available options:

-h, --help              Print this help and exit
-v, --verbose           Print script debug info
-a, --all-in-one        Bake user-data and meta-data into the generated ISO. By default you will
                        need to boot systems with a CIDATA volume attached containing your
                        autoinstall user-data and meta-data files.
                        For more information see: https://ubuntu.com/server/docs/install/autoinstall-quickstart
-e, --use-hwe-kernel    Force the generated ISO to boot using the hardware enablement (HWE) kernel. Not supported
                        by early Ubuntu 20.04 release ISOs.
-u, --user-data         Path to user-data file. Required if using -a
-m, --meta-data         Path to meta-data file. Will be an empty file if not specified and using -a
-k, --no-verify         Disable GPG verification of the source ISO file. By default SHA256SUMS-$today and
                        SHA256SUMS-$today.gpg in ${script_dir} will be used to verify the authenticity and integrity
                        of the source ISO file. If they are not present the latest daily SHA256SUMS will be
                        downloaded and saved in ${script_dir}. The Ubuntu signing key will be downloaded and
                        saved in a new keyring in ${script_dir}
-c, --no-md5            Disable MD5 checksum on boot
-r, --use-release-iso   Use the current release ISO instead of the daily ISO. The file will be used if it already
                        exists.
-s, --source            Source ISO file. By default the latest daily ISO for Ubuntu 20.04 will be downloaded
                        and saved as ${script_dir}/ubuntu-original-$today.iso
                        That file will be used by default if it already exists.
-d, --destination       Destination ISO file. By default ${script_dir}/ubuntu-autoinstall-$today.iso will be
                        created, overwriting any existing file.
EOF
    exit
}

function parse_params() {
    user_data_file=''
    meta_data_file=''
    download_url="https://cdimage.ubuntu.com/ubuntu-server/focal/daily-live/current"
    download_iso="focal-live-server-amd64.iso"
    original_iso="ubuntu-original-$today.iso"
    source_iso="${script_dir}/${original_iso}"
    destination_iso="${script_dir}/ubuntu-autoinstall-$today.iso"
    sha_suffix="${today}"
    gpg_verify=1
    all_in_one=0
    use_hwe_kernel=0
    md5_checksum=1
    use_release_iso=0

    while :; do
        case "${1-}" in
        -h | --help) usage ;;
        -v | --verbose) set -x ;;
        -a | --all-in-one) all_in_one=1 ;;
        -e | --use-hwe-kernel) use_hwe_kernel=1 ;;
        -c | --no-md5) md5_checksum=0 ;;
        -k | --no-verify) gpg_verify=0 ;;
        -r | --use-release-iso) use_release_iso=1 ;;
        -u | --user-data)
            user_data_file="${2-}"
            shift
            ;;
        -s | --source)
            source_iso="${2-}"
            shift
            ;;
        -d | --destination)
            destination_iso="${2-}"
            shift
            ;;
        -m | --meta-data)
            meta_data_file="${2-}"
            shift
            ;;
        -?*) die "Unknown option: $1" ;;
        *) break ;;
        esac
        shift
    done

    log "👶 Starting up..."

    if [ ${all_in_one} -ne 0 ]; then
        [[ -z "${user_data_file}" ]] && die "💥 user-data file was not specified."
        [[ ! -f "$user_data_file" ]] && die "💥 user-data file could not be found."
        [[ -n "${meta_data_file}" ]] && [[ ! -f "$meta_data_file" ]] && die "💥 meta-data file could not be found."
    fi

    if [ "${source_iso}" != "${script_dir}/${original_iso}" ]; then
        [[ ! -f "${source_iso}" ]] && die "💥 Source ISO file could not be found."
    fi

    if [ "${use_release_iso}" -eq 1 ]; then
        download_url="https://releases.ubuntu.com/focal"
        log "🔎 Checking for current release..."
        download_iso=$(curl -sSL "${download_url}" | grep -oP 'ubuntu-20\.04\.\d*-live-server-amd64\.iso' | head -n 1)
        original_iso="${download_iso}"
        source_iso="${script_dir}/${download_iso}"
        current_release=$(echo "${download_iso}" | cut -f2 -d-)
        sha_suffix="${current_release}"
        log "💿 Current release is ${current_release}"
    fi

    destination_iso=$(realpath "${destination_iso}")
    source_iso=$(realpath "${source_iso}")

    return 0
}

ubuntu_gpg_key_id="843938DF228D22F7B3742BC0D94AA3F0EFE21092"

parse_params "$@"

tmpdir=$(mktemp -d)

if [[ ! "$tmpdir" || ! -d "$tmpdir" ]]; then
    die "💥 Could not create temporary working directory."
else
    log "📁 Created temporary working directory $tmpdir"
fi

log "🔎 Checking for required utilities..."
[[ ! -x "$(command -v xorriso)" ]] && die "💥 xorriso is not installed. On Ubuntu, install  the 'xorriso' package."
[[ ! -x "$(command -v sed)" ]] && die "💥 sed is not installed. On Ubuntu, install the 'sed' package."
[[ ! -x "$(command -v curl)" ]] && die "💥 curl is not installed. On Ubuntu, install the 'curl' package."
[[ ! -x "$(command -v gpg)" ]] && die "💥 gpg is not installed. On Ubuntu, install the 'gpg' package."
[[ ! -f "/usr/lib/ISOLINUX/isohdpfx.bin" ]] && die "💥 isolinux is not installed. On Ubuntu, install the 'isolinux' package."
log "👍 All required utilities are installed."

if [ ! -f "${source_iso}" ]; then
    log "🌎 Downloading ISO image for Ubuntu 20.04 Focal Fossa..."
    curl -NsSL "${download_url}/${download_iso}" -o "${source_iso}"
    log "👍 Downloaded and saved to ${source_iso}"
else
    log "☑️ Using existing ${source_iso} file."
    if [ ${gpg_verify} -eq 1 ]; then
        if [ "${source_iso}" != "${script_dir}/${original_iso}" ]; then
            log "⚠️ Automatic GPG verification is enabled. If the source ISO file is not the latest daily or release image, verification will fail!"
        fi
    fi
fi

if [ ${gpg_verify} -eq 1 ]; then
    if [ ! -f "${script_dir}/SHA256SUMS-${sha_suffix}" ]; then
        log "🌎 Downloading SHA256SUMS & SHA256SUMS.gpg files..."
        curl -NsSL "${download_url}/SHA256SUMS" -o "${script_dir}/SHA256SUMS-${sha_suffix}"
        curl -NsSL "${download_url}/SHA256SUMS.gpg" -o "${script_dir}/SHA256SUMS-${sha_suffix}.gpg"
    else
        log "☑️ Using existing SHA256SUMS-${sha_suffix} & SHA256SUMS-${sha_suffix}.gpg files."
    fi

    if [ ! -f "${script_dir}/${ubuntu_gpg_key_id}.keyring" ]; then
        log "🌎 Downloading and saving Ubuntu signing key..."
        gpg -q --no-default-keyring --keyring "${script_dir}/${ubuntu_gpg_key_id}.keyring" --keyserver keyserver.ubuntu.com --recv-keys "${ubuntu_gpg_key_id}"
    else
        log "☑️ Using existing Ubuntu signing key."
    fi

    log "🔎 Verifying source ISO file with SHA256SUMS-${sha_suffix}..."
    gpgv --keyring "${script_dir}/${ubuntu_gpg_key_id}.keyring" "${script_dir}/SHA256SUMS-${sha_suffix}.gpg" "${script_dir}/SHA256SUMS-${sha_suffix}" || die "💥 SHA256SUMS verification failed."

    if [ ! -f "${script_dir}/SHA256SUMS-${sha_suffix}" ]; then
        log "💥 SHA256SUMS-${sha_suffix} file could not be found or verified. Cannot continue."
        exit 1
    fi

    if ! grep -q "$(sha256sum <"${source_iso}" | awk '{print $1}')" "${script_dir}/SHA256SUMS-${sha_suffix}"; then
        log "💥 SHA256SUMS checksum for ${source_iso} is incorrect."
        exit 1
    fi
fi

log "🛠️ Mounting source ISO and preparing output ISO..."

if ! mountpoint -q "${tmpdir}/iso"; then
    mkdir -p "${tmpdir}/iso"
    mount -o loop "${source_iso}" "${tmpdir}/iso"
fi

if ! mountpoint -q "${tmpdir}/iso"; then
    die "💥 Failed to mount source ISO."
fi

if [ -d "${tmpdir}/iso/EFI/BOOT" ]; then
    cp -r "${tmpdir}/iso/EFI" "${tmpdir}/iso/EFI.tmp"
    mv "${tmpdir}/iso/EFI" "${tmpdir}/iso/EFI/BOOT"
fi

if [ ${use_hwe_kernel} -eq 1 ]; then
    log "🛠️ Preparing HWE kernel files..."
    mkdir -p "${tmpdir}/iso/casper"
    cp -v "${tmpdir}/iso/casper/initrd" "${tmpdir}/iso/casper/initrd.orig"
    cp -v "${tmpdir}/iso/casper/vmlinuz" "${tmpdir}/iso/casper/vmlinuz.orig"
    sed -i '/^initrd.*\.gz$/d' "${tmpdir}/iso/isolinux/txt.cfg"
fi

if [ ${all_in_one} -eq 1 ]; then
    log "🔧 Adding user-data and meta-data to the ISO..."
    mkdir -p "${tmpdir}/iso/nocloud"
    cp -v "${user_data_file}" "${tmpdir}/iso/nocloud/user-data"
    if [[ -n "${meta_data_file}" ]]; then
        cp -v "${meta_data_file}" "${tmpdir}/iso/nocloud/meta-data"
    else
        echo "instance-id: $(uuidgen)" > "${tmpdir}/iso/nocloud/meta-data"
    fi
fi

log "🔧 Generating new ISO image..."
mkisofs -r -V "Custom Ubuntu ISO" -cache-inodes -J -l -no-emul-boot -boot-load-size 4 -boot-info-table -o "${destination_iso}" "${tmpdir}/iso"

log "🗑️ Cleaning up..."
umount "${tmpdir}/iso"
rmdir "${tmpdir}/iso"

log "✅ Successfully created new Ubuntu ISO with autoinstall support: ${destination_iso}"
