#!/usr/bin/bash

# Build this PKGBUILD with qemu virtual machine.
# We can have more control of resources, and most important, we can pause builder and recover in the future.

# NOTE: sudo is required only when you need to create a builder.

# Package Requirements:
#    arch-install-scripts
#    coreutils
#    curl
#    e2fsprogs
#    findutils
#    gptfdisk
#    grep
#    kmod
#    pacman
#    qemu-img
#    qemu-system-x86
#    sed
#    socat
#    sudo
#    systemd
#    util-linux
#    virtiofsd

set -e -o pipefail

# Programs:
read -ra    SUDO <<< "${SUDO:-sudo}"
readonly -a SUDO
readonly -a DIRNAME=(dirname)
readonly -a UNAME=(uname)
readonly -a UUIDGEN=(uuidgen)
readonly -a READLINK=(readlink)
            TARGET_ARCH="${TARGET_ARCH:-"$("${UNAME[@]}" -m)"}"
readonly    TARGET_ARCH
readonly -a QEMU_SYSTEM=("qemu-system-$TARGET_ARCH")
readonly -a ECHO=(echo)
readonly -a MKDIR=(mkdir -p)
readonly -a MKDIR_ROOT=("${SUDO[@]}" "${MKDIR[@]}")
readonly -a GREP=(grep)
readonly -a CUT=(cut)
readonly -a XARGS=(xargs --no-run-if-empty)
readonly -a XARGS_VERBOSE=("${XARGS[@]}" --verbose)
readonly -a MAKEPKG=(makepkg)
readonly -a PUSHD=(pushd)
readonly -a POPD=(popd)
readonly -a SYSTEMD_RUN=(systemd-run --user --collect)
readonly -a MOUNT=(mount)
readonly -a MOUNT_ROOT=("${SUDO[@]}" "${MOUNT[@]}")
readonly -a UMOUNT=(umount)
readonly -a UMOUNT_ROOT=("${SUDO[@]}" "${UMOUNT[@]}")
readonly -a QEMU_IMG=(qemu-img)
readonly -a EXIT=(exit)
readonly -a PACSTRAP=(pacstrap -K -c)
readonly -a PACSTRAP_ROOT=("${SUDO[@]}" "${PACSTRAP[@]}")
readonly -a ARCH_CHROOT=(arch-chroot)
readonly -a ARCH_CHROOT_ROOT=("${SUDO[@]}" "${ARCH_CHROOT[@]}")
readonly -a CP=(cp --recursive)
readonly -a CP_ROOT=("${SUDO[@]}" "${CP[@]}")
readonly -a ID=(id)
readonly -a CHOWN=(chown --preserve-root --recursive)
readonly -a CHOWN_ROOT=("${SUDO[@]}" "${CHOWN[@]}")
readonly -a SED=(sed)
readonly -a SED_ROOT=("${SUDO[@]}" "${SED[@]}")
readonly -a SYSTEMCTL=(systemctl --user)
readonly -a RM=(rm --recursive --force)
readonly -a SOCAT=(socat)
readonly -a TEE=(tee)
readonly -a TEE_ROOT=("${SUDO[@]}" "${TEE[@]}")
readonly -a QEMU_NBD=(qemu-nbd)
readonly -a QEMU_NBD_ROOT=("${SUDO[@]}" "${QEMU_NBD[@]}")
readonly -a MODPROBE=(modprobe)
readonly -a MODPROBE_ROOT=("${SUDO[@]}" "${MODPROBE[@]}")
readonly -a SGDISK=(sgdisk)
readonly -a SGDISK_ROOT=("${SUDO[@]}" "${SGDISK[@]}")
readonly -a MKSWAP=(mkswap)
readonly -a MKSWAP_ROOT=("${SUDO[@]}" "${MKSWAP[@]}")
readonly -a MKFS_EXT4=(mkfs.ext4)
readonly -a MKFS_EXT4_ROOT=("${SUDO[@]}" "${MKFS_EXT4[@]}")
readonly -a LSFD=(lsfd)
readonly -a LSFD_ROOT=("${SUDO[@]}" "${LSFD[@]}")
readonly -a KILL=(kill --verbose)
readonly -a KILL_ROOT=("${SUDO[@]}" "${KILL[@]}")
readonly -a SORT=(sort -u)
readonly -a UNSHARE=(unshare --map-root-user --map-auto --)
readonly -a VIRTIOFSD=("${UNSHARE[@]}" /usr/lib/virtiofsd --announce-submounts --sandbox chroot)
readonly -a TOUCH=(touch)
readonly -a TOUCH_ROOT=("${SUDO[@]}" "${TOUCH[@]}")
readonly -a PACMAN=(pacman)
readonly -a CURL=(curl --location)
# Variables:
            SCRIPT_DIR=$("${READLINK[@]}" -e "$("${DIRNAME[@]}" "$0")")
