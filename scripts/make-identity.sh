#!/usr/bin/env bash
#
# make-identity.sh — create the code-signing identity, once.
#
# A self-signed certificate with a **stable** common name. Stability is the
# whole point: macOS ties granted permissions to the signing identity, so an
# identity that changes on every build revokes them on every update. Ad-hoc
# signing does exactly that, which is why build.sh has no ad-hoc fallback.
#
# The certificate lives in the login keychain and never in the repository.
# Run this once per machine; `security` will ask for your login password.
#
#   ./scripts/make-identity.sh
#
set -euo pipefail

NAME="${VIBEBUDDY_SIGN_IDENTITY:-VibeBuddy Self-Signed}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if security find-certificate -c "$NAME" >/dev/null 2>&1; then
    echo "✓ « $NAME » existe déjà, rien à faire."
    exit 0
fi

echo "▸ génération d'un certificat auto-signé « $NAME »"

# `codesign` refuses a certificate without the code-signing extended key usage,
# and macOS refuses one without basicConstraints. Both go in the extension file.
cat > "$WORK/openssl.cnf" <<CNF
[ req ]
distinguished_name = dn
prompt = no
x509_extensions = codesign

[ dn ]
CN = $NAME

[ codesign ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/openssl.cnf" \
    -keyout "$WORK/identity.key" \
    -out "$WORK/identity.crt" 2>/dev/null

# `security` cannot verify a PKCS#12 sealed by OpenSSL 3's defaults — it fails
# with "MAC verification failed during PKCS12 import (wrong password?)" even
# when the password is right. The legacy algorithms below are what the keychain
# understands, and the passphrase is non-empty because an empty one hits the
# same path.
PASS="vibebuddy-import"
openssl pkcs12 -export -legacy \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 \
    -inkey "$WORK/identity.key" \
    -in "$WORK/identity.crt" \
    -name "$NAME" \
    -passout "pass:$PASS" \
    -out "$WORK/identity.p12"

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$PASS" \
    -T /usr/bin/codesign -T /usr/bin/security

# Lets codesign use the key without asking every time. It needs the login
# password, so it only runs when one is supplied — otherwise it blocks on an
# interactive prompt, which is a hang in CI and a mystery locally.
if [ -n "${KEYCHAIN_PASSWORD:-}" ]; then
    security set-key-partition-list -S apple-tool:,apple: -s \
        -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 ||
        echo "  (set-key-partition-list a échoué, codesign demandera une autorisation)"
else
    echo "  KEYCHAIN_PASSWORD non fourni : macOS demandera une autorisation à la"
    echo "  première signature. Réponds « Toujours autoriser »."
fi

# Trust it for code signing, or `codesign` never sees it as an identity.
# `trustRoot`, not `trustAsRoot`: the certificate signs itself. And no `-d`,
# which would write to the admin store and ask for an administrator password.
security add-trusted-cert -r trustRoot -p codeSign \
    -k "$KEYCHAIN" "$WORK/identity.crt" 2>/dev/null ||
    echo "  (add-trusted-cert a échoué : la signature sera refusée, relance à la main)"

security find-identity -v -p codesigning | grep -q "$NAME" ||
    { echo "✗ le certificat est importé mais n'est pas une identité de signature." >&2; exit 1; }

echo "✓ identité « $NAME » installée dans le trousseau de session."
echo "  Elle est valable 10 ans et ne doit jamais changer : c'est ce qui garde"
echo "  les autorisations accordées d'une version à l'autre."
