#!/bin/bash

# ================= Configuration =================
VM_MEM="32G"
VM_SMP="32"
# Enable AVX512, which is critical for PyTorch performance
CPU_MODEL="host,+avx2,+avx512f,+avx512dq,+avx512cd,+avx512bw,+avx512vl"

# --- Management network (for SSH) ---
SSH_PORT=10022

# --- High-performance data network (TAP) ---
TAP_IF="tdx-tap0"
NET_QUEUES=16
MAC_ADDR_PERF="52:54:00:12:34:57"

# Basic configuration
PROCESS_NAME=td
LOGFILE='/tmp/tdx-guest-td.log'
# ===========================================

cleanup() {
    rm -f /tmp/tdx-guest-*.log &> /dev/null
    rm -f /tmp/tdx-demo-*-monitor.sock &> /dev/null
    PID_TD=$(cat /tmp/tdx-demo-td-pid.pid 2> /dev/null)
    [ ! -z "$PID_TD" ] && echo "Cleanup, kill TD with PID: ${PID_TD}" && kill -TERM ${PID_TD} &> /dev/null
    
    # Clean up the TAP device
    sudo ip link set dev $TAP_IF down 2>/dev/null
    sudo ip tuntap del dev $TAP_IF mode tap 2>/dev/null
    sleep 3
}

cleanup
if [ "$1" = "clean" ]; then
    exit 0
fi

if [ "$EUID" -ne 0 ]; then
  echo "Error: sudo privileges are required to create the high-performance TAP network interface."
  exit 1
fi

UBUNTU_VERSION=$(lsb_release -rs)
#TD_IMG=${TD_IMG:-${PWD}/image/tdx-guest-ubuntu-${UBUNTU_VERSION}-generic.qcow2}
TD_IMG=${TD_IMG:-${PWD}/image/tdx-guest-ubuntu-24.04-generic.qcow2}
TDVF_FIRMWARE=/usr/share/ovmf/OVMF.fd

# 1. Set up the high-performance TAP network interface (data channel)
echo "Setting up high-performance TAP interface: $TAP_IF"
ip tuntap add dev $TAP_IF mode tap user $SUDO_USER multi_queue
ip link set dev $TAP_IF up
ip addr add 192.168.100.1/24 dev $TAP_IF 2>/dev/null

# 2. Memory optimization settings
MEM_ARGS="-object memory-backend-memfd,id=ram1,size=${VM_MEM},share=on,prealloc=on"

# 3. CPU binding (Numactl)
PREFIX_CMD=""
if command -v numactl &> /dev/null; then
    PREFIX_CMD="numactl --cpunodebind=0 --membind=0"
    echo "Using numactl for CPU pinning..."
fi

echo "Starting TDX VM (Dual NIC Mode)..."

$PREFIX_CMD qemu-system-x86_64 -D $LOGFILE \
       -accel kvm \
       -m ${VM_MEM} -smp ${VM_SMP} \
       -name ${PROCESS_NAME},process=${PROCESS_NAME},debug-threads=on \
       -cpu ${CPU_MODEL} \
       ${MEM_ARGS} \
       -machine q35,kernel_irqchip=split,confidential-guest-support=tdx,hpet=off,memory-backend=ram1 \
       -object '{"qom-type":"tdx-guest","id":"tdx","quote-generation-socket":{"type": "vsock", "cid":"2","port":"4050"}}' \
       -bios ${TDVF_FIRMWARE} \
       -nographic -daemonize \
       -nodefaults \
       \
       `# --- NIC 1: Management interface (slower, but convenient for SSH) ---` \
       -device virtio-net-pci,netdev=nic_mgmt \
       -netdev user,id=nic_mgmt,hostfwd=tcp::${SSH_PORT}-:22 \
       \
       `# --- NIC 2: Data interface (high-speed TAP with multiple queues) ---` \
       -netdev tap,id=nic_perf,ifname=${TAP_IF},script=no,downscript=no,vhost=on,queues=${NET_QUEUES} \
       -device virtio-net-pci,netdev=nic_perf,mac=${MAC_ADDR_PERF},mq=on,vectors=$((NET_QUEUES * 2 + 2)) \
       \
       `# Disk I/O thread optimization` \
       -object iothread,id=io1 \
       -device virtio-blk-pci,drive=virtio-disk0,iothread=io1 \
       -drive file=${TD_IMG},if=none,id=virtio-disk0,cache=none,aio=native \
       \
       -device vhost-vsock-pci,guest-cid=4 \
       -pidfile /tmp/tdx-demo-td-pid.pid

ret=$?
if [ $ret -ne 0 ]; then
    echo "Error: Failed to create TD VM. Check $LOGFILE."
    exit $ret
fi

echo "------------------------------------------------------------------"
echo "TD VM Started!"
echo "1. Management login (using the original method):"
echo "   ssh -p ${SSH_PORT} root@localhost"
echo ""
echo "2. Enable high-performance networking (run after logging in):"
echo "   ip addr add 192.168.100.2/24 dev enp0s2 (or enp*s*)"
echo "   ip link set dev enp0s2 up"
echo "   ethtool -L enp0s2 combined 16"
echo "------------------------------------------------------------------"
