#!/usr/bin/bash

# Build this PKGBUILD with qemu virtual machine.
# We can have more control of resources, and most important, we can pause builder and recover in the future.

# NOTE: sudo is required only when you need to create a builder.

# Package Requirements:
#   arch-install-scripts bash coreutils e2fsprogs edk2-ovmf gptfdisk grep kmod pacman qemu-img
#   qemu-system-x86 qemu-system-x86 sudo systemd util-linux virtiofsd

DATA_DIR="$(readlink -e "$(dirname "$0")")"
readonly DATA_DIR
# ./guest/etc/systemd/system/dev-disk-by\x2duuid-7152de1a\x2d738b\x2d4b7c\x2dade1\x2dd99ff86ae8d2.swap
# Requires static swap UUID
# QEMU kernel command requires static rootfs UUID
readonly SWAP_UUID=7152de1a-738b-4b7c-ade1-d99ff86ae8d2 \
         ROOT_UUID=a59695a9-cdb7-4578-b21d-81f8a095d443 \
         IMG_SIZE=128G \
         ROOT_SIZE=64G \
         MEMORY_SIZE=10G \
         CPU_CORES=10 \
         SERIAL_SPEED=115200 \
         SAVE_TAG=latest-builder-status
         FIRMWARE_VARS="$DATA_DIR/OVMF_VARS.4m.qcow2" \
         FIRMWARE_CODE="/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd" \
         FIRMWARE_VARS_TEMPLATE="/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd" \
         RUNTIME_DIR="/run/qemu-builder" \
         USER_RUNTIME_DIR="$XDG_RUNTIME_DIR/qemu-builder" \
         SUDO=sudo
readonly QEMU_NBD="$SUDO qemu-nbd" \
         MODPROBE="$SUDO modprobe" \
         SGDISK="$SUDO sgdisk" \
         MKFS="$SUDO mkfs.ext4" \
         MKSWAP="$SUDO mkswap" \
         MOUNT="$SUDO mount" \
         PACSTRAP="$SUDO pacstrap" \
         ARCH_CHROOT="$SUDO arch-chroot" \
         CP="$SUDO cp" \
         UMOUNT="$SUDO umount" \
         LSFD="$SUDO lsfd" \
         KILL="$SUDO kill" \
         SED="$SUDO sed" \
         CHOWN="$SUDO chown"
VIRTIOFSD_STARTDIR_PATH="$(readlink -e "$DATA_DIR/..")"
readonly VIRTIOFSD="unshare -r --map-auto -- /usr/lib/virtiofsd --announce-submounts --sandbox chroot" \
         VIRTIOFSD_STARTDIR_SERVICE="virtiofsd-builder-startdir.service" \
         VIRTIOFSD_STARTDIR_PATH \
         VIRTIOFSD_STARTDIR_TAG="startdir" \
         VIRTIOFSD_STARTDIR_SOCKET="$USER_RUNTIME_DIR/virtiofsd-startdir.socket"
readonly MONITOR_SOCKET="$USER_RUNTIME_DIR/monitor.socket" \
         VM_CONSOLE_SOCKET="$USER_RUNTIME_DIR/console.socket" \
         BUILDER_SLICE="qemu-builder.slice" \
         BUILDER_SERVICE="builder.service"

