#!/bin/bash

# Per-process local network restriction script (limits bandwidth and latency and tracks traffic)
# Usage: limit_local_process.sh <bandwidth limit(Kbps)> <delay(ms)> -- <command>

# Default limits
BANDWIDTH_LIMIT=100        # Default: 100Kbps
DELAY=50                   # Default: 50ms
INTERFACE="lo"             # Local loopback interface
CGROUP_NAME="net_limit_lo"
MARK="0x1"                 # iptables mark value
CLASS_ID="1:100"           # tc class ID

# Traffic statistics variables
initial_packets=0
initial_bytes=0
final_packets=0
final_bytes=0

# Check privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root"
    exit 1
fi

# Check required commands
for cmd in tc iptables; do
    if ! command -v $cmd &> /dev/null; then
        echo "Error: The $cmd command must be installed"
        exit 1
    fi
done

# Format bytes into human-readable units
format_bytes() {
    local bytes=$1
    if [ $bytes -lt 1024 ]; then
        echo "${bytes} B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$(echo "scale=2; $bytes/1024" | bc) KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$(echo "scale=2; $bytes/1048576" | bc) MB"
    else
        echo "$(echo "scale=2; $bytes/1073741824" | bc) GB"
    fi
}

# Get marked traffic statistics
get_marked_stats() {
    # Get MARK rule counters from the OUTPUT chain
    iptables -t mangle -L OUTPUT -v -n -x | grep "MARK set $MARK" | awk '{print $1, $2}'
}

