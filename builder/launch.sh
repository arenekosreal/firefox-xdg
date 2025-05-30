#!/usr/bin/bash

# Build this PKGBUILD with qemu virtual machine.
# We can have more control of resources, and most important, we can pause builder and recover in the future.

# NOTE: sudo is required only when you need to create a builder.

# Package Requirements:
#   arch-install-scripts
#   bash
#   btrfs-progs
#   coreutils
#   edk2-ovmf
#   findutils
#   gptfdisk
#   grep
#   kmod
#   pacman
#   qemu-img
#   qemu-system-x86
#   sed
#   socat
#   sudo
#   systemd
#   util-linux
#   virtiofsd

readonly READLINK=readlink \
         DIRNAME=dirname \
         UNAME=uname \
         UUIDGEN=uuidgen \
         SUDO=sudo
QEMU_SYSTEM="qemu-system-$($UNAME -m)"
SCRIPT_DIR="$($READLINK -e "$($DIRNAME "$0")")"
SWAP_UUID="$($UUIDGEN)"
VIRTIOFSD_STARTDIR_PATH="$($READLINK -e "$SCRIPT_DIR/..")"
readonly SCRIPT_DIR \
         DATA_DIR="${DATA_DIR:-$SCRIPT_DIR}" \
         QEMU_SYSTEM \
         SWAP_UUID \
         SWAP_SIZE=64G \
         MEMORY_SIZE=12G \
         CPU_CORES=4 \
         SERIAL_SPEED=115200 \
         ROOT_SUBVOL="slash" \
         FIRMWARE_CODE="/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd" \
         FIRMWARE_VARS="/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd" \
         USER_RUNTIME_DIR="$XDG_RUNTIME_DIR/qemu-builder" \
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
         RM="$SUDO rm" \
         SOCAT=socat \
         TEE="tee -a" \
         QEMU_NBD="$SUDO qemu-nbd" \
         MODPROBE="$SUDO modprobe" \
         SGDISK="$SUDO sgdisk" \
         MKSWAP="$SUDO mkswap"
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
    $ECHO "Adding those items into /etc/fstab:"
    {
        echo "UUID=$SWAP_UUID   none        swap        defaults"
        echo "startdir          /startdir   virtiofs    defaults"
    } | $TEE "$DATA_DIR/$ROOT_SUBVOL/etc/fstab"

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
    local NVRAM="$DATA_DIR/OVMF_VARS.4m.qcow2"
    local -a args=(-enable-kvm
                   -machine "q35,vmport=off"
                   -m "size=$MEMORY_SIZE"
                   -cpu "host"
                   -smp "$CPU_CORES"
                   -drive "if=virtio,format=qcow2,file=$DATA_DIR/swap.qcow2,aio=native,cache.direct=on"
                   -drive "if=pflash,format=raw,readonly=on,file=$FIRMWARE_CODE"
                   -drive "if=pflash,format=qcow2,file=$NVRAM"
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
    if [[ ! -e "$NVRAM" ]]
    then
        $QEMU_IMG convert -O qcow2 -o nocow=on -o compression_type=zstd "$FIRMWARE_VARS" "$NVRAM"
    fi
    # shellcheck disable=SC2086
    $SYSTEMD_RUN --unit "$VIRTIOFSD_STARTDIR_SERVICE" --slice "$BUILDER_SLICE" --description "virtiofsd for $VIRTIOFSD_STARTDIR_PATH" \
        $VIRTIOFSD --socket-path "$VIRTIOFSD_STARTDIR_SOCKET" --shared-dir "$VIRTIOFSD_STARTDIR_PATH"
    # shellcheck disable=SC2086
    $SYSTEMD_RUN --unit "$VIRTIOFSD_SLASH_SERVICE" --slice "$BUILDER_SLICE" --description "virtiofsd for $VIRTIOFSD_SLASH_PATH" \
        $VIRTIOFSD --socket-path "$VIRTIOFSD_SLASH_SOCKET" --shared-dir "$VIRTIOFSD_SLASH_PATH"
    # shellcheck disable=SC2086
    $SYSTEMD_RUN --unit "$BUILDER_SERVICE" --slice "$BUILDER_SLICE" --description "Qemu process for running builder" \
        $QEMU_SYSTEM "${args[@]}"
    $ECHO "HINT: Root does not have any password, but you can login directly on any console in /etc/securetty."
}

function __connect_qemu() {
    $SOCAT "stdin,raw,echo=0,escape=0x11,b$SERIAL_SPEED" "unix-connect:$VM_CONSOLE_SOCKET"
}

function __quit_qemu() {
    if $SYSTEMCTL --quiet is-active "$BUILDER_SLICE"
    then
        $ECHO "$BUILDER_SLICE is active, stopping it..."
        $SYSTEMCTL stop "$BUILDER_SLICE"
    fi
}

function __manage_qemu() {
    $SOCAT "stdin,raw,echo=0,escape=0x11" "unix-connect:$MONITOR_SOCKET"
}

case "$1" in
    --create)
        $ECHO "Creating new builder..."
        __create_qemu
        ;;
    --launch)
        $ECHO "Launching builder..."
        __launch_qemu
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
    --manage)
        $ECHO "Connectiong to Qemu monitor..."
        $ECHO "You can use Ctrl+Q to exit shell."
        __manage_qemu
        ;;
    *)
        $ECHO "Unsupported option $1."
        $ECHO "Usage: $0 --create|--launch|--shell|--quit|--manage"
        $ECHO "Recommend workflow:"
        $ECHO "$0 --create"
        $ECHO "$0 --launch"
        $ECHO "$0 --shell"
        $ECHO "     # systemctl start builder"
        $ECHO "# Press Ctrl+Q to leave shell."
        $ECHO "# Wait until it needs to be paused."
        $ECHO "$0 --manage"
        $ECHO "     (QEMU) stop"
        $ECHO "     (QEMU) savevm tag"
        $ECHO "     (QEMU) quit"
        $ECHO "$0 --quit"
        $ECHO "$0 --launch"
        $ECHO "$0 --manage"
        $ECHO "     (QEMU) loadvm tag"
        $ECHO "     (QEMU) cont"
        $ECHO "# Press Ctrl+Q to leave monitor shell."
        $ECHO "# Save and load again until it finishes work."
        $ECHO "$0 --shell"
        $ECHO "     # systemctl poweroff"
        $ECHO "$0 --quit"
        $ECHO "You can use environment variable DATA_DIR to control where to storage vm data, which may eat so much space."
        ;;
esac
