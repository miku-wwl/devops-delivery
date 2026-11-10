#!/usr/bin/env bash
# OpenBao's unseal key, encrypted, outside the WSL VM - to be run by the OWNER (incident E11-1, action
# item 2). Never prints the key.
#   bash v2/platform/secrets/openbao-key-backup.sh <staging directory outside WSL>
#   e.g. bash v2/platform/secrets/openbao-key-backup.sh /mnt/c/Users/<you>/lab-key-staging
# 1. encrypts ~/.lab-secrets/v2/openbao/init.json with gpg (AES-256, symmetric) - you type a passphrase
#    (twice); it is not stored anywhere, not cached by gpg-agent;
# 2. decrypts the result again (you type the passphrase a third time) and compares it with the key file
#    byte for byte (cmp) - prints "verified", never the content;
# 3. prints the encrypted file's name and SHA-256 for your records.
# Then, yourself: move the .gpg file into independent encrypted storage (a password-manager attachment,
# an encrypted external drive), store the passphrase separately (password manager), and delete the
# staging copy. Windows does not enforce the mode bits of /mnt/c - the protection is the encryption.
# Restore (only into an empty slot - openbao-init.sh refuses to replace an existing key file):
#   gpg --decrypt <file>.gpg > ~/.lab-secrets/v2/openbao/init.json && chmod 400 ~/.lab-secrets/v2/openbao/init.json
# Test only (a dummy key, never the real one): KEYFILE=<dummy> TEST_PASSFILE=<file> ... runs unattended.
set -euo pipefail
SRC=${KEYFILE:-$HOME/.lab-secrets/v2/openbao/init.json}
DEST=${1:?usage: openbao-key-backup.sh <staging directory outside WSL>}
command -v gpg >/dev/null || { echo "gpg is missing (sudo apt-get install gnupg)"; exit 1; }
[ -s "$SRC" ] || { echo "no key file at $SRC"; exit 1; }
jq -e '(.unseal_keys_b64[0] | length > 0) and (.root_token | length > 0)' "$SRC" >/dev/null || { echo "$SRC is not a key file"; exit 1; }
mkdir -p "$DEST"
umask 077
OUT="$DEST/openbao-init-$(date -u +%Y%m%dT%H%M%SZ).json.gpg"
G=(--no-symkey-cache --quiet)
[ -n "${TEST_PASSFILE:-}" ] && G+=(--batch --pinentry-mode loopback --passphrase-file "$TEST_PASSFILE")
gpg "${G[@]}" --symmetric --cipher-algo AES256 --output "$OUT" "$SRC"
if gpg "${G[@]}" --decrypt "$OUT" | cmp -s - "$SRC"; then
  echo "verified: the encrypted copy decrypts to exactly the key file"
else
  echo "VERIFICATION FAILED - keep the original, delete $OUT"; exit 1
fi
echo "written: $OUT"
echo "sha256 of the encrypted file: $(sha256sum "$OUT" | cut -d' ' -f1)"
