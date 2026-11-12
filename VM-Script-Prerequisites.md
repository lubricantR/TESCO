# TDX VM Script Launching Prerequisites

- **TDX-capable host:** Intel TDX enabled in hardware and firmware, with a TDX-enabled Linux kernel and working KVM (`/dev/kvm`).
- **TDX-capable QEMU:** `qemu-system-x86_64` must support `tdx-guest` and the script's TDX machine options. A standard QEMU installation may not be sufficient.
- **TDVF firmware:** A TDX-compatible firmware image at `/usr/share/ovmf/OVMF.fd`, or an updated `TDVF_FIRMWARE` path in the script.
- **Guest disk image:** A TDX-compatible qcow2 image at `image/tdx-guest-ubuntu-<host-Ubuntu-version>-generic.qcow2`, or an absolute path supplied through `TD_IMG`.
- **Host utilities:** `bash`, `ip` (`iproute2`), `lsb_release` (`lsb-release`), `sudo`, and standard core utilities. `numactl` is optional.
- **Kernel networking support:** TAP, multiqueue TAP, vhost-net, and vhost-vsock support.
- **Permissions and resources:** Run with `sudo`; provide 32 GiB of available memory, capacity for 32 vCPUs, and an unused TCP port `10022`.
- **For TDX quote generation:** A compatible service must be available on host vsock CID `2`, port `4050`.