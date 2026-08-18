#!/usr/bin/env sh
set -eu
HERE=$(CDPATH= cd -- "${0%/*}" && pwd)
CERT="$HERE/../certs/neura-matrix-ca.crt"
if [ ! -f "$CERT" ]; then
  echo "Missing $CERT" >&2
  exit 1
fi

if command -v security >/dev/null 2>&1; then
  echo "Installing the Matrix local certificate into your macOS login keychain..."
  security add-trusted-cert -r trustRoot -k "$HOME/Library/Keychains/login.keychain-db" "$CERT"
  echo "Done. Close Cinny completely, then sign in again with http://192.168.196.65:6167"
  exit 0
fi

if command -v certutil >/dev/null 2>&1; then
  echo "Installing the Matrix local certificate into the current NSS store if present..."
  certutil -d sql:"$HOME/.pki/nssdb" -A -t "C,," -n "Neura Matrix Local CA" -i "$CERT" || true
fi

if command -v update-ca-certificates >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
  cp "$CERT" /usr/local/share/ca-certificates/neura-matrix-ca.crt
  update-ca-certificates
  echo "Installed system-wide."
  exit 0
fi

echo "Certificate saved at $CERT"
echo "Import it into your OS trust store, then reopen Cinny and sign in with http://192.168.196.65:6167"