readonly    SCRIPT_DIR
readonly    DATA_DIR="${DATA_DIR:-$SCRIPT_DIR}"
            SWAP_UUID="$("${UUIDGEN[@]}")"
readonly    SWAP_UUID
            ROOT_UUID="$("${UUIDGEN[@]}")"
readonly    ROOT_UUID
readonly    ID_BUILDER=qemu-builder
readonly    CPU_CORES=4
readonly    MEMORY_SIZE=12G
readonly    DATA_SIZE=128G
readonly    SWAP_SIZE=64G
readonly    SERIAL_SPEED=115200
readonly    FIRMWARE_CODE="/usr/share/edk2-ovmf/x64/OVMF_CODE.4m.fd"
readonly    FIRMWARE_VARS="/usr/share/edk2-ovmf/x64/OVMF_VARS.4m.fd"
readonly    FIRMWARE_VARS_RW="$DATA_DIR/OVMF_VARS.4m.qcow2"
readonly    VM_DATA_IMAGE="$DATA_DIR/data.qcow2"
readonly    VM_KERNEL="/boot/vmlinuz-linux"
readonly    VM_INITRAMFS="/boot/initramfs-linux-fallback.img"
readonly    SLICE_NAME="$ID_BUILDER.slice"
readonly    USER_RUNTIME="$XDG_RUNTIME_DIR/$ID_BUILDER"
            VIRTIOFSD_STARTDIR_PATH="$("${READLINK[@]}" -e "$SCRIPT_DIR/..")"
readonly    VIRTIOFSD_STARTDIR_PATH
readonly    VIRTIOFSD_STARTDIR_SERVICE="virtiofsd-startdir-builder.service"
readonly    VIRTIOFSD_STARTDIR_TAG="startdir"
readonly    VIRTIOFSD_STARTDIR_SOCKET="$USER_RUNTIME/virtiofsd-startdir.socket"
readonly    VM_MONITOR_SOCKET="$USER_RUNTIME/monitor.socket"
readonly    VM_CONSOLE_SOCKET="$USER_RUNTIME/console.socket"
readonly    VM_QMP_SOCKET="$USER_RUNTIME/qmp.socket"
readonly    VM_SERVICE="$ID_BUILDER.service"
readonly    SCRIPT_NAME="$0"
readonly    PACMAN_CONF="$DATA_DIR/pacman.conf"
readonly    _ERROR_COMMON_ERROR=1
readonly    _ERROR_NO_NBD_DEVICE=2

