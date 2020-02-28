#!/bin/bash

# make.sh: Generate customized libvirt XML.
# by Foxlet <foxlet@furcode.co>

VMDIR=$PWD
OUT="template.xml"

# source environment file
if [[ -f "$VMDIR/.env" ]]; then
    . .env
fi

print_usage() {
    echo
    echo "Usage: $0"
    echo
    echo " -a, --add   Add XML to virsh (uses sudo)."
    echo
}

error() {
    local error_message="$*"
    echo "${error_message}" 1>&2;
}

get_machine() {
    qemu-system-x86_64 --machine help | grep q35 | cut -d" " -f1 | grep -Eoe ".*-[0-9.]+" | sort -rV | head -1
}

get_uuid() {
    local uuid
    if [[ -f "$OUT" ]]; then
        uuid=$(grep -oP "<uuid>\K[a-f0-9-]+(?=</uuid>)" "$OUT" | head -n1)
    fi
    if [[ -z "$uuid" ]]; then
        uuid=$(cat /proc/sys/kernel/random/uuid)
    fi
    echo "$uuid"
}

get_vcpu() {
    awk '$1 == "siblings" { print $3 }' /proc/cpuinfo | head -n1
}

get_cores() {
    awk '$0 ~ /^cpu cores/ { print $4 }' /proc/cpuinfo | head -n1
}

get_threads() {
    echo $(($(get_vcpu) / $(get_cores)))
}

get_memory() {
    local mem_total=$(awk '$1 == "MemTotal:" { print $2 }' /proc/meminfo)
    local mem_allocated=$(($mem_total / 4))
    if [[ "$mem_allocated" -lt 2097152 ]]; then
        mem_allocated=2097152
    elif [[ "$mem_allocated" -gt 12582912 ]]; then
        mem_allocated=12582912
    fi
    echo "$mem_allocated"
}

get_mac_address() {
    local mac_address
    if [[ -f "$OUT" ]]; then
        mac_address=$(grep -oP "mac address='\K[a-f0-9:]+(?=')" "$OUT" | head -n1)
    fi
    if [[ -z "$mac_address" ]] || [[ "$mac_address" == "52:54:00:92:d4:7b" ]]; then
        mac_address=$(openssl rand -hex 6 | sed 's/\(..\)/\1:/g; s/:$//')
    fi
    echo "$mac_address"
}

generate() {
    sed -e "s|CORES|${CORES:-$(get_cores)}|g" \
        -e "s|MAC_ADDRESS|${MAC_ADDRESS:-$(get_mac_address)}|g" \
        -e "s|MACHINE|$(get_machine)|g" \
        -e "s|MEMORY|${MEMORY:-$(get_memory)}|g" \
        -e "s|NAME|${NAME:-macOS-Simple-KVM}|g" \
        -e "s|THREADS|${THREADS:-$(get_threads)}|g" \
        -e "s|UUID|${UUID:-$(get_uuid)}|g" \
        -e "s|VCPU|${VCPU:-$(get_vcpu)}|g" \
        -e "s|VMDIR|$VMDIR|g" \
        tools/template.xml.in > $OUT
    echo "$OUT has been generated in $VMDIR"
}

generate

argument="$1"
case $argument in
    -a|--add)
        sudo virsh define $OUT
        ;;
    -h|--help)
        print_usage
        ;;
esac
