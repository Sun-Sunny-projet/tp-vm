#!/bin/sh
# 02_run.sh - Lance la VM avec QEMU à partir de l'image cloud Ubuntu préparée.
# Usage : ./02_run.sh
set -eu

WORKDIR="${WORKDIR:-$HOME/vm}"
IMG_NAME="${IMG_NAME:-noble-server-cloudimg-amd64.img}"
DISK_SIZE="${DISK_SIZE:-10G}"
RAM="${RAM:-2048}"
CPUS="${CPUS:-2}"
SSH_PORT="${SSH_PORT:-2222}"

die() { printf 'Erreur : %s\n' "$*" >&2; exit 1; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || die "qemu-system-x86_64 introuvable"
command -v qemu-img >/dev/null 2>&1 || die "qemu-img introuvable"

cd "$WORKDIR" 2>/dev/null || die "$WORKDIR absent, lancez d'abord 01_prepare.sh"
[ -f "$IMG_NAME" ] || die "image $IMG_NAME absente"
[ -f seed.iso ] || die "seed.iso absent, lancez d'abord 01_prepare.sh"

if [ -f vm.pid ] && kill -0 "$(cat vm.pid)" 2>/dev/null; then
    die "la VM tourne déjà (PID $(cat vm.pid))"
fi

if [ ! -f vm.qcow2 ]; then
    qemu-img create -q -f qcow2 -F qcow2 -b "$IMG_NAME" vm.qcow2 "$DISK_SIZE"
fi

# KVM si possible, sinon émulation logicielle (TCG) automatiquement
qemu-system-x86_64 \
    -machine q35,accel=kvm:tcg \
    -cpu max \
    -smp "$CPUS" -m "$RAM" \
    -drive file=vm.qcow2,if=virtio,format=qcow2 \
    -drive file=seed.iso,if=virtio,format=raw,media=cdrom,readonly=on \
    -netdev "user,id=net0,hostfwd=tcp:127.0.0.1:${SSH_PORT}-:22" \
    -device virtio-net-pci,netdev=net0 \
    -display none \
    -serial file:vm-console.log \
    -pidfile vm.pid \
    -daemonize

printf 'VM démarrée (PID %s). Attendez 1 à 3 minutes le premier démarrage.\n' "$(cat vm.pid)"
printf 'Connexion admin    : ssh -i %s/id_vm -p %s ubuntu@127.0.0.1\n' "$WORKDIR" "$SSH_PORT"
printf 'Connexion camarade : ssh -i <sa_cle_privee> -p %s <user>@127.0.0.1\n' "$SSH_PORT"
printf 'Arrêt              : kill $(cat %s/vm.pid)\n' "$WORKDIR"
