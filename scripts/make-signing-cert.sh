#!/bin/sh
# Creates a self-signed code signing certificate in the login keychain.
# macOS ties Accessibility permission to the app's signature. With an ad-hoc
# signature that changes on every build; with this certificate it stays stable.
set -eu

NAME="${1:-Jispr Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "Certificate '$NAME' already exists in the login keychain."
    exit 0
fi

cat > "$TMP/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF

echo "Creating key and certificate..."
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -config "$TMP/openssl.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -name "$NAME" -passout pass:jispr -out "$TMP/cert.p12"

echo "Importing into login keychain..."
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P jispr \
    -T /usr/bin/codesign -T /usr/bin/security >/dev/null

echo "Trusting it for code signing (macOS asks for your password)..."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
    echo "Done. Identity '$NAME' is ready."
else
    echo "The identity was imported but is not listed as valid. Check Keychain Access." >&2
    exit 1
fi