function __create_qemu() {
    set -e
    echo "Creating qcow2 image..."
    qemu-img create -f qcow2 -o nocow=on "$DATA_DIR/data.qcow2" "$IMG_SIZE"
    mkdir -p "$DATA_DIR/boot"
    echo "Copying UEFI vars storage file..."
    qemu-img convert -O qcow2 -o nocow=on "$FIRMWARE_VARS_TEMPLATE" "$FIRMWARE_VARS"
    if ! lsmod | grep -q nbd
    then
        echo "Inserting NBD module..."
        _rmmod=true
        $MODPROBE nbd
    else
        _rmmod=false
    fi
    readonly _rmmod
    local NBD nbd
    for nbd in /sys/class/block/nbd*
    do
        if [[ $(< "$nbd/size") == 0 ]]
        then
            readonly NBD=${nbd##*/}
            echo "Using NBD device $NBD"
            break
        fi
    done
    if [[ -z "$NBD" ]]
    then
        echo "Unable to find an available NBD device."
        exit 2
    fi
    echo "Attaching qcow2 img to /dev/$NBD..."
    $QEMU_NBD --connect "/dev/$NBD" "$DATA_DIR/data.qcow2"
    echo "Creating partitions on $DATA_DIR/data.qcow2..."
    $SGDISK --zap-all "/dev/$NBD"
    $SGDISK --new=1:0:+$ROOT_SIZE --typecode=1:8304 --new=2:0:0 --typecode=2:8200 "/dev/$NBD"
    echo "Creating filesystem on $DATA_DIR/data.qcow2..."
    $MKFS "/dev/${NBD}p1" -U "$ROOT_UUID"
    $MKSWAP "/dev/${NBD}p2" --uuid "$SWAP_UUID"
    echo "Mounting filesystem..."
    $MOUNT --mkdir "/dev/${NBD}p1" "$RUNTIME_DIR/root"
    echo "Bootstrapping archlinux..."
    $PACSTRAP -K "$RUNTIME_DIR/root" base base-devel linux
    # shellcheck disable=SC2164
    pushd "$DATA_DIR/.."
    # shellcheck disable=SC2086
    makepkg --printsrcinfo | grep -P '^\tmakedepends|^\tdepends' | cut -d = -f 2 | xargs -rt $ARCH_CHROOT "$RUNTIME_DIR/root" pacman -S --needed --noconfirm
    # shellcheck disable=SC2164
    popd
    echo "Adding builder..."
    $CP -r "$DATA_DIR/guest/." "$RUNTIME_DIR/root/"
    $ARCH_CHROOT "$RUNTIME_DIR/root" systemd-sysusers
    $ARCH_CHROOT "$RUNTIME_DIR/root" systemd-tmpfiles --create
    $SED -i "3 i auth sufficient pam_listfile.so item=tty sense=allow file=/etc/securetty onerr=fail apply=root" \
        "$RUNTIME_DIR/root/etc/pam.d/login"
    echo "Grabbing kernel and initramfs..."
    $CP --no-preserve=ownership,mode -t "$DATA_DIR/boot/" \
        "$RUNTIME_DIR/root/boot/initramfs-linux-fallback.img" \
        "$RUNTIME_DIR/root/boot/vmlinuz-linux"
    $CHOWN -R "$(id -u):$(id -g)" "$DATA_DIR/boot"
    echo "Killing orphaned processes..."
    # shellcheck disable=SC2086
    $LSFD --filter "NAME =~ \"$RUNTIME_DIR/root\"" --output "PID" --noheadings | sort -u | xargs $KILL --verbose
    echo "Unmounting filesystem..."
    $UMOUNT "$RUNTIME_DIR/root"
    echo "Unattaching qcow2 img..."
    $QEMU_NBD --disconnect "/dev/$NBD"
    if "$_rmmod"
    then
        echo "Removing NBD module..."
        $MODPROBE -r nbd
    fi
    set +e
}

function __launch_qemu() {
    local -a args=(
        -enable-kvm
        -machine "q35,vmport=off"
        -m size="$MEMORY_SIZE"
        -cpu host
        -smp "$CPU_CORES"
        -drive "if=pflash,format=raw,readonly=on,file=$FIRMWARE_CODE"
        -drive "if=pflash,format=qcow2,file=$FIRMWARE_VARS"
        -drive "if=virtio,format=qcow2,file=$DATA_DIR/data.qcow2,aio=native,cache.direct=on"
        -kernel "$DATA_DIR/boot/vmlinuz-linux"
        -initrd "$DATA_DIR/boot/initramfs-linux-fallback.img"
        -append "root=UUID=$ROOT_UUID console=ttyS0,$SERIAL_SPEED"
        -device "vhost-user-fs-pci,chardev=char0,tag=$VIRTIOFSD_STARTDIR_TAG"
        -object "memory-backend-memfd,id=mem0,size=$MEMORY_SIZE,share=on"
        -numa "node,memdev=mem0"
        -chardev "socket,id=char0,path=$VIRTIOFSD_STARTDIR_SOCKET"
        -chardev "socket,id=char1,path=$VM_CONSOLE_SOCKET,server=on,wait=off"
        -monitor "unix:$MONITOR_SOCKET,server,wait=off"
        -serial "chardev:char1"
        -nographic
    )
    if [[ -n "$1" ]]
    then
        args+=(-loadvm "$1")
    fi
    mkdir -p "$USER_RUNTIME_DIR"
    # shellcheck disable=SC2086
    systemd-run --user --unit "$VIRTIOFSD_STARTDIR_SERVICE" --slice "$BUILDER_SLICE" --description "virtiofsd for $VIRTIOFSD_STARTDIR_PATH" \
        $VIRTIOFSD --socket-path "$VIRTIOFSD_STARTDIR_SOCKET" --shared-dir "$VIRTIOFSD_STARTDIR_PATH"
    echo "HINT: Root does not have any password, but you can login directly on any console in /etc/securetty."
    systemd-run --user --unit "$BUILDER_SERVICE" --slice "$BUILDER_SLICE" --description "Qemu process for running builder" \
        qemu-system-x86_64 "${args[@]}"
    if [[ -n "$1" ]]
    then
        while ! [[ -S "$MONITOR_SOCKET" ]]
        do
            echo "Waiting for monitor socket..."
            sleep 1
        done
        echo "cont" | socat - "unix-connect:$MONITOR_SOCKET"
    fi
}

function __save_qemu() {
    echo -e "stop\nsavevm $SAVE_TAG\ncommit\nquit" | socat - "unix-connect:$MONITOR_SOCKET"
}

function __connect_qemu() {
    socat "stdin,raw,echo=0,escape=0x11,b$SERIAL_SPEED" "unix-connect:$VM_CONSOLE_SOCKET"
}

function __stop_processes() {
    if systemctl --user is-active "$BUILDER_SLICE"
    then
        echo "$BUILDER_SLICE is active, stopping it..."
        systemctl --user stop "$BUILDER_SLICE"
    fi
}

case "$1" in
    --create)
        echo "Creating new builder..."
        __create_qemu
        ;;
    --new)
        echo "Launching new builder..."
        __launch_qemu
        ;;
    --continue)
        echo "Continue existing builder..."
        __launch_qemu "$SAVE_TAG"
        ;;
    --save)
        echo "Saving builder..."
        __save_qemu
        ;;
    --shell)
        echo "Connecting to builder..."
        echo "You can use Ctrl+Q to exit shell."
        __connect_qemu
        ;;
    --stop-processes)
        echo "Cleaning up remaining processes..."
        __stop_processes
        ;;
    *)
        echo "Invalid option."
        echo "Usage: $0 --create|--new|--continue|--save|--shell|--stop-processes"
        exit 1
        ;;
esac