# Parse arguments
parse_args() {
    # Reset variables
    BANDWIDTH_LIMIT=""
    DELAY=""
    CMD_ARGS=()
    
    # Check whether any arguments were provided
    if [ $# -eq 0 ]; then
        echo "Error: No arguments provided"
        echo "Usage: $0 <bandwidth limit(Kbps)> <delay(ms)> -- <command>"
        exit 1
    fi
    
    # Parse arguments
    found_separator=0
    for arg in "$@"; do
        if [ "$arg" = "--" ]; then
            found_separator=1
            continue
        fi
        
        if [ $found_separator -eq 0 ]; then
            # Process bandwidth and delay arguments
            if [ -z "$BANDWIDTH_LIMIT" ]; then
                BANDWIDTH_LIMIT="$arg"
            elif [ -z "$DELAY" ]; then
                DELAY="$arg"
            else
                echo "Error: Too many arguments before --"
                echo "Usage: $0 <bandwidth limit(Kbps)> <delay(ms)> -- <command>"
                exit 1
            fi
        else
            # Process command arguments
            CMD_ARGS+=("$arg")
        fi
    done
    
    # Check whether the separator was found
    if [ $found_separator -eq 0 ]; then
        echo "Error: -- separator not found"
        echo "Usage: $0 <bandwidth limit(Kbps)> <delay(ms)> -- <command>"
        exit 1
    fi
    
    # Check whether a command was specified
    if [ ${#CMD_ARGS[@]} -eq 0 ]; then
        echo "Error: No command specified"
        echo "Usage: $0 <bandwidth limit(Kbps)> <delay(ms)> -- <command>"
        exit 1
    fi
}

parse_args "$@"

# Validate arguments
if [ -z "$BANDWIDTH_LIMIT" ]; then
    echo "Error: No bandwidth limit specified"
    exit 1
fi

if ! [[ "$BANDWIDTH_LIMIT" =~ ^[0-9]+$ ]]; then
    echo "Error: Bandwidth limit must be a number"
    exit 1
fi

if [ -z "$DELAY" ]; then
    echo "Error: No delay specified"
    exit 1
fi

if ! [[ "$DELAY" =~ ^[0-9]+$ ]]; then
    echo "Error: Delay must be a number"
    exit 1
fi

echo "Argument parsing complete:"
echo "Bandwidth limit: ${BANDWIDTH_LIMIT}Kbps"
echo "Delay: ${DELAY}ms"
echo "Command: ${CMD_ARGS[*]}"

# Enable forwarding on the lo interface
sysctl -w net.ipv4.conf.lo.forwarding=1
sysctl -w net.ipv4.conf.all.route_localnet=1

# Check cgroups version
CGROUP_VERSION=$(stat -fc %T /sys/fs/cgroup)
echo "Detected cgroups version: $CGROUP_VERSION"

# Create a cgroup (compatible with v1 and v2)
if [ "$CGROUP_VERSION" = "cgroup2fs" ]; then
    # Use cgroups v2
    CGROUP_PATH="/sys/fs/cgroup/$CGROUP_NAME"
    mkdir -p "$CGROUP_PATH"
    echo 1 > "$CGROUP_PATH/cgroup.procs" || { echo "Failed to create cgroup"; exit 1; }
    echo "Using cgroups v2: $CGROUP_PATH"
else
    # Use cgroups v1
    cgcreate -g net_cls,net_prio:$CGROUP_NAME || { echo "Failed to create cgroup. Please ensure cgroups v1 is mounted"; exit 1; }
    echo $((0x10000 + $(echo $CLASS_ID | cut -d: -f2))) > /sys/fs/cgroup/net_cls/$CGROUP_NAME/net_cls.classid
    echo "Using cgroups v1: $CGROUP_NAME"
fi

# Configure tc (set bandwidth and delay only)
echo "Configuring TC rules..."
tc qdisc add dev $INTERFACE root handle 1: htb default 10 || { echo "Failed to add root queue"; exit 1; }
tc class add dev $INTERFACE parent 1: classid 1:1 htb rate ${BANDWIDTH_LIMIT}kbit || { echo "Failed to add main class"; exit 1; }
tc class add dev $INTERFACE parent 1:1 classid $CLASS_ID htb rate ${BANDWIDTH_LIMIT}kbit ceil ${BANDWIDTH_LIMIT}kbit || { echo "Failed to add restricted class"; exit 1; }

# Add delay (delay only, without other network impairments)
echo "Adding network delay..."
if [ "$DELAY" -gt 0 ]; then
    tc qdisc add dev $INTERFACE parent $CLASS_ID handle 10: netem delay ${DELAY}ms || { echo "Failed to add delay"; exit 1; }
else
    # If delay is 0, do not add the netem module
    tc qdisc add dev $INTERFACE parent $CLASS_ID handle 10: pfifo || { echo "Failed to add default queue"; exit 1; }
fi

# Set iptables rules (with counters)
echo "Configuring iptables rules..."
# Remove old rules (if any)
if [ "$CGROUP_VERSION" = "cgroup2fs" ]; then
    iptables -t mangle -D OUTPUT -m cgroup --path $CGROUP_NAME -j MARK --set-mark $MARK 2>/dev/null
else
    iptables -t mangle -D OUTPUT -m cgroup --cgroup $((0x10000 + $(echo $CLASS_ID | cut -d: -f2))) -j MARK --set-mark $MARK 2>/dev/null
fi

# Add new rules and reset counters
if [ "$CGROUP_VERSION" = "cgroup2fs" ]; then
    iptables -t mangle -I OUTPUT 1 -m cgroup --path $CGROUP_NAME -j MARK --set-mark $MARK || { echo "Failed to add OUTPUT rule"; exit 1; }
else
    iptables -t mangle -I OUTPUT 1 -m cgroup --cgroup $((0x10000 + $(echo $CLASS_ID | cut -d: -f2))) -j MARK --set-mark $MARK || { echo "Failed to add OUTPUT rule"; exit 1; }
fi

iptables -t mangle -D PREROUTING -i $INTERFACE -m mark --mark $MARK -j CONNMARK --set-mark $MARK 2>/dev/null
iptables -t mangle -A PREROUTING -i $INTERFACE -m mark --mark $MARK -j CONNMARK --set-mark $MARK || { echo "Failed to add PREROUTING rule"; exit 1; }

iptables -t mangle -D OUTPUT -o $INTERFACE -m connmark --mark $MARK -j MARK --set-mark $MARK 2>/dev/null
iptables -t mangle -A OUTPUT -o $INTERFACE -m connmark --mark $MARK -j MARK --set-mark $MARK || { echo "Failed to add OUTPUT(connmark) rule"; exit 1; }

# Direct marked traffic to the tc class
echo "Directing marked traffic to the TC class..."
tc filter add dev $INTERFACE parent 1: protocol ip handle $MARK fw classid $CLASS_ID || { echo "Failed to add filter"; exit 1; }

# Record initial traffic statistics
echo "Recording initial network traffic..."
read initial_packets initial_bytes <<< $(get_marked_stats)
echo "Initial packet count: $initial_packets"
echo "Initial byte count: $(format_bytes $initial_bytes)"

# Start the command and get its PID
echo "Starting command and restricting local network..."
echo "Interface: $INTERFACE"
echo "Bandwidth limit: ${BANDWIDTH_LIMIT}Kbps"
echo "Delay: ${DELAY}ms"
echo "Executing command: ${CMD_ARGS[*]}"

"${CMD_ARGS[@]}" &
PID=$!
echo "Process PID: $PID"

# Add the process to the cgroup
echo "Adding process to cgroup..."
if [ "$CGROUP_VERSION" = "cgroup2fs" ]; then
    echo $PID > "$CGROUP_PATH/cgroup.procs" || { echo "Failed to add process to cgroup"; exit 1; }
else
    echo $PID > /sys/fs/cgroup/net_cls/$CGROUP_NAME/tasks || { echo "Failed to add process to cgroup"; exit 1; }
fi

# Cleanup function
cleanup() {
    echo "Cleaning up resources..."
    
    # Record final traffic statistics
    echo "Recording final network traffic..."
    read final_packets final_bytes <<< $(get_marked_stats)
    
    # Calculate traffic differences
    packet_count=$((final_packets - initial_packets))
    byte_count=$((final_bytes - initial_bytes))
    
    # Display traffic statistics
    echo "--- Network Traffic Statistics ---"
    echo "Total packets: $packet_count"
    echo "Total received/sent traffic: $(format_bytes $byte_count)"
    echo "-------------------"
    
    # Remove iptables rules
    if [ "$CGROUP_VERSION" = "cgroup2fs" ]; then
        iptables -t mangle -D OUTPUT -m cgroup --path $CGROUP_NAME -j MARK --set-mark $MARK 2>/dev/null
    else
        iptables -t mangle -D OUTPUT -m cgroup --cgroup $((0x10000 + $(echo $CLASS_ID | cut -d: -f2))) -j MARK --set-mark $MARK 2>/dev/null
    fi
    
    iptables -t mangle -D PREROUTING -i $INTERFACE -m mark --mark $MARK -j CONNMARK --set-mark $MARK 2>/dev/null
    iptables -t mangle -D OUTPUT -o $INTERFACE -m connmark --mark $MARK -j MARK --set-mark $MARK 2>/dev/null
    
    # Remove tc rules
    tc qdisc del dev $INTERFACE parent $CLASS_ID handle 10: 2>/dev/null
    tc class del dev $INTERFACE classid $CLASS_ID 2>/dev/null
    tc class del dev $INTERFACE classid 1:1 2>/dev/null
    tc qdisc del dev $INTERFACE root 2>/dev/null
    
    # Delete cgroup
    if [ "$CGROUP_VERSION" = "cgroup2fs" ]; then
        # Recursively clean up cgroup v2
        for subtree in $(ls "$CGROUP_PATH" 2>/dev/null); do
            if [ -d "$CGROUP_PATH/$subtree" ]; then
                echo 0 > "$CGROUP_PATH/$subtree/cgroup.procs" 2>/dev/null
            fi
        done
        echo 0 > "$CGROUP_PATH/cgroup.procs" 2>/dev/null
        rmdir "$CGROUP_PATH" 2>/dev/null
    else
        cgdelete -r net_cls,net_prio:$CGROUP_NAME 2>/dev/null
    fi
    
    # Restore sysctl settings
    sysctl -w net.ipv4.conf.lo.forwarding=0
    sysctl -w net.ipv4.conf.all.route_localnet=0
    
    exit
}

# Set up signal handling
trap cleanup SIGINT SIGTERM EXIT

# Wait for the process to finish
wait $PID
