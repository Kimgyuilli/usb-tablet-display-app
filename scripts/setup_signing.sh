#!/bin/bash
# One-time setup: create a stable, self-signed code-signing identity for
# local builds of this fork.
#
#   scripts/setup_signing.sh
#
# Why: ad-hoc signatures change on every build, so macOS forgets the Screen
# Recording / Accessibility grants after each reinstall. A fixed certificate
# gives every build the same designated requirement, so grants persist.
#
# The identity lives in its own keychain (not your login keychain). The
# keychain password below only protects this local, self-signed key — it is
# not a secret worth guarding and grants no access to anything else.
set -euo pipefail

IDENTITY="SideScreen Local Signing"
KEYCHAIN="$HOME/Library/Keychains/sidescreen-signing.keychain-db"
KEYCHAIN_PASSWORD="sidescreen-local"

if security find-certificate -c "$IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "✓ '$IDENTITY' already exists in $(basename "$KEYCHAIN")"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Creating keychain $(basename "$KEYCHAIN")..."
if [ ! -f "$KEYCHAIN" ]; then
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
fi
security set-keychain-settings "$KEYCHAIN"   # no auto-lock timeout
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

# Add to the user search list (keeping existing keychains) so codesign finds it.
EXISTING=$(security list-keychains -d user | sed -e 's/^ *//' -e 's/"//g')
if ! echo "$EXISTING" | grep -qF "$KEYCHAIN"; then
    # shellcheck disable=SC2086
    security list-keychains -d user -s $EXISTING "$KEYCHAIN"
fi

echo "Generating certificate '$IDENTITY'..."
cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
# macOS can only read PKCS#12 with legacy (SHA1/3DES) MACs. OpenSSL 3 needs
# -legacy for that; LibreSSL already defaults to it and rejects the flag.
openssl pkcs12 -export -legacy -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$IDENTITY" -passout pass:temp -out "$WORK/identity.p12" 2>/dev/null \
  || openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$IDENTITY" -passout pass:temp -out "$WORK/identity.p12"

security import "$WORK/identity.p12" -k "$KEYCHAIN" -P temp -T /usr/bin/codesign >/dev/null
# Let codesign use the key without a GUI prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

echo "✓ Created '$IDENTITY'"
security find-identity -p codesigning "$KEYCHAIN"
