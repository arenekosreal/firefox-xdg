#!/usr/bin/bash

# Build this PKGBUILD with qemu virtual machine.
# We can have more control of resources, and most important, we can pause builder and recover in the future.

# NOTE: sudo is required only when you need to create a builder.

# Package Requirements:
#   arch-install-scripts bash coreutils e2fsprogs edk2-ovmf findmnt gptfdisk grep kmod pacman qemu-img
#   qemu-system-x86 qemu-system-x86 sudo systemd util-linux virtiofsd
readonly READLINK=readlink \
         DIRNAME=dirname \
         UNAME=uname
QEMU_SYSTEM="qemu-system-$($UNAME -m)"
SCRIPT_DIR="$($READLINK -e "$($DIRNAME "$0")")"
readonly SCRIPT_DIR \
         DATA_DIR="${DATA_DIR:-$SCRIPT_DIR}" \
         QEMU_SYSTEM
# ./guest/etc/systemd/system/dev-disk-by\x2duuid-7152de1a\x2d738b\x2d4b7c\x2dade1\x2dd99ff86ae8d2.swap
# Requires static swap UUID
readonly SWAP_UUID=7152de1a-738b-4b7c-ade1-d99ff86ae8d2 \
         SWAP_SIZE=64G \
         MEMORY_SIZE=12G \
         CPU_CORES=4 \
         SERIAL_SPEED=115200 \
         SAVE_TAG="latest-builder-status"
         ROOT_SUBVOL="slash" \
         FIRMWARE_CODE="/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd" \
         FIRMWARE_VARS="/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd" \
         USER_RUNTIME_DIR="$XDG_RUNTIME_DIR/qemu-builder" \
         SUDO=sudo \
         ECHO=echo \
         MKDIR="mkdir -p" \
         SET=set \
         GREP=grep \
         CUT=cut \
         XARGS="xargs -rt" \
         MAKEPKG=makepkg \
         PUSHD=pushd \
         POPD=popd \
         SYSTEMD_RUN="systemd-run --user --collect" \
         FINDMNT=findmnt \
         BTRFS=btrfs \
         QEMU_IMG=qemu-img \
         EXIT=exit \
         PACSTRAP="pacstrap -K -N" \
         CP=cp \
         SED=sed \
         SYSTEMCTL="systemctl --user" \
         SLEEP=sleep \
         RM=rm
readonly QEMU_NBD="$SUDO qemu-nbd" \
         MODPROBE="$SUDO modprobe" \
         SGDISK="$SUDO sgdisk" \
         MKSWAP="$SUDO mkswap"
VIRTIOFSD_STARTDIR_PATH="$($READLINK -e "$DATA_DIR/..")"
readonly VIRTIOFSD="unshare -r --map-auto -- /usr/lib/virtiofsd --announce-submounts --sandbox chroot" \
         VIRTIOFSD_STARTDIR_SERVICE="virtiofsd-builder-startdir.service" \
         VIRTIOFSD_STARTDIR_PATH \
         VIRTIOFSD_STARTDIR_TAG="startdir" \
         VIRTIOFSD_STARTDIR_SOCKET="$USER_RUNTIME_DIR/virtiofsd-startdir.socket" \
         VIRTIOFSD_SLASH_SERVICE="virtiofsd-builder-slash.service" \
         VIRTIOFSD_SLASH_PATH="$DATA_DIR/$ROOT_SUBVOL" \
         VIRTIOFSD_SLASH_TAG="$ROOT_SUBVOL" \
         VIRTIOFSD_SLASH_SOCKET="$USER_RUNTIME_DIR/virtiofsd-slash.socket" \
         MONITOR_SOCKET="$USER_RUNTIME_DIR/monitor.socket" \
         VM_CONSOLE_SOCKET="$USER_RUNTIME_DIR/console.socket" \
         BUILDER_SLICE="qemu-builder.slice" \
         BUILDER_SERVICE="builder.service"

$SET -e -o pipefail

# __create_subvolume_if_needed $directory $name
function __create_subvolume_if_needed() {
    $MKDIR "$1"
    case "$($FINDMNT --real -o FSTYPE -n -T "$1")" in
        btrfs)
            $ECHO "Creating BTRFS subvolume $1/$2..."
            $BTRFS subvolume create "$1/$2"
            ;;
        *)
            $ECHO "Unsupported filesystem, falling back to create normal directory $1/$2..."
            $MKDIR "$1/$2"
            ;;
    esac
}

