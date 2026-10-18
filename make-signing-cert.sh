#!/bin/sh
# One-time: creates a self-signed "Lilith Code Signing" identity in the login keychain.
# build.sh signs with it, so macOS keeps Lilith's Accessibility permission across rebuilds.
set -e
NAME="Lilith Code Signing"
if security find-identity -p codesigning | grep -q "\"$NAME\""; then echo "$NAME already exists"; exit 0; fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CFG
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cfg" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PW=$(openssl rand -hex 16)
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" -passout "pass:$PW" -out "$TMP/id.p12"
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PW" -T /usr/bin/codesign
echo "Created $NAME. Rebuild with ./build.sh --install, then grant Accessibility once more."
