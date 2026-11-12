# TDX VM Requirements and Setup

## Requirements

- An Intel TDX-capable host with TDX enabled in firmware and supported by the Linux kernel and KVM.
- A TDX-capable `qemu-system-x86_64` and compatible TDVF firmware at `/usr/share/ovmf/OVMF.fd`.
- Host utilities: `bash`, `ip` (`iproute2`), `lsb_release` (`lsb-release`), `sudo`, and standard core utilities. `numactl` is optional.
- TAP, multiqueue TAP, vhost-net, and vhost-vsock network support.
- 32 GiB of available memory, capacity for 32 vCPUs, and an unused TCP port `10022`.
- A compatible quote-generation service on host vsock CID `2`, port `4050`, if TDX quote generation is required.

## Setup

1. Create a `tdxvm` directory and place `TESCOrun_td.sh` inside it.
2. Create an `image` directory inside `tdxvm`. Download the TESCO guest image, extract it, and place `tdx-guest-ubuntu-24.04-generic.qcow2` in `tdxvm/image/`.
3. From the `tdxvm` directory, run `sudo bash ./TESCOrun_td.sh`. Follow the script’s output to log in to the TDX VM and configure its data network interface.
