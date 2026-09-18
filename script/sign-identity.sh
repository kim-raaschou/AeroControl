#!/bin/bash
#
# Create the self-signed "AeroControl Dev" code-signing certificate, once per machine.
#
# macOS ties the Screen Recording grant to the signing identity; an ad-hoc signature is a
# new identity on every build, so previews would ask for the grant again after each
# `make install` and every `brew upgrade`. This certificate is the same one each time.
# No trust settings are needed — it only has to be stable. `make install` picks it up when
# present, `script/release.sh` requires it.
#
# After switching signatures, re-grant Screen Recording once (System Settings > Privacy &
# Security > Screen & System Audio Recording) and relaunch AeroControl.

set -euo pipefail
NAME="AeroControl Dev"

if security find-identity -p codesigning 2>/dev/null | grep -q "\"${NAME}\""; then
    echo "\"${NAME}\" is already in the keychain."
    exit 0
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cd "$T"
printf '[req]\ndistinguished_name=dn\nx509_extensions=v3\nprompt=no\n[dn]\nCN=%s\n[v3]\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nbasicConstraints=critical,CA:false\n' "$NAME" > ext.cnf
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -keyout key.pem -out cert.pem -config ext.cnf 2>/dev/null
openssl pkcs12 -export -inkey key.pem -in cert.pem -name "$NAME" -out dev.p12 -passout pass:x
security import dev.p12 -k ~/Library/Keychains/login.keychain-db -P x -T /usr/bin/codesign
echo "Created \"${NAME}\". Run make install, then grant Screen Recording once."
