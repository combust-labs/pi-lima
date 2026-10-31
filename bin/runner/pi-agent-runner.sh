#!/bin/bash

set -euo pipefail
base="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

image_dir=${PI_BUILDER_IMAGE_DIR:-"${HOME}/.local/share/pi-builder-images"}
image_name=${PI_BUILDER_OUTPUT_IMAGE_NAME:-"ubuntu-24.04-arm64-pi-agent-base"}
lima_config_root=${PI_BUILDER_LIMA_CONFIG_ROOT:-"${HOME}/.lima"}
resources_cpu=8
resources_disk=100
resources_mem=32
vm_name=${PI_VM_NAME:-"pi-agent"}

while (( "$#" )); do
    case "${1}" in
        --image-dir)
            image_dir="${2}"
            shift 2
            ;;
        --image-name)
            image_name="${2}"
            shift 2
            ;;
        --lima-config-root)
            lima_config_root="${2}"
            shift 2
            ;;
        --resources-cpu)
            resources_cpu="${2}"
            shift 2
            ;;
        --resources-disk)
            resources_disk="${2}"
            shift 2
            ;;
        --resources-mem)
            resources_mem="${2}"
            shift 2
            ;;
        --name)
            vm_name="${2}"
            shift 2
            ;;
        -*)
            echo "Error: Unsupported flag ${1}" >&2
            exit 1
            ;;
    esac
done

[ -z "${image_name}" ] && echo >&2 "missing argument: --image-name" && exit 1
[ -z "${image_dir}" ] && echo >&2 "missing argument: --image-dir" && exit 1
[ -z "${vm_name}" ] && echo >&2 "missing argument: --vm-name" && exit 1

vm_root_image="${image_dir}/${image_name}.qcow2"
[ ! -f "${vm_root_image}" ] && echo >&2 "VM root filesystem not found at '${vm_root_image}'" && exit 1

vm_image="${vm_root_image}.$(sha256 -s "$(pwd)")"
[ ! -f "${vm_image}" ] && cp -v "${vm_root_image}" "${vm_image}"

if [ ! -d "${lima_config_root}/${vm_name}" ]; then
    echo >&2 "[vm: ${vm_name}] Creating using '${vm_root_image}' image..."
    limactl create \
        --cpus "${resources_cpu}" \
        --disk "${resources_disk}" \
        --memory "${resources_mem}" \
        --name "${vm_name}" \
        --set='.images[0].location = "file://'${vm_image}'"' \
        "${base}/pi-agent-runner.yaml" \
        --yes
fi

echo >&2 "[vm: ${vm_name}] Starting..."
# limactl start "${vm_name}"

limactl start \
    --mount-only "${HOME}/.config/git" \
    --mount-only "${HOME}/.pi/agent" \
    --mount-only "$(pwd)" \
    --mount-writable \
    --mount-inotify=false \
    "${vm_name}"
limactl shell "${vm_name}"

# echo >&2 "[vm: ${vm_name}] Running, to get the shell: limactl shell ${vm_name}."
