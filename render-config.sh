#!/usr/bin/env sh
set -eu

case "$0" in
  */*) SCRIPT_REL_DIR=${0%/*} ;;
  *) SCRIPT_REL_DIR=. ;;
esac

SCRIPT_DIR=$(CDPATH= cd -- "$SCRIPT_REL_DIR" && pwd)

if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "$SCRIPT_DIR/.env"
  set +a
fi

: "${HOST_IP:?Set HOST_IP in .env}"
: "${SERVER_NAME:?Set SERVER_NAME in .env}"
: "${LIVEKIT_KEY:?Set LIVEKIT_KEY in .env}"
: "${LIVEKIT_SECRET:?Set LIVEKIT_SECRET in .env}"

DATA_DIR="${DATA_DIR:-/var/lib/conduit-matrix}"
CERT_DAYS="${CERT_DAYS:-3650}"
CERT_SUBJECT="${CERT_SUBJECT:-/CN=$HOST_IP}"
CINNY_PORT="${CINNY_PORT:-6168}"
OUTPUT_DIR="${1:-$DATA_DIR}"

CONFIG_DIR="$OUTPUT_DIR/config"
CERT_DIR="$OUTPUT_DIR/certs"
mkdir -p "$CONFIG_DIR" "$CERT_DIR" "$OUTPUT_DIR/conduit"

replace() {
  src="$1"
  dst="$2"
  tmp="$dst.tmp"
  sed \
    -e "s|__HOST_IP__|$HOST_IP|g" \
    -e "s|__SERVER_NAME__|$SERVER_NAME|g" \
    -e "s|__LIVEKIT_KEY__|$LIVEKIT_KEY|g" \
    -e "s|__LIVEKIT_SECRET__|$LIVEKIT_SECRET|g" \
    -e "s|__CINNY_PORT__|$CINNY_PORT|g" \
    "$src" > "$tmp"
  mv "$tmp" "$dst"
}

if [ -n "${TURN_SECRET:-}" ]; then
  TURN_BLOCK=$(printf '%s\n' \
    "turn_uris = [\"turn:$HOST_IP:3478?transport=udp\", \"turn:$HOST_IP:3478?transport=tcp\", \"stun:stun.l.google.com:19302\"]" \
    "turn_secret = \"$TURN_SECRET\"" \
    "turn_ttl = ${TURN_TTL:-86400}")
else
  TURN_BLOCK="# No TURN server configured."
fi

replace "$SCRIPT_DIR/templates/nginx.conf.template" "$CONFIG_DIR/nginx.conf"
replace "$SCRIPT_DIR/templates/livekit.yaml.template" "$CONFIG_DIR/livekit.yaml"
replace "$SCRIPT_DIR/templates/cinny-config.json.template" "$CONFIG_DIR/cinny-config.json"
replace "$SCRIPT_DIR/templates/trust-index.html.template" "$CERT_DIR/trust-index.html"
replace "$SCRIPT_DIR/templates/install-matrix-ca.ps1.template" "$CERT_DIR/install-matrix-ca.ps1"
replace "$SCRIPT_DIR/templates/install-matrix-ca.cmd.template" "$CERT_DIR/install-matrix-ca.cmd"
cp "$SCRIPT_DIR/templates/cinny-patch-http-voice.sh" "$CONFIG_DIR/cinny-patch-http-voice.sh"
chmod 0755 "$CONFIG_DIR/cinny-patch-http-voice.sh"
cp "$SCRIPT_DIR/templates/nginx-main.conf" "$CONFIG_DIR/nginx-main.conf"

sed \
  -e "s|__HOST_IP__|$HOST_IP|g" \
  -e "s|__SERVER_NAME__|$SERVER_NAME|g" \
  -e "s|__LIVEKIT_KEY__|$LIVEKIT_KEY|g" \
  -e "s|__LIVEKIT_SECRET__|$LIVEKIT_SECRET|g" \
  "$SCRIPT_DIR/templates/conduit.toml.template" \
  | awk -v block="$TURN_BLOCK" '{ if ($0 == "__TURN_BLOCK__") print block; else print }' \
  > "$CONFIG_DIR/conduit.toml"

if [ -f "$SCRIPT_DIR/certs/neura-matrix-ca.crt" ]; then
  cp "$SCRIPT_DIR/certs/neura-matrix-ca.crt" "$CERT_DIR/neura-matrix-ca.crt"
fi

if [ ! -f "$CERT_DIR/matrix.crt" ] || [ ! -f "$CERT_DIR/matrix.key" ]; then
  if ! command -v openssl >/dev/null 2>&1; then
    echo "openssl is required to generate the Matrix TLS certificate." >&2
    exit 1
  fi

  echo "Generating a self-signed certificate for $HOST_IP..."
  openssl req -x509 -newkey rsa:2048 -sha256 -days "$CERT_DAYS" -nodes \
    -keyout "$CERT_DIR/matrix.key" \
    -out "$CERT_DIR/matrix.crt" \
    -subj "$CERT_SUBJECT" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign,digitalSignature" \
    -addext "subjectAltName=IP:$HOST_IP"
  chmod 600 "$CERT_DIR/matrix.key"
  cp "$CERT_DIR/matrix.crt" "$CERT_DIR/neura-matrix-ca.crt"
fi

echo "Wrote generated config to $CONFIG_DIR"