function __get_vm_status() {
    local status
    if [[ -S "$MONITOR_SOCKET" ]] && status=$(echo "info status" | socat - "unix-connect:$MONITOR_SOCKET" | $GREP "VM status" | $CUT -d : -f 2 | xargs)
    then
        echo "$status"
    fi
}

function __create_qemu() {
    if [[ -d "$DATA_DIR/$ROOT_SUBVOL" ]]
    then
        $ECHO "Removing existing /..."
        $RM -rf "$DATA_DIR/$ROOT_SUBVOL"
    fi
    $ECHO "Creating / in $DATA_DIR..."
    __create_subvolume_if_needed "$DATA_DIR" "$ROOT_SUBVOL"
    $CP -r "$SCRIPT_DIR/guest/." "$DATA_DIR/$ROOT_SUBVOL"
    $PUSHD "$SCRIPT_DIR/.."
    # shellcheck disable=SC2086
    $MAKEPKG --printsrcinfo | $GREP -P '^\tmakedepends|^\tdepends' | $CUT -d = -f 2 | $XARGS $PACSTRAP "$DATA_DIR/$ROOT_SUBVOL" base base-devel linux
    $POPD
    $SED -i "3 i auth sufficient pam_listfile.so item=tty sense=allow file=/etc/securetty onerr=fail apply=root" \
        "$DATA_DIR/$ROOT_SUBVOL/etc/pam.d/login"

    $ECHO "Creating qcow2 image to storage swap..."
    $QEMU_IMG create -f qcow2 -o nocow=on -o compression_type=zstd "$DATA_DIR/swap.qcow2" "$SWAP_SIZE"
    $ECHO "Ensuring NBD module is inserted..."
    $MODPROBE nbd
    local nbd NBD
    for nbd in /sys/class/block/nbd*
    do
        if [[ "$(< "$nbd/size")" == 0 ]]
        then
            NBD="${nbd##*/}"
            $ECHO "Using NBD device $NBD"
            break
        fi
    done
    if [[ -z "$NBD" ]]
    then
        $ECHO "Unable to find an available NBD device."
        $EXIT 2
    fi
    unset nbd
    $ECHO "Connecting qemu-nbd..."
    $QEMU_NBD --connect "/dev/$NBD" "$DATA_DIR/swap.qcow2"
    $ECHO "Partitioning /dev/$NBD..."
    $SGDISK --zap-all "/dev/$NBD"
    $SGDISK --new="1:0:0" --typecode="1:8200" "/dev/$NBD"
    $ECHO "Creating filesystem..."
    $MKSWAP "/dev/${NBD}p1" --uuid "$SWAP_UUID"
    $ECHO "Disconnecting qemu-nbd..."
    $QEMU_NBD --disconnect "/dev/$NBD"
}

