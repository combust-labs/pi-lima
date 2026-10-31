#!/bin/bash

set -euo pipefail
base="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

builder_name=${PI_BUILDER_NAME:-"pi-builder"}
builder_template=${PI_BUILDER_TEMPLATE:-"${base}/pi-builder.yaml"}
image_dir=${PI_BUILDER_IMAGE_DIR:-"${HOME}/.local/share/pi-builder-images"}
image_name=${PI_BUILDER_OUTPUT_IMAGE_NAME:-"ubuntu-24.04-arm64-pi-agent-base"}
lima_config_root=${PI_BUILDER_LIMA_CONFIG_ROOT:-"${HOME}/.lima"}
lima_bootstrap_timeout=${PI_BUILDER_LIMA_BOOTSTRAP_TIMEOUT:-"10m"}

while (( "$#" )); do
    case "${1}" in
        --builder-name)
            builder_name="${2}"
            shift 2
            ;;
        --builder-template)
            builder_template="${2}"
            shift 2
            ;;
        --image-dir)
            image_dir="${2}"
            shift 2
            ;;
        --image-name)
            image_name="${2}"
            shift 2
            ;;
        --lima-bootstrap-timeout)
            lima_bootstrap_timeout="${2}"
            shift 2
            ;;
        --lima-config-root)
            lima_config_root="${2}"
            shift 2
            ;;
        -*)
            echo "Error: Unsupported flag ${1}" >&2
            exit 1
            ;;
    esac
done

[ -z "${builder_name}" ] && echo >&2 "missing argument: --builder-name" && exit 1
[ -z "${builder_template}" ] && echo >&2 "missing argument: --builder-template" && exit 1
[ ! -f "${builder_template}" ] && echo >&2 "missing file from argument: --builder-template target not found" && exit 1
[ -z "${image_name}" ] && echo >&2 "missing argument: --image-name" && exit 1
[ -z "${image_dir}" ] && echo >&2 "missing argument: --image-dir" && exit 1
[ -z "${lima_config_root}" ] && echo >&2 "missing argument: --lima-config-root" && exit 1


mkdir -p "${image_dir}"

echo >&2 "[${builder_name}]: Creating the builder virtual machine..."

limactl start "${builder_template}" \
    --mount-only "${base}/pi-lima.bootstrap" \
    --name "${builder_name}" \
    --timeout "${lima_bootstrap_timeout}" \
    --progress --yes

echo >&2 "[${builder_name}]: Clean up the VM to make the image smaller..."

limactl shell "${builder_name}" -- sudo bash -lc '
    set -eux

    #
    # Reset cloud-init so a new VM can initialize independently.
    #
    cloud-init clean --logs || true

    #
    # Remove SSH host keys.
    #
    # Ubuntu recreates them on first boot.
    #
    rm -f /etc/ssh/ssh_host_*

    #
    # Clear temporary/log data.
    #
    rm -rf /tmp/*
    rm -rf /var/tmp/*

    journalctl --rotate || true
    journalctl --vacuum-time=1s || true

    #
    # Clear machine identity.
    #
    truncate -s 0 /etc/machine-id
    rm -f /var/lib/dbus/machine-id

    #
    # Clean apt caches to keep image smaller.
    #
    apt-get autoremove -y
    apt-get clean
    rm -rf /var/lib/apt/lists/*

    #
    # Make sure everything has reached disk.
    #
    sync
'

echo >&2 "[${builder_name}]: Stopping the VM after cleanup..."

limactl stop "${builder_name}"

export builder_root_disk="${lima_config_root}/${builder_name}/disk"
export output_image="${image_dir}/${image_name}.qcow2"

echo >&2 "[${builder_name}]: Disk located at ${builder_root_disk}..."
stat "${builder_root_disk}"

qemu-img info "${builder_root_disk}"

echo >&2 "[${builder_name}]: Export standalone qcow2..."

qemu-img convert \
    -p \
    -O qcow2 \
    -o compression_type=zstd \
    -c \
    "${builder_root_disk}" \
    "${output_image}"

qemu-img check "${output_image}"
qemu-img info "${output_image}"

echo >&2 "[${builder_name}]: Generate a checksum..."
shasum -a 256 "${output_image}" > "${output_image}.sha256"

echo >&2 "[${builder_name}]: Removing builder VM..."
limactl delete "${builder_name}"

echo >&2 "[${builder_name}]: Done."