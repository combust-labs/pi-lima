# pi-lima

A [Lima](https://github.com/lima-vm/lima) + [krunkit](https://github.com/slp/krunkit) VM on macOS that hosts the [pi coding agent](https://github.com/earendil-works/pi) on Apple Silicon — with a real, hardware-accelerated Vulkan GPU passed through to the guest.

This repository is a spiritual successor to [`combust-labs/pi-docker`](https://github.com/combust-labs/pi-docker). Where `pi-docker` builds a Docker image that runs `pi`, `pi-lima` builds a Linux VM image that runs `pi` natively, with a working GPU stack. The natural next step is to collapse the two into a single **`pi-runner`** that can launch `pi` either in Docker or directly on the host shell — at which point `ppi`, the helper from `pi-docker`, becomes the canonical entry point in either world.

## Target platform

* macOS on Apple Silicon (`aarch64`).
* VM backend: `krunkit` (libkrun / `hypervisor.framework`).
* Nested virtualization is enabled inside the guest so KVM is available to the VM.
* The guest itself is `aarch64` Ubuntu 24.04.

## GPU: Vulkan over VirtIO on Apple Silicon

GPU acceleration in a VM on Apple Silicon is rare, and most people assume it isn't possible. It is — and this project makes it work.

> ⚠️ **The Mesa patches in `bin/image/pi-builder.yaml` are critical and must not be modified.**
>
> The two inline patches `mesa-23.3.6.krunkit-16k.patch` and
> `mesa-25.0.7.krunkit-16k.patch` are the reason Vulkan enumerates inside
> the VM at all. They are derived from slp's downstream Mesa patch at
> [`gitlab.freedesktop.org/slp/mesa/-/commit/761ef1ec`](https://gitlab.freedesktop.org/slp/mesa/-/commit/761ef1ec5ff2aae1cc3dc8bbc22b3d06ef04b549),
> and they implement a specific, non-trivial workaround that is documented
> below. **Do not edit, "clean up", or drop them.** See
> [How the GPU was unlocked](#how-the-gpu-was-unlocked) for the full
> provenance.

The stack, end to end:

```
┌──────────────────────────────────────────────────────────────────┐
│  Ubuntu 24.04 aarch64 guest                                      │
│                                                                  │
│   pi coding agent + Chromium, llamma.cpp, Ollama, ...            │
│                    │                                             │
│                    ▼                                             │
│   Vulkan apps   ──▶   Venus ICD (Mesa, virtio-vulkan only)       │
│                    │                                             │
└────────────────────│─────────────────────────────────────────────┘
                     │  virtio-gpu / Venus protocol over shared mem
                     ▼
┌──────────────────────────────────────────────────────────────────┐
│  macOS host (Apple Silicon)                                      │
│                                                                  │
│   krunkit / libkrun  ──▶  virglrenderer  ──▶  Metal              │
│                                       (slp/krun tap, pinned)     │
└──────────────────────────────────────────────────────────────────┘
```

Concretely:

* **krunkit + libkrun** exposes a `virtio-gpu` device to the guest with a
  Venus-compatible transport. Memory regions for Vulkan buffers and command
  buffers are shared via `RESOURCE_CREATE_BLOB` ioctls.
* The **guest Mesa** is built from source at a pinned version (default
  `25.0.7`, with `23.3.6` kept as a fallback inside `pi-builder.yaml`) and
  configured with `-Dvulkan-drivers=virtio` only — no GL, no GLX, no EGL,
  no Gallium drivers. It is installed to `/opt/mesa/venus`, and
  `VK_DRIVER_FILES` is pointed at the resulting `virtio_icd.aarch64.json`.
* The **host-side renderer** is `virglrenderer`, translating the guest's
  Vulkan commands into Metal. This must be the version pinned by the
  `slp/krun` Homebrew tap — the upstream Homebrew `virglrenderer 1.3.0` is
  incompatible with krunkit on Apple Silicon and produces
  `ERROR_INITIALIZATION_FAILED` from `vkEnumeratePhysicalDevices`. The
  `fix-virglrenderer.sh` script exists for exactly this reason.
* A custom patch (`mesa-$VERSION.krunkit-16k.patch`) is applied to the Mesa
  sources before building. It aligns virtio-vulkan memory allocations to
  **16 KiB** in four call sites — `vn_device_memory_alloc_simple`,
  `virtgpu_bo_create_from_device_memory`, `virtgpu_shmem_create`, and
  `vn_ring_get_layout`. **All four hunks are required** — without the
  `vn_ring.c` hunk the build gets past `vkCreateInstance` but then fails
  on device memory allocation. Without this alignment, krunkit's resource
  blob backend rejects the guest's allocations and the Vulkan stack fails
  to enumerate any physical devices, even though everything else looks
  correct. See [How the GPU was unlocked](#how-the-gpu-was-unlocked)
  below for the full provenance.

What this unlocks in practice:

* **Local LLM inference inside the VM is GPU-accelerated.** This is the main
  reason this setup exists. The agent in the VM can invoke local inference
  runtimes — `llama.cpp`, Ollama, vLLM, MLX, anything that talks to Metal on
  macOS — and they use the host GPU through the virtio-gpu passthrough. The
  point is to be able to test "computer + LLM" deployments end to end on
  macOS without leaving the host machine: the agent is fully isolated in a
  VM, GPU compute is available to it, and any local-inference runtime the
  agent wants to use just works.
* **Any Vulkan application works.** The guest is not a server-class VM; it
  is a desktop-class VM with a real GPU. This is uncommon on Apple Silicon
  and is one of the main reasons this project exists separately from
  `pi-docker`.
* **Chromium inside the VM is hardware-accelerated** as a side effect.
  Useful for front-end work — building or testing apps that themselves use
  GPU paths (WebGPU, Skia/Vulkan, canvas-heavy UIs). The
  `combust-labs/pi-ext-read-website` extension also benefits from this when
  rendering heavy sites.
* **Nested virtualization is enabled**, so KVM is also available inside the
  guest. This is unusual for a krunkit VM and means the guest can itself
  host additional VMs or run workloads that need `/dev/kvm`.

This combination — krunkit + a custom Venus Mesa + a 16 KiB-aligned blob
transport + the `slp/krun` pinned `virglrenderer` — is a fragile recipe, but
it is the recipe that makes Vulkan work in a Linux VM on Apple Silicon.

### How the GPU was unlocked

The GPU stack in this repo did not come out of nowhere. It exists because
of two specific upstream reports and the workaround that came out of
diagnosing them. The chain is small enough to read in order:

1. **[`libkrun/krunkit#102`](https://github.com/libkrun/krunkit/issues/102) — *Vulkan broken in krunkit VM with newer Mesa*.**
   A user reports that `vulkaninfo` fails inside a krunkit VM with
   `vkCreateInstance failed with ERROR_OUT_OF_HOST_MEMORY` once the guest
   Mesa is newer than ~23.x. Stock Debian / Ubuntu / Fedora guest images
   break. The issue is closed by switching to a container image whose Mesa
   carries a downstream patch — i.e. the workaround exists, but the root
   cause is not yet pinned down.
2. **[Comment on `#102`](https://github.com/libkrun/krunkit/issues/102#issuecomment-5228832380) by
   [`@stewartjeacocke`](https://github.com/stewartjeacocke):**
   *"I believe the root cause of this may be
   [`libkrun/krunkit#114`](https://github.com/libkrun/krunkit/issues/114)."*
   This is the pointer that links the symptom in `#102` to the diagnosis in
   `#114`.
3. **[`libkrun/krunkit#114`](https://github.com/libkrun/krunkit/issues/114) — *`hv_vm_map` requires 16 KiB-aligned blob sizes on Apple Silicon*.**
   The actual root cause. `libkrun`'s
   `#[cfg(target_os = "macos")] resource_map_blob` passes the guest-requested
   blob size unchanged into `hv_vm_map`, but Apple's hypervisor framework
   requires page-aligned arguments and the VM page size on Apple Silicon is
   16384 bytes. The guest's 4 KiB pages get `PAGE_ALIGN`-ed but not
   16 KiB-aligned, so the mapping fails with `EINVAL`. Mesa's Venus ring
   shmem is 131268 bytes, gets rounded by the guest kernel to 135168
   (33 × 4 KiB, 8.25 × 16 KiB), and that exact size is the one that fails.
   Venus reports the failure upward as `VK_ERROR_OUT_OF_HOST_MEMORY`, and
   the Vulkan loader aborts `vkCreateInstance`.
4. **The fix in Mesa: slp's downstream patch
   [`761ef1ec`](https://gitlab.freedesktop.org/slp/mesa/-/commit/761ef1ec5ff2aae1cc3dc8bbc22b3d06ef04b549).**
   Force 16 KiB alignment on every Venus allocation, in four call sites:
   `vn_device_memory_alloc_simple`,
   `virtgpu_bo_create_from_device_memory`, `virtgpu_shmem_create`, and
   `vn_ring_get_layout`. The author of `#114` notes explicitly that **all
   four hunks are needed** — the `vn_ring.c` one alone gets past
   `vkCreateInstance`, then device memory allocation fails instead. The
   two patches embedded in `pi-builder.yaml` are derived directly from
   this commit.

These two issues, together, are what unlocked the GPU. Without them there
is no patched Mesa, and without a patched Mesa there is no Vulkan in a
krunkit VM.

The full investigation — including the failed attempts, the moment of
discovery, and the upstream fix that has now landed in Mesa MR #44783
and libkrun PR #886 — is written up at
[*GPU in a Linux VM on Apple Silicon*](https://gruchalski.com/posts/2026-10-30-gpu-in-a-vm-on-apple-silicon/).

### The upstream fix that should eventually replace the patches

The hardcoded 16384 alignment is a workaround for an undocumented host-side requirement. The proper fix is two-sided.

On the guest side, **[Mesa MR #44783 *"venus: honor the virtio-gpu blob alignment"*](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/44783)**, merged 2026-09-28 by Matthew Periut, queries the kernel for `VIRTGPU_PARAM_BLOB_ALIGNMENT` (a parameter added in Linux 7.2) and rounds blob sizes up to whatever the kernel reports. On hosts without that parameter it falls back to 1, i.e. no rounding — so the change is a no-op on every other platform.

On the host side, **[libkrun PR #886 *"virtio/gpu: offer VIRTIO_GPU_F_BLOB_ALIGNMENT"*](https://github.com/libkrun/libkrun/pull/886)**, merged 2026-10-01 by `willie`, advertises the parameter with `sysconf(_SC_PAGESIZE)` — 16384 on Apple Silicon — so the guest kernel has a meaningful value to forward to Mesa. With both halves in place, the guest Mesa learns the right alignment from the host instead of hardcoding it.

The conditions for "no patch needed":

* a Mesa release that contains MR #44783 — on Mesa `main`, tagged for 26.3, **no released stable Mesa has it yet** as of 2026-10-30;
* a libkrun release that contains PR #886 — also on `main`, **no released stable libkrun has it yet** as of 2026-10-30;
* a Linux 7.2+ guest kernel;
* the default Ubuntu 24.04 HWE kernel at 7.2+. At the time of writing it is `24.04.5 LTS (HWE)` with kernel version `7.0`.

**Rollout order matters.** Once libkrun PR #886 ships in a stable libkrun release, any guest with a 7.2 kernel and a Mesa older than the first release with MR #44783 will hit the same `VK_ERROR_OUT_OF_HOST_MEMORY` we have been diagnosing — see **[limina issue #22](https://github.com/liminavm/limina/issues/22)** for a real report (Debian forky/sid, Mesa 26.1.6, kernel 7.2.9). Until Mesa 26.3 ships in a stable release that Ubuntu picks up, **the patches must stay**, even if you have updated everything else.

## Repository layout

```
pi-lima/
├── .gitignore
├── LICENSE                              Apache License 2.0
├── README.md                            this file
└── bin/
    ├── host/macos/                      macOS host bootstrap
    │   ├── install-lima.sh
    │   ├── install-krunkit.sh
    │   ├── install-qemu.sh
    │   ├── uninstall-krunkit.sh
    │   ├── cleanup.sh
    │   └── fix-virglrenderer.sh
    ├── image/                           image builder
    │   ├── pi-builder.sh
    │   ├── pi-builder.yaml
    │   └── pi-lima.bootstrap/           mounted into the builder VM (see below)
    │       └── custom/                  user-overridable bootstrap data (gitignored)
    └── runner/                          day-to-day VM launcher
        ├── pi-agent-runner.sh
        └── pi-agent-runner.yaml
```

### Bootstrap directory (`bin/image/pi-lima.bootstrap/`)

`pi-builder.sh` mounts this directory into the builder VM at build time.
Today it contains only `custom/`, which is gitignored — drop files there
to extend or override what the image build picks up during provisioning
without having to edit `pi-builder.yaml`. A `.gitkeep` keeps the empty
directory tracked.

## How it works

The pipeline has two phases.

### 1. Build a base image

`bin/image/pi-builder.sh` drives `bin/image/pi-builder.yaml` through Lima to
produce a single, ready-to-use qcow2:

1. `limactl start` the builder template, mounting `bin/image/pi-lima.bootstrap`
   into the VM. The `custom/` subdirectory under it is gitignored — drop
   files there to extend or override what the image build picks up
   during provisioning without editing `pi-builder.yaml`.
2. Provisioning runs in stages:
   * **System packages:** build tools (meson, ninja, cmake, bison, flex,
     pkg-config), Python 3 with `mako` / `pyyaml`, Chromium (or its snap
     symlink), `vulkan-tools`, `mesa-utils`, `libdrm-dev`, plus `curl`,
     `git`, `jq`, `socat`, `iproute2`, `iptables`, `net-tools`, and
     `apt-get build-dep mesa`.
   * **Tunables:** large inotify / file-handle limits,
     `vm.max_map_count=262144`, `ip_forward=1`.
   * **Custom Mesa build:** see [GPU](#gpu-vulkan-over-virtio-on-apple-silicon)
     above. The Mesa source is cloned from
     `https://gitlab.freedesktop.org/mesa/mesa.git` at the tag pinned by
     `MESA_VERSION`, the krunkit-specific 16 KiB alignment patch is
     applied, and the build is configured with `-Dvulkan-drivers=virtio`
     only and installed to `/opt/mesa/venus`. `VK_DRIVER_FILES` is set in
     `/etc/environment.d/99-lima-pi.conf` and in `~/.mesa-env`.
   * **User-level setup:** Node.js via NVM (version pinned through
     `PI_NODE_VERSION`), `pi` cloned from
     `https://github.com/earendil-works/pi.git` at tag `v1.3.0` and built
     with `npm`. A custom CLI wrapper is installed that disables
     `process.emitWarning`, sets `process.title = "pi"`, and wires
     `undici`'s `EnvHttpProxyAgent` as the global HTTP dispatcher so HTTP
     proxies are honored automatically.
   * The `combust-labs/pi-ext-read-website` extension is installed. This
     is the extension that makes GPU-accelerated Chromium matter.
   * `~/.local/share/pi/agent/settings.json` is pre-seeded with
     `defaultProjectTrust: "always"`.
3. The VM is cleaned up (cloud-init reset, SSH host keys removed,
   machine-id truncated, apt cache wiped, journal vacuumed to 1s, sync).
4. The VM is stopped, and its disk is exported with
   `qemu-img convert -O qcow2 -o compression_type=zstd -c` into
   `${HOME}/.local/share/pi-builder-images/ubuntu-24.04-arm64-pi-agent-base.qcow2`,
   validated with `qemu-img check`, and checksummed with SHA-256.
5. The temporary builder VM is deleted.

### 2. Launch a per-project VM from the image

`bin/runner/pi-agent-runner.sh` reuses the prebuilt qcow2:

1. If no copy exists yet for the current working directory, the base qcow2
   is copied to a per-directory sibling (keyed on `sha256sum "$(pwd)"`) so
   each project gets an isolated, mutable image.
2. `limactl create` is invoked with the image location injected via
   `--set='.images[0].location = "file://..."'`.
3. `limactl start` mounts `~/.config/git`, `~/.pi/agent`, and `$(pwd)` with
   `--mount-writable`, and `--mount-inotify=false` to avoid krunkit inotify
   storms.
4. The script drops into `limactl shell` against the running VM.

### Mount-aware shell setup

On VM startup, a block appended to `~/.bashrc` walks `findmnt` output for
`virtiofs` mounts and:

* Symlinks a host-mounted working directory into `/code` when
  `HARNESS_WORK_DIR` is set.
* For `~/.config/git` mounts, **copies** the host's `git/config` and any
  referenced includeIf files into the VM's `~/.config/git`. Symlinking them
  causes `Too many open files` errors after long commit activity through
  the shared mount, so files are copied selectively instead.
* For `~/.pi/agent` mounts, symlinks `models.json`, `prompts/`, and
  `sessions/` into `${PI_CODING_AGENT_DIR}` (defaults to
  `~/.local/share/pi/agent`) so the VM uses the host's models and sessions.

## Prerequisites

On a fresh macOS host, install the required components:

```sh
./bin/host/macos/install-krunkit.sh
./bin/host/macos/install-lima.sh
```

If you intend to build the image from scratch:

```sh
./bin/host/macos/install-qemu.sh
```

## Usage

### Build the base image

```sh
./bin/image/pi-builder.sh
```

The build reads these environment variables (all optional):

| Variable | Default | Purpose |
|---|---|---|
| `PI_BUILDER_NAME` | `pi-builder` | Lima instance name for the temporary builder |
| `PI_BUILDER_TEMPLATE` | `bin/image/pi-builder.yaml` | Lima YAML template |
| `PI_BUILDER_IMAGE_DIR` | `~/.local/share/pi-builder-images` | Output directory for the qcow2 |
| `PI_BUILDER_OUTPUT_IMAGE_NAME` | `ubuntu-24.04-arm64-pi-agent-base` | Output qcow2 base name |
| `PI_BUILDER_LIMA_CONFIG_ROOT` | `~/.lima` | Lima state directory |
| `PI_BUILDER_LIMA_BOOTSTRAP_TIMEOUT` | `10m` | Lima bootstrap timeout |

Mesa and Node versions are configured inside `pi-builder.yaml` under
`param` (`MESA_VERSION`, `NODE_VERSION`, `PI_REPOSITORY`, `PI_VERSION`).

### Run a VM from the image

```sh
./bin/runner/pi-agent-runner.sh
```

Environment variables / flags accepted by the runner:

| Flag / variable | Default | Purpose |
|---|---|---|
| `--name` / `PI_VM_NAME` | `pi-agent` | Lima VM instance name |
| `--image-dir` / `PI_BUILDER_IMAGE_DIR` | `~/.local/share/pi-builder-images` | Where to look for the qcow2 |
| `--image-name` / `PI_BUILDER_OUTPUT_IMAGE_NAME` | `ubuntu-24.04-arm64-pi-agent-base` | Image base name (without `.qcow2`) |
| `--lima-config-root` / `PI_BUILDER_LIMA_CONFIG_ROOT` | `~/.lima` | Lima state directory |
| `--resources-cpu` | `8` | vCPUs for the runtime VM |
| `--resources-disk` | `100` | Disk size (GiB) for the runtime VM |
| `--resources-mem` | `32` | Memory (GiB) for the runtime VM |

## `ppi` in the VM

The helper `ppi` from [`combust-labs/pi-docker`](https://github.com/combust-labs/pi-docker)
is the canonical entry point for invoking `pi`. It transparently supports
both interactive CLI and HTTP-RPC server modes and handles all of the
session, model, and configuration mounts.

The plan is for `pi-docker` to become **`pi-runner`** — a single host-side
helper that launches `pi` either inside a Docker container or directly on
the host shell, picking whichever target is appropriate. When that lands,
installing `pi-runner` inside the Lima VM (or having `pi-lima` build it in)
makes `ppi` available in the VM exactly the way it is available on a host
that runs `pi` in Docker today:

```sh
# inside the VM, with pi-runner installed:
ppi --model gpt-4o "Summarize this project"
ppi --mode rpc   # HTTP-RPC server, default port 3000
```

Until `pi-runner` exists, `pi` itself is on `PATH` (symlinked to
`/usr/local/bin/pi`) and the `pi-ext-read-website` extension is preinstalled.

## Troubleshooting

### Vulkan in the VM fails with `ERROR_INITIALIZATION_FAILED`

If `vulkaninfo --summary` reports:

```
ERROR: [Loader Message] Code 0 : setup_loader_term_phys_devs:  Failed to detect any valid GPUs in the current config
ERROR at ./vulkaninfo/./vulkaninfo.h:245:vkEnumeratePhysicalDevices failed with ERROR_INITIALIZATION_FAILED
```

you almost certainly have the wrong `virglrenderer`. If
`brew info virglrenderer` shows `1.3.0`, it is incompatible with krunkit
on Apple Silicon. Recover with:

```sh
./bin/host/macos/fix-virglrenderer.sh
```

### General slp/krun issues

When in doubt, fully uninstall and reinstall the krunkit stack:

```sh
./bin/host/macos/uninstall-krunkit.sh
./bin/host/macos/install-krunkit.sh
```

### Deep-clean the krunkit Homebrew state

`cleanup.sh` removes the krunkit-related Homebrew state in one shot: the binaries (`krunkit`, `libkrun`, `libkrunfw`, `virglrenderer`), both taps (`libkrun/krun`, `slp/krun`), the per-formula trusts on both taps, and the brew cache. Use it whenever a stale tap or trust is blocking a fresh `install-krunkit.sh` run, or when a full reset of the krunkit stack is needed.

For a full reset:

```sh
./bin/host/macos/cleanup.sh
./bin/host/macos/install-krunkit.sh
```

### "Too many open files" during `git commit` in the VM

This is the bug the `~/.bashrc` mount-handler works around. If you still
see it, the VM has not picked up the updated `~/.bashrc`, or the mount for
`~/.config/git` was not provided to `limactl start`.

## Sandboxing inside the VM

There is no additional security boundary inside the VM. By design.

`pi` is given full agency over the VM. The instruction set passed to it
includes "you own this VM, do whatever you need to finish the task, install
any software required." That instruction requires `pi` to be a sudoer and
to have unrestricted filesystem access inside the VM — including the
regular user's home, `/etc`, `/usr`, and everything else. The trust boundary
is the VM itself: outside it, `pi` cannot reach the host.

Several approaches to internal sandboxing were considered and rejected:

* **Separate user + strict Unix permissions** (`chmod 0700` on the regular
  home, `chattr +i` on sensitive files). Defeated by sudo — `pi`-as-root
  can `chmod`, `chown`, and `chattr -i` past any permission-based barrier.
* **Bubblewrap (`bwrap`)** for namespace-based filesystem isolation.
  The boundary is kernel-enforced (mount namespace), but it contradicts the
  "do whatever you need" instruction. If `pi` legitimately needs to modify
  a file outside the sandbox, the sandbox becomes an obstacle to the task,
  not a security control.
* **Landlock (Linux ≥ 5.13)** for self-imposed filesystem policy. Same
  fundamental issue as bwrap: it limits what `pi` can do, which conflicts
  with full agency.
* **AppArmor / SELinux** mandatory access control. Same fundamental issue.
* **systemd-nspawn, or a second container inside the VM.** Possible, but
  the complexity outweighs the benefit when `pi` is fully trusted inside
  the VM.
* **A second VM.** This is the only configuration that provides real
  additional isolation. If that level of isolation is ever needed, run two
  VMs — one for `pi`, one for everything else. That is a deployment model,
  not a sandboxing question.

The remaining hygiene concerns — `pi` polluting the user's shell history,
sourcing the user's init files from non-interactive subprocesses, or writing
to the regular user's home — can be addressed at two layers, independently
of each other:

* **Wrapper-level cleanup (light).** The `pi` wrapper itself
  (`/opt/pi-agent/packages/coding-agent/dist/pi`) is a shell script that
  unsets `HISTFILE`, `BASH_ENV`, `ENV`, and `PROMPT_COMMAND` before
  exec'ing the Node.js entry point. This stops `pi`'s subprocess shells
  from polluting `~/.bash_history`, from sourcing the user's
  `~/.bash_profile`, and from running the user's prompt hooks. No separate
  user, no extra provisioning — the change lives in one wrapper file
  inside `pi-builder.yaml`.
* **Separate sudoer user (heavier).** A distinct UID with its own
  `$HOME` solves pollution more comprehensively (dotfiles, agent state,
  tool caches, NVM directory, and so on) but requires user provisioning
  and adds cognitive overhead. Worth doing only if the wrapper-level
  cleanup proves insufficient.

Either way, these are housekeeping, not security boundaries.

## Known issues / things to fix

* `bin/runner/pi-agent-runner.yaml` hardcodes the image location to
  `file:///Users/radek/dev/radekg/pi-lima/ubuntu-24.04-lima-arm64.qcow2`,
  which is the original author's path. The runner overrides this at create
  time via `--set`, but the YAML in the repo is misleading.
* `ppi` is not yet installed in the VM. It will land when `pi-docker`
  becomes `pi-runner`.

## License

Apache License 2.0. See [LICENSE](./LICENSE).
