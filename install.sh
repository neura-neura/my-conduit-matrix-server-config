#!/usr/bin/env sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    exec sudo "$0" "$@"
  fi
  echo "Please run this installer as root." >&2
  exit 1
fi

case "$0" in
  */*) SOURCE_REL_DIR=${0%/*} ;;
  *) SOURCE_REL_DIR=. ;;
esac

SOURCE_DIR=$(CDPATH= cd -- "$SOURCE_REL_DIR" && pwd)
ENV_FILE="$SOURCE_DIR/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Missing .env." >&2
  echo "Create it first: cp .env.example .env" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_FILE"
set +a

SERVICE_NAME="${SERVICE_NAME:-conduit-matrix}"
INSTALL_DIR="${INSTALL_DIR:-/opt/conduit-matrix}"
DATA_DIR="${DATA_DIR:-/var/lib/conduit-matrix}"

: "${HOST_IP:?Set HOST_IP in .env}"
: "${SERVER_NAME:?Set SERVER_NAME in .env}"
: "${LIVEKIT_KEY:?Set LIVEKIT_KEY in .env}"
: "${LIVEKIT_SECRET:?Set LIVEKIT_SECRET in .env}"

case "$SERVICE_NAME" in
  *[!A-Za-z0-9_.@-]*|'')
    echo "SERVICE_NAME may only contain letters, numbers, underscore, dot, at-sign, and dash." >&2
    exit 1
    ;;
esac

case "$INSTALL_DIR" in
  /*) ;;
  *)
    echo "INSTALL_DIR must be an absolute path." >&2
    exit 1
    ;;
esac

case "$DATA_DIR" in
  /*) ;;
  *)
    echo "DATA_DIR must be an absolute path." >&2
    exit 1
    ;;
esac

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed or not in PATH." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose v2 is required. The command 'docker compose' is not available." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "openssl is required to generate the Matrix TLS certificate." >&2
  exit 1
fi

DOCKER_BIN=$(command -v docker)
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

echo "Installing Conduit Matrix project into $INSTALL_DIR"
mkdir -p "$INSTALL_DIR/templates" "$DATA_DIR/config" "$DATA_DIR/certs" "$DATA_DIR/conduit"

copy_file() {
  src="$1"
  dst="$2"
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    return 0
  fi
  cp "$src" "$dst"
}

copy_file "$SOURCE_DIR/compose.yaml" "$INSTALL_DIR/compose.yaml"
copy_file "$SOURCE_DIR/wait-for-ip.sh" "$INSTALL_DIR/wait-for-ip.sh"
copy_file "$SOURCE_DIR/render-config.sh" "$INSTALL_DIR/render-config.sh"
copy_file "$SOURCE_DIR/templates/nginx-main.conf" "$INSTALL_DIR/templates/nginx-main.conf"
copy_file "$SOURCE_DIR/templates/nginx.conf.template" "$INSTALL_DIR/templates/nginx.conf.template"
copy_file "$SOURCE_DIR/templates/conduit.toml.template" "$INSTALL_DIR/templates/conduit.toml.template"
copy_file "$SOURCE_DIR/templates/livekit.yaml.template" "$INSTALL_DIR/templates/livekit.yaml.template"
copy_file "$ENV_FILE" "$INSTALL_DIR/.env"
chmod 0755 "$INSTALL_DIR/wait-for-ip.sh" "$INSTALL_DIR/render-config.sh"

"$INSTALL_DIR/render-config.sh" "$DATA_DIR"

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Conduit Matrix homeserver with Element Call / MatrixRTC (Docker Compose)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$INSTALL_DIR/.env
TimeoutStartSec=600
TimeoutStopSec=120
Restart=on-failure
RestartSec=15
ExecStartPre=$INSTALL_DIR/wait-for-ip.sh
ExecStartPre=$INSTALL_DIR/render-config.sh $DATA_DIR
ExecStart=$DOCKER_BIN compose --env-file $INSTALL_DIR/.env -f $INSTALL_DIR/compose.yaml up -d --remove-orphans
ExecStop=$DOCKER_BIN compose --env-file $INSTALL_DIR/.env -f $INSTALL_DIR/compose.yaml down

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "$SERVICE_NAME.service"

echo "Pulling container images..."
"$DOCKER_BIN" compose --env-file "$INSTALL_DIR/.env" -f "$INSTALL_DIR/compose.yaml" pull

echo "Starting $SERVICE_NAME.service..."
systemctl restart "$SERVICE_NAME.service"

echo
systemctl --no-pager --full status "$SERVICE_NAME.service" | sed -n '1,80p'

echo
echo "Installed successfully."
echo "Homeserver:"
echo "  http://$SERVER_NAME"
echo "  https://$SERVER_NAME"
echo
echo "Optional Cinny web client:"
echo "  http://$HOST_IP:${CINNY_PORT:-6168}"
echo
echo "Create the first account from a Matrix client, then open a voice room."
echo "Cinny Desktop works over HTTP. Element Desktop may still refuse MatrixRTC"
echo "on a Conduit homeserver even when discovery is present."
