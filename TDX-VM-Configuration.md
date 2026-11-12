


## Host configuration, TDX Remote Attestation and Key Exchange

This section documents the system environment, software dependencies, platform prerequisites, execution workflow, and benchmark results for our Intel TDXremote attestation and key exchange implementation. It provides the technical specifications required to reproduce hardware-backed attestation on a TDX virtual machine.

### 1. Architecture Overview

During initialization, the workload inside the TDX guest generates a hardware-authenticated `TDREPORT` bound to session handshake parameters and requests a signed TDX Quote from the host Quote Generation Service (QGS). The remote verifier validates the Quote and platform collateral via the Intel DCAP Quote Verification Library (QVL) before completing ephemeral key establishment.

```text
TDX Guest Application
  ├─ 64 B REPORTDATA (SHA-512 over domain, nonce, and ephemeral public keys)
  ├─ Linux TDX guest driver (/dev/tdx_guest & configfs TSM report interface)
  └─ Quote request
       │  Guest-host transport (vhost-vsock)
       ▼
Host QGS (qgsd) ──► Intel DCAP QPL/QCNL ──► Host PCCS ──► Intel PCS
                                                            │
                                                PCK certificates & collateral
       ┌────────────────────────────────────────────────────┘
       ▼
Verifier: Quote + collateral ──► Intel DCAP QVL ──► Key derivation & mutual HMAC
```

### 2. Environment and Dependencies