function __create_qemu() {
    local force=false create_data=false
    while [[ "$#" -gt 0 ]]
    do
        case "$1" in
            --force)
                force=true
                shift
                ;;
        esac
    done
    if "$force" || ! [[ -e "$FIRMWARE_VARS_RW" ]]
    then
        "${ECHO[@]}" "Creating $FIRMWARE_VARS_RW"
        "${QEMU_IMG[@]}" convert -O qcow2 -o nocow=on -o compression_type=zstd "$FIRMWARE_VARS" "$FIRMWARE_VARS_RW"
    else
        "${ECHO[@]}" "Skip creating $FIRMWARE_VARS_RW because it is exist."
    fi
    if "$force" || ! [[ -e "$VM_DATA_IMAGE" ]]
    then
        "${ECHO[@]}" "Creating $VM_DATA_IMAGE..."
        "${QEMU_IMG[@]}" create -f qcow2 -o nocow=on -o compression_type=zstd "$VM_DATA_IMAGE" "$DATA_SIZE"
        create_data=true
    else
        "${ECHO[@]}" "Skip creating $VM_DATA_IMAGE because it is exist."
    fi
    if "$create_data"
    then
        local NBD nbd
        "${MODPROBE_ROOT[@]}" nbd
        for nbd in /sys/class/block/nbd*
        do
            if [[ "$(< "$nbd/size")" == 0 ]]
            then
                NBD="${nbd##*/}"
                "${ECHO[@]}" "Using NBD device $NBD"
                break
            fi
        done
        if [[ -z "$NBD" ]]
        then
            "${ECHO[@]}" "Unable to find an available NBD device."
            "${EXIT[@]}" "$_ERROR_NO_NBD_DEVICE"
        fi
        unset nbd
        local TMP_MOUNTPOINT="/run/$ID_BUILDER"
        "${MKDIR_ROOT[@]}" "$TMP_MOUNTPOINT"
        "${ECHO[@]}" "Connecting NBD..."
        "${QEMU_NBD_ROOT[@]}" --connect "/dev/$NBD" "$VM_DATA_IMAGE"
        "${ECHO[@]}" "Partitioning /dev/$NBD..."
        "${SGDISK_ROOT[@]}" --zap-all \
            --new="1:0:+$SWAP_SIZE" --typecode="1:8200" \
            --new="2:0:0" --typecode="2:8304" \
        "/dev/$NBD"
        "${ECHO[@]}" "Creating filesystem..."
        "${MKSWAP_ROOT[@]}" --uuid "$SWAP_UUID" "/dev/${NBD}p1"
        "${MKFS_EXT4_ROOT[@]}" -U "$ROOT_UUID" "/dev/${NBD}p2"
        "${ECHO[@]}" "Preparing rootfs..."
        "${MOUNT_ROOT[@]}" "/dev/${NBD}p2" "$TMP_MOUNTPOINT"
        "${PUSHD[@]}" "$VIRTIOFSD_STARTDIR_PATH"
        local PACMAN_VERSION
        PACMAN_VERSION="$(LANG=C "${PACMAN[@]}" --query --info pacman | "${GREP[@]}" Version | "${CUT[@]}" --delimiter : --fields 2 | "${XARGS[@]}")"
        "${ECHO[@]}" "Getting default pacman config for version $PACMAN_VERSION..."
        "${CURL[@]}" "https://gitlab.archlinux.org/archlinux/packaging/packages/pacman/-/raw/$PACMAN_VERSION/pacman.conf" -o "$PACMAN_CONF"
        "${MAKEPKG[@]}" --printsrcinfo | "${GREP[@]}" -P '^\tmakedepends|^\tdepends' | "${CUT[@]}" -d = -f 2- | "${XARGS_VERBOSE[@]}" "${PACSTRAP_ROOT[@]}" -C "$PACMAN_CONF" "$TMP_MOUNTPOINT" base base-devel linux
        "${POPD[@]}"
        "${SED_ROOT[@]}" -i "3 i auth sufficient pam_listfile.so item=tty sense=allow file=/etc/securetty onerr=fail apply=root" \
            "$TMP_MOUNTPOINT/etc/pam.d/login"
        "${ECHO[@]}" "Adding those to $TMP_MOUNTPOINT/etc/fstab..."
        {
            echo "UUID=$SWAP_UUID           none        swap     defaults 0 0"
            echo "UUID=$ROOT_UUID           /           ext4     defaults 0 1"
            echo "$VIRTIOFSD_STARTDIR_TAG   /startdir   virtiofs defaults 0 0"
        } | "${TEE_ROOT[@]}" -a "$TMP_MOUNTPOINT/etc/fstab"
        "${ECHO[@]}" "Copying systemd files..."
        "${CP_ROOT[@]}" "$SCRIPT_DIR/guest/." "$TMP_MOUNTPOINT"
        "${ECHO[@]}" "Re-enabling fallback initramfs support..."
        "${TOUCH_ROOT[@]}" "$TMP_MOUNTPOINT/etc/vconsole.conf"
        "${SED_ROOT[@]}" -i 's/#PRESET/PRESET/;s/#fallback_image/fallback_image/' "$TMP_MOUNTPOINT/etc/mkinitcpio.d/linux.preset"
        "${ARCH_CHROOT_ROOT[@]}" "$TMP_MOUNTPOINT" mkinitcpio -P
        "${ECHO[@]}" "Saving kernel and initramfs for loading by QEMU directly..."
        local VM_BOOT="$DATA_DIR/boot"
        "${MKDIR[@]}" "$VM_BOOT"
        "${CP_ROOT[@]}" --target-directory "$VM_BOOT" \
            "$TMP_MOUNTPOINT$VM_KERNEL" "$TMP_MOUNTPOINT$VM_INITRAMFS"
        "${CHOWN_ROOT[@]}" "$("${ID[@]}" --user):$("${ID[@]}" --group)" "$VM_BOOT"
        "${ECHO[@]}" "Cleaning orphaned processes..."
        "${LSFD_ROOT[@]}" --filter "NAME =~ \"$TMP_MOUNTPOINT\"" --output "PID" --noheadings | "${SORT[@]}" | "${XARGS[@]}" "${KILL_ROOT[@]}"
        "${ECHO[@]}" "Unmounting partition..."
        "${UMOUNT_ROOT[@]}" "$TMP_MOUNTPOINT"
        "${QEMU_NBD_ROOT[@]}" --disconnect "/dev/$NBD"
    fi
}

