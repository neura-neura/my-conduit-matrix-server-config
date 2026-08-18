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

if [ -n "${1:-}" ]; then
  HOST_IP="$1"
fi

: "${HOST_IP:?Set HOST_IP in .env or pass it as the first argument}"

WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-300}"
WAIT_INTERVAL_SECONDS="${WAIT_INTERVAL_SECONDS:-2}"

case "$WAIT_TIMEOUT_SECONDS" in
  ''|*[!0-9]*)
    echo "WAIT_TIMEOUT_SECONDS must be a positive integer" >&2
    exit 2
    ;;
esac

case "$WAIT_INTERVAL_SECONDS" in
  ''|*[!0-9]*)
    echo "WAIT_INTERVAL_SECONDS must be a positive integer" >&2
    exit 2
    ;;
esac

if [ "$WAIT_TIMEOUT_SECONDS" -le 0 ]; then
  echo "WAIT_TIMEOUT_SECONDS must be greater than zero" >&2
  exit 2
fi

if [ "$WAIT_INTERVAL_SECONDS" -le 0 ]; then
  echo "WAIT_INTERVAL_SECONDS must be greater than zero" >&2
  exit 2
fi

if [ "$HOST_IP" = "0.0.0.0" ]; then
  echo "HOST_IP is 0.0.0.0; no specific interface address is required."
  exit 0
fi

elapsed=0

while [ "$elapsed" -lt "$WAIT_TIMEOUT_SECONDS" ]; do
  if ip -o -4 addr show | awk '{print $4}' | cut -d/ -f1 | grep -Fxq "$HOST_IP"; then
    echo "Found host IP $HOST_IP."
    exit 0
  fi

  sleep "$WAIT_INTERVAL_SECONDS"
  elapsed=$((elapsed + WAIT_INTERVAL_SECONDS))
done

echo "Timed out waiting for host IP $HOST_IP after ${WAIT_TIMEOUT_SECONDS}s." >&2
echo "Current IPv4 addresses:" >&2
ip -brief -4 addr >&2 || true
exit 1