The implementation was validated in the following hardware and software environment:
#### Host Environment
* **Hardware & OS**: Intel TDX-capable server running Ubuntu 24.04.2 LTS (kernel `6.8.0-1028-intel`).
* **Virtualization & Guest-Host Transport**: QEMU configured with a Quote Generation Socket over `vhost-vsock` (`CID 2`, `port 4050`). In our testbed, `socat` bridges host vsock `CID 2:4050` to the QGS Unix domain socket (`/var/run/tdx-qgs/qgs.socket`).
* **Quote Generation Service (QGS)**: `tdx-qgs`, `libsgx-tdx-logic`, and `libsgx-dcap-default-qpl` (`1.27.101.1-noble1`), managed via `qgsd.service` and listening on `/var/run/tdx-qgs/qgs.socket`.
* **Provisioning Certificate Caching Service (PCCS)**: `pccs.service` (`1.26.100.1-noble1`), listening on `127.0.0.1:8081` (HTTPS) with an SQLite backend. Version `1.26.100.1` is used for compatibility with the host's Node.js 18 runtime.
* **QCNL & TLS Configuration**: Configured in `/etc/sgx_default_qcnl.conf`. The isolated evaluation setup uses a local self-signed HTTPS certificate for PCCS with `use_secure_cert=false`; production deployments require a CA-signed certificate matching the host SAN with `use_secure_cert=true`.
* **Platform Registration**: Intel `PCK ID Retrieval Tool` and an Intel PCS API key configured in the PCCS `ApiKey` field (subscribed from https://api.portal.trustedservices.intel.com/provisioning-certification).
##### TDX VM Configuration
* **Compute & ISA Extensions**: 32 vCPUs (`-smp 32`) and explicit AVX2/AVX-512 extensions (`+avx2`, `+avx512f`, `+avx512dq`, `+avx512cd`, `+avx512bw`, `+avx512vl`) enabled to accelerate PyTorch workloads.
* **Memory & NUMA Pinning**: 32 GB pre-allocated memory, both vCPUs and memory are pinned to NUMA node 0 via `numactl` (`--cpunodebind=0 --membind=0`) to eliminate cross-NUMA latency.
* **Machine & Firmware**: QEMU/KVM `q35` machine (`confidential-guest-support=tdx`, `kernel_irqchip=split`, `hpet=off`) booted via TDVF (`/usr/share/ovmf/OVMF.fd`), equipped with a `vhost-vsock-pci` device (`guest-cid=4`) for host-guest vsock communication.
* **Dual-NIC Network Architecture**:
  * *Management Network*: User-mode `virtio-net-pci` interface forwarding host TCP port `10022` to guest port `22` for out-of-band SSH access.
  * *High-Performance Data Network*: Multi-queue `virtio-net-pci` interface backed by a host TAP device (`tdx-tap0`, `192.168.100.1/24` to guest `192.168.100.2/24`) with `16` TX/RX queues (`mq=on`).

#### TDX Guest Environment
* **OS & Kernel**: Ubuntu 24.04.2 LTS (kernel `6.8.0-58-generic`) running inside a hardware-backed TDX TD.
* **Kernel Interfaces**: `/dev/tdx_guest` and `configfs` TSM report interface at `/sys/kernel/config/tsm/report` with `provider` reporting `tdx_guest`.
* **Runtime & Cryptographic Dependencies**: Python `3.12.3` with `cryptography` `41.0.7` (providing X25519, HKDF-SHA256, and HMAC-SHA256).

#### Verifier Environment
* **Verification Libraries**: Intel DCAP QVL (`libsgx-dcap-quote-verify`, `1.27.101.1-noble1`) and QPL/QCNL. In our benchmark environment, the official Intel `.deb` packages are extracted into an isolated workspace directory and loaded via `LD_LIBRARY_PATH` without modifying system-wide packages.

### 3. Platform Prerequisites for Reproduction

TDX virtualization alone does not guarantee that a guest VM can obtain remotely verifiable Quotes. Reproducing the full pipeline on another TDX VM depends on the following platform conditions:

1. **Guest Driver Exposure**: The guest kernel and cloud/hypervisor image must expose `/dev/tdx_guest` and/or `/sys/kernel/config/tsm/report` (`tdx_guest` provider).
2. **Host QGS Availability and Transport**: The host administrator or cloud provider must run QE/QGS with access to SGX/TDX quoting hardware and expose a guest-host communication channel (the specific vsock CID, port, or hypervisor transport varies across platforms).
3. **Platform Registration and Collateral Access**: The host PCCS (or the verifier's QPL) must have network access to Intel PCS with a valid PCS API key, and the physical server's PCK material must be registered with Intel PCS.

### 4. Configuration and Execution Workflow

#### 4.1 Guest Interface Verification and Local Report Baseline
On the TDX guest, confirm the presence of the device node and `configfs` TSM provider:

```bash
uname -a
ls -l /dev/tdx_guest
mount | grep configfs
ls -l /sys/kernel/config/tsm/report
cat /sys/kernel/config/tsm/report/provider
```

Issuing a `GET_REPORT0` ioctl to `/dev/tdx_guest` with 64 B of input `REPORTDATA` produces a `1,024 B` local `TDREPORT`, where byte offset `[128:192]` matches the supplied 64 B input. This confirms hardware TDX guest capability independently of host Quote services.

#### 4.2 Host QGS and PCCS Setup
1. **QGS & Transport**: Start `qgsd.service` on the host, verify `/var/run/tdx-qgs/qgs.socket`, and establish the transport bridge between the QEMU guest Quote socket (e.g., vsock `CID 2`, `port 4050`) and `qgs.socket`.
2. **PCCS Initialization**: Install a Node.js-compatible PCCS package, bind it to `127.0.0.1:8081`, configure the Intel PCS `ApiKey` alongside PCCS `User` and `Admin` tokens, and allow initial SQLite schema migration to complete on startup.
3. **Multi-Socket Platform Registration**: If automatic multi-package registration is not enabled in BIOS, run the Intel `PCK ID Retrieval Tool` on the host to generate the Platform Manifest CSV, convert it to the PCCS JSON payload format, and register it via the PCCS User Token at `POST https://127.0.0.1:8081/sgx/certification/v4/platforms` (expecting `HTTP 200` / `Operation successful.`). Point `/etc/sgx_default_qcnl.conf` to the local PCCS endpoint.

#### 4.3 Hardware Quote Generation in the Guest
Once the host pipeline is active, the guest requests a signed Quote via `configfs` TSM:
1. Create a uniquely named temporary directory under `/sys/kernel/config/tsm/report/`.
2. Write the 64 B `REPORTDATA` payload to `inblob`.
3. Read the resulting binary Quote from `outblob` with a bounded timeout, and remove the temporary entry in a `finally` block.

On the reference platform, this returns a `5,247 B` **TDX Quote v4** (`attestation key type = 2`, `TEE type = 0x81`) whose embedded `REPORTDATA` field matches the 64 B input. Generated Quotes and their corresponding `REPORTDATA` inputs are stored as paired artifacts.

#### 4.4 Quote Verification via Intel DCAP QVL
The verifier loads `libsgx-dcap-quote-verify`, retrieves the matching verification collateral (via configured PCCS or Intel PCS), and invokes the QVL verification API. The verification step records the QVL return code, cryptographic signature status, collateral expiration check, `REPORTDATA` equality check, and platform TCB status. On our reference testbed, QVL validates authentic Quotes, rejects modified Quotes, and reports a platform TCB status of `OUT_OF_DATE`; our benchmark configuration permits this status to measure steady-state execution, whereas production deployments should enforce up-to-date TCB requirements and verify target `MRTD`/`RTMR` measurements.

#### 4.5 Attestation-Bound Key Exchange
Session key establishment binds an ephemeral X25519 key exchange to the TDX Quote:
1. **Challenge**: The verifier generates a 32 B random `nonce` and an X25519 key pair, sending `nonce` and `verifier_pub` to the guest.
2. **Quote Binding**: The guest generates an ephemeral X25519 key pair, computes the transcript digest `REPORTDATA = SHA-512(domain || nonce || verifier_pub || guest_pub)`, obtains a hardware TDX Quote over `REPORTDATA`, and returns `guest_pub` along with the Quote.
3. **Verification & Key Confirmation**: The verifier first validates the Quote signature, collateral, policy, and `REPORTDATA` binding via DCAP QVL. Upon successful verification, both parties compute the X25519 shared secret, derive session keys via `HKDF-SHA256` using the handshake transcript as the salt, and exchange role-separated `HMAC-SHA256` tags for mutual confirmation. 

### 5. Reference Benchmarks

#### Component Microbenchmarks
Measured directly on the reference TDX guest and host:
* **Local `TDREPORT` generation (`GET_REPORT0` ioctl)**: `~6 µs` median (30 warmup / 500 measurement iterations.
* **End-to-end `TDX Quote` generation (guest TSM to host QGS)**: `~1,024 ms` median.
* **Steady-state `DCAP QVL` verification (with cached collateral)**: `~13.73 ms` median.

#### End-to-End Protocol Performance
Protocol benchmarks were evaluated between two threads over TCP loopback inside the guest (`10 warmup / 100 runs`), as well as under an application-layer network model injecting `400 Mbps` bidirectional serialization delay and `50 ms` latency (`5 warmup / 50 runs`). Reported byte counts reflect bidirectional application-layer payloads (including the `5,247 B` Quote) and exclude TCP/IP headers.

| Protocol Mode                                                 | LAN Median Latency | WAN Median Latency | Communication |
| :------------------------------------------------------------ | -----------------: | -----------------: | ------------: |
| **Attestation Only** (Quote generation, transfer, QVL verify) |        1,086.63 ms |        1,150.67 ms |       5,279 B |
| **X25519 Key Exchange Only**                                  |            1.57 ms |           78.72 ms |         160 B |
| **Attestation + Bound Key Exchange**                          |    **1,086.89 ms** |    **1,151.10 ms** |   **5,407 B** |