function __launch_qemu() {
    local -a QEMU_ARGS=(-enable-kvm
                        -machine "q35,vmport=off"
                        -m "size=$MEMORY_SIZE"
                        -cpu "host"
                        -smp "$CPU_CORES"
                        -drive "if=virtio,format=qcow2,file=$VM_DATA_IMAGE,aio=native,cache.direct=on"
                        -drive "if=pflash,format=raw,file=$FIRMWARE_CODE,readonly=on"
                        -drive "if=pflash,format=qcow2,file=$FIRMWARE_VARS_RW"
                        -kernel "$DATA_DIR$VM_KERNEL"
                        -initrd "$DATA_DIR$VM_INITRAMFS"
                        -append "root=/dev/vda2 rootfstype=ext4 rootflag=rw,noatime console=ttyS0,$SERIAL_SPEED"
                        -device "vhost-user-fs-pci,chardev=char0,tag=$VIRTIOFSD_STARTDIR_TAG"
                        -object "memory-backend-memfd,id=mem0,size=$MEMORY_SIZE,share=on"
                        -numa "node,memdev=mem0"
                        -chardev "socket,id=char0,path=$VIRTIOFSD_STARTDIR_SOCKET"
                        -chardev "socket,id=char1,path=$VM_CONSOLE_SOCKET,server=on,wait=off"
                        -monitor "unix:$VM_MONITOR_SOCKET,server=on,wait=off"
                        -qmp "unix:$VM_QMP_SOCKET,server=on,wait=off"
                        -serial "chardev:char1"
                        -nographic)
    "${MKDIR[@]}" "$USER_RUNTIME"
    "${SYSTEMD_RUN[@]}" --unit "$VIRTIOFSD_STARTDIR_SERVICE" --slice "$SLICE_NAME" --description "virtiofsd for /startdir" \
        "${VIRTIOFSD[@]}" --socket-path "$VIRTIOFSD_STARTDIR_SOCKET" --shared-dir "$VIRTIOFSD_STARTDIR_PATH"
    "${SYSTEMD_RUN[@]}" --unit "$VM_SERVICE" --slice "$SLICE_NAME" --description "qemu for $ID_BUILDER" \
        "${QEMU_SYSTEM[@]}" "${QEMU_ARGS[@]}"
}

function __shell_qemu() {
    "${ECHO[@]}" "HINT: Use Ctrl+Q to leave the shell."
    "${SOCAT[@]}" "stdin,raw,echo=0,escape=0x11,b$SERIAL_SPEED" "unix-connect:$VM_CONSOLE_SOCKET"
}

function __manage_qemu() {
    "${ECHO[@]}" "HINT: Use Ctrl+Q to leave the shell."
    "${SOCAT[@]}" "stdin,raw,echo=0,escape=0x11" "unix-connect:$VM_MONITOR_SOCKET"
}

function __quit_qemu() {
    if "${SYSTEMCTL[@]}" --quiet is-active "$SLICE_NAME"
    then
        "${ECHO[@]}" "$SLICE_NAME is active, stopping it..."
        "${SYSTEMCTL[@]}" stop "$SLICE_NAME"
    fi
}

function __cleanup_qemu() {
    "${RM[@]}" "$VM_DATA_IMAGE" "$FIRMWARE_VARS_RW" "$DATA_DIR/boot"
}