function __launch_qemu() {
    local -a args=(-enable-kvm
                   -machine "q35,vmport=off"
                   -m "size=$MEMORY_SIZE"
                   -cpu "host"
                   -smp "$CPU_CORES"
                   -drive "if=pflash,format=raw,readonly=on,file=$FIRMWARE_CODE"
                   -drive "if=pflash,format=raw,readonly=on,file=$FIRMWARE_VARS"
                   -drive "if=virtio,format=qcow2,file=$DATA_DIR/swap.qcow2,aio=native,cache.direct=on"
                   -kernel "$DATA_DIR/$ROOT_SUBVOL/boot/vmlinuz-linux"
                   -initrd "$DATA_DIR/$ROOT_SUBVOL/boot/initramfs-linux-fallback.img"
                   -append "root=$VIRTIOFSD_SLASH_TAG rootfstype=virtiofs rw console=ttyS0,$SERIAL_SPEED"
                   -device "vhost-user-fs-pci,chardev=char0,tag=$VIRTIOFSD_STARTDIR_TAG"
                   -device "vhost-user-fs-pci,chardev=char1,tag=$VIRTIOFSD_SLASH_TAG"
                   -object "memory-backend-memfd,id=mem0,size=$MEMORY_SIZE,share=on"
                   -numa "node,memdev=mem0"
                   -chardev "socket,id=char0,path=$VIRTIOFSD_STARTDIR_SOCKET"
                   -chardev "socket,id=char1,path=$VIRTIOFSD_SLASH_SOCKET"
                   -chardev "socket,id=char2,path=$VM_CONSOLE_SOCKET,server=on,wait=off"
                   -monitor "unix:$MONITOR_SOCKET,server=on,wait=off"
                   -serial "chardev:char2"
                   -nographic)
    $MKDIR "$USER_RUNTIME_DIR"
    # shellcheck disable=SC2086
    $SYSTEMD_RUN --unit "$VIRTIOFSD_STARTDIR_SERVICE" --slice "$BUILDER_SLICE" --description "virtiofsd for $VIRTIOFSD_STARTDIR_PATH" \
        $VIRTIOFSD --socket-path "$VIRTIOFSD_STARTDIR_SOCKET" --shared-dir "$VIRTIOFSD_STARTDIR_PATH"
    # shellcheck disable=SC2086
    $SYSTEMD_RUN --unit "$VIRTIOFSD_SLASH_SERVICE" --slice "$BUILDER_SLICE" --description "virtiofsd for $VIRTIOFSD_SLASH_PATH" \
        $VIRTIOFSD --socket-path "$VIRTIOFSD_SLASH_SOCKET" --shared-dir "$VIRTIOFSD_SLASH_PATH"
    # shellcheck disable=SC2086
    $SYSTEMD_RUN --unit "$BUILDER_SERVICE" --slice "$BUILDER_SLICE" --description "Qemu process for running builder" \
        $QEMU_SYSTEM "${args[@]}"
    if [[ -n "$1" ]]
    then
        while [[ "$(__get_vm_status)" != "running" ]]
        do
            $ECHO "Waiting for monitor socket to be ready..."
            $SLEEP 5
        done
        $ECHO "Recovering from state $1..."
        echo "loadvm $1" | socat - "unix-connect:$MONITOR_SOCKET"
        if [[ "$(__get_vm_status)" == "paused" ]]
        then
            echo "cont"  | socat - "unix-connect:$MONITOR_SOCKET"
        fi
    fi
    $ECHO "HINT: Root does not have any password, but you can login directly on any console in /etc/securetty."
}

function __save_qemu() {
    echo "stop"      | socat - "unix-connect:$MONITOR_SOCKET"
    echo "savevm $1" | socat - "unix-connect:$MONITOR_SOCKET"
}

function __connect_qemu() {
    socat "stdin,raw,echo=0,escape=0x11,b$SERIAL_SPEED" "unix-connect:$VM_CONSOLE_SOCKET"
}

function __quit_qemu() {
    echo "quit" | socat - "unix-connect:$MONITOR_SOCKET"
    if $SYSTEMCTL is-active "$BUILDER_SLICE"
    then
        $ECHO "$BUILDER_SLICE is active, stopping it..."
        $SYSTEMCTL stop "$BUILDER_SLICE"
    fi
}

case "$1" in
    --create)
        $ECHO "Creating new builder..."
        __create_qemu
        ;;
    --new)
        $ECHO "Launching new builder..."
        __launch_qemu
        ;;
    --continue)
        $ECHO "Continue existing builder..."
        __launch_qemu "$SAVE_TAG"
        ;;
    --save)
        $ECHO "Saving builder..."
        __save_qemu "$SAVE_TAG"
        ;;
    --shell)
        $ECHO "Connecting to builder..."
        $ECHO "You can use Ctrl+Q to exit shell."
        __connect_qemu
        ;;
    --quit)
        $ECHO "Quitting builder..."
        __quit_qemu
        ;;
    *)
        $ECHO "Invalid option."
        $ECHO "Usage: $0 --create|--new|--continue|--save|--shell|--quit"
        $ECHO "Recommend workflow:"
        $ECHO "$0 --create"
        $ECHO "$0 --new"
        $ECHO "$0 --save"
        $ECHO "$0 --quit"
        $ECHO "$0 --continue"
        $ECHO "$0 --save"
        $ECHO "$0 --quit"
        $ECHO "$0 --continue"
        $ECHO "You can use environment variable DATA_DIR to control where to storage vm data, which may eat so much space."
        ;;
esac
