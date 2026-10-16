#!/bin/sh
# 01_prepare.sh - Prépare la VM : image cloud vérifiée, clé SSH, config cloud-init durcie.
# Usage : ./01_prepare.sh <user_camarade> <fichier_cle_publique_camarade>
set -eu

WORKDIR="${WORKDIR:-$HOME/vm}"
BASE_URL="${BASE_URL:-https://cloud-images.ubuntu.com/noble/current}"
IMG_NAME="${IMG_NAME:-noble-server-cloudimg-amd64.img}"

die() { printf 'Erreur : %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "commande manquante : $1"; }

[ "$#" -eq 2 ] || die "usage : $0 <user_camarade> <fichier_cle_publique_camarade>"
FRIEND_USER="$1"
FRIEND_KEY_FILE="$2"

case "$FRIEND_USER" in
    ''|*[!a-z0-9_-]*|[!a-z_]*) die "nom d'utilisateur invalide : $FRIEND_USER" ;;
esac
[ -r "$FRIEND_KEY_FILE" ] || die "clé publique illisible : $FRIEND_KEY_FILE"
FRIEND_KEY="$(head -n 1 "$FRIEND_KEY_FILE")"
case "$FRIEND_KEY" in
    ssh-*|ecdsa-*|sk-*) : ;;
    *) die "$FRIEND_KEY_FILE ne ressemble pas à une clé publique SSH" ;;
esac

need ssh-keygen
need sha256sum
if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL -o "$2" "$1"; }
elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -q -O "$2" "$1"; }
else
    die "curl ou wget requis"
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"

# 1. Téléchargement depuis la source officielle (HTTPS) + vérification SHA256
if [ ! -f "$IMG_NAME" ]; then
    printf 'Téléchargement de %s...\n' "$IMG_NAME"
    fetch "$BASE_URL/$IMG_NAME" "$IMG_NAME.part"
    mv "$IMG_NAME.part" "$IMG_NAME"
fi
fetch "$BASE_URL/SHA256SUMS" SHA256SUMS
grep " \*\{0,1\}$IMG_NAME\$" SHA256SUMS > SHA256SUM.one \
    || die "somme introuvable pour $IMG_NAME"
sha256sum -c SHA256SUM.one || die "somme SHA256 invalide, image rejetée"

# 2. Clé SSH de l'administrateur (aucun mot de passe en SSH)
if [ ! -f id_vm ]; then
    ssh-keygen -q -t ed25519 -N '' -C 'vm-admin' -f id_vm
fi
ADMIN_KEY="$(cat id_vm.pub)"

# 3. Configuration cloud-init
cat > user-data <<EOF
#cloud-config
hostname: vm-tp
ssh_pwauth: false
disable_root: true
users:
  - name: ubuntu
    shell: /bin/bash
    groups: [sudo]
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - ${ADMIN_KEY}
  - name: ${FRIEND_USER}
    shell: /bin/bash
    lock_passwd: true
    ssh_authorized_keys:
      - ${FRIEND_KEY}
      - ${ADMIN_KEY}
write_files:
  - path: /etc/ssh/sshd_config.d/00-hardening.conf
    permissions: '0644'
    content: |
      PermitRootLogin no
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PubkeyAuthentication yes
runcmd:
  - systemctl restart ssh || systemctl restart sshd
EOF

cat > meta-data <<EOF
instance-id: vm-tp-$(date +%s)
local-hostname: vm-tp
EOF

# 4. Création de l'ISO "seed" (label cidata)
if command -v cloud-localds >/dev/null 2>&1; then
    cloud-localds seed.iso user-data meta-data
elif command -v genisoimage >/dev/null 2>&1; then
    genisoimage -quiet -output seed.iso -volid cidata -joliet -rock user-data meta-data
elif command -v xorriso >/dev/null 2>&1; then
    xorriso -as mkisofs -quiet -o seed.iso -V cidata -J -r user-data meta-data
else
    die "installez cloud-localds, genisoimage ou xorriso"
fi

printf '\nPréparation terminée dans %s\n' "$WORKDIR"
printf 'Lancez ensuite : ./02_run.sh\n'