function __help_qemu() {
    "${ECHO[@]}" "Control the vm builder to build PKGBUILD."
    "${ECHO[@]}"
    "${ECHO[@]}" "Usage:"
    "${ECHO[@]}"
    "${ECHO[@]}" "$SCRIPT_NAME command [arg_name...]"
    "${ECHO[@]}"
    "${ECHO[@]}"
    "${ECHO[@]}" "Commands:"
    "${ECHO[@]}"
    "${ECHO[@]}" "create:   Create a builder, this requires ${SUDO[*]} so we can run some commands as root."
    "${ECHO[@]}" "              --force: Override existing file."
    "${ECHO[@]}" "launch:   Launch the builder."
    "${ECHO[@]}" "shell:    Start a shell of the builder."
    "${ECHO[@]}" "manage:   Connect to qemu monitor of the builder."
    "${ECHO[@]}" "quit:     Quit all existing processes like qemu and/or virtiofsd."
    "${ECHO[@]}" "cleanup:  Cleanup data generated for running vm."
    "${ECHO[@]}"
    "${ECHO[@]}"
    "${ECHO[@]}" "Environment Variables:"
    "${ECHO[@]}"
    "${ECHO[@]}" "SUDO:             Set program to run commands as root."
    "${ECHO[@]}" "                  Default value: sudo"
    "${ECHO[@]}" "                  Current value: ${SUDO[*]}"
    "${ECHO[@]}" "DATA_DIR:         Set where to storage data of vm. It may eat so much space."
    "${ECHO[@]}" "                  Default value: $SCRIPT_DIR"
    "${ECHO[@]}" "                  Current value: $DATA_DIR"
    "${ECHO[@]}" "XDG_RUNTIME_DIR:  Set where to storate runtime data of vm like unix domain sockets."
    "${ECHO[@]}" "                  It should be set by logind so there is no default value for it."
    "${ECHO[@]}" "                  Current value: $XDG_RUNTIME_DIR"
    "${ECHO[@]}" "TARGET_ARCH:      The architecture of vm."
    "${ECHO[@]}" "                  Default value: $("${UNAME[@]}" -m)"
    "${ECHO[@]}" "                  Current value: $TARGET_ARCH"
    "${ECHO[@]}"
    "${ECHO[@]}"
    "${ECHO[@]}" "Recommended workflow:"
    "${ECHO[@]}"
    "${ECHO[@]}" "$SCRIPT_NAME create"
    "${ECHO[@]}" "$SCRIPT_NAME launch"
    "${ECHO[@]}" "$SCRIPT_NAME shell"
    "${ECHO[@]}" "  # systemctl start builder"
    "${ECHO[@]}" "# Press Ctrl+Q to leave the shell."
    "${ECHO[@]}" "# Wait until it needs to be saved."
    "${ECHO[@]}" "$SCRIPT_NAME manage"
    "${ECHO[@]}" "  (qemu) stop"
    "${ECHO[@]}" "  (qemu) savevm tag"
    "${ECHO[@]}" "  (qemu) quit"
    "${ECHO[@]}" "$SCRIPT_NAME quit"
    "${ECHO[@]}" "# Wait until it needs to be started again."
    "${ECHO[@]}" "$SCRIPT_NAME launch"
    "${ECHO[@]}" "$SCRIPT_NAME manage"
    "${ECHO[@]}" "  (qemu) loadvm tag"
    "${ECHO[@]}" "  (qemu) cont"
    "${ECHO[@]}" "# Press Ctrl+Q to leave the shell."
    "${ECHO[@]}" "# Wait until it needs to be saved again and do same thing to save and quit it."
    "${ECHO[@]}" "# Repeat until it finishes its work."
    "${ECHO[@]}" "$SCRIPT_NAME shell"
    "${ECHO[@]}" "  # systemctl poweroff"
    "${ECHO[@]}" "$SCRIPT_NAME quit"
    "${ECHO[@]}" "# You can remove the builder now."
    "${ECHO[@]}"
    "${ECHO[@]}"
}

command="$1"
if [[ "$(type -t "__${command}_qemu")" == "function" ]]
then
    shift 1
    "__${command}_qemu" "$@"
else
    if [[ -n "$command" ]]
    then
        "${ECHO[@]}" "Unsupported command $command."
        "${ECHO[@]}"
    else
        "${ECHO[@]}" "You must provide a command."
    fi
    __help_qemu
fi
