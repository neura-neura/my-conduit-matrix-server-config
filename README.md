# Conduit Matrix VPN Docker Starter

Run a self-hosted [Conduit](https://conduit.rs) Matrix homeserver with Docker Compose, bound to a VPN address such as ZeroTier, Tailscale, WireGuard, or any other private interface.

This stack also publishes the MatrixRTC discovery that Cinny needs for continuous voice rooms. Nginx multiplexes HTTP and HTTPS on one Matrix port, LiveKit handles media, and a systemd service waits until the VPN IP exists before starting Docker Compose. Without that wait, Docker can fail after a reboot with errors like `cannot assign requested address`.

## What This Installs

- A Conduit homeserver.
- Nginx on one public Matrix port, serving both HTTP and HTTPS.
- LiveKit plus Element's LiveKit JWT service for MatrixRTC / Cinny voice rooms.
- An optional Cinny web client.
- Persistent homeserver data on the host.
- A systemd service that starts everything automatically after reboot.
- A startup guard that waits for your VPN/private IP before binding ports.

The default ports are:

- `6167/tcp` for Matrix HTTP and HTTPS.
- `8448/tcp` for optional federation TLS.
- `6168/tcp` for the optional Cinny web client.
- `7881/tcp` and `7882/udp` for LiveKit media.

## Requirements

- A Linux server with systemd.
- Docker Engine.
- Docker Compose v2, available as `docker compose`.
- `openssl`, used once to generate a self-signed certificate if none exists yet.
- A VPN/private IP already configured on the server.

This was designed for VPN-only Matrix hosting. It works well with ZeroTier, but it is not ZeroTier-specific.

## Quick Start

Clone the repository on your server:

```bash
git clone https://github.com/neura-neura/my-conduit-matrix-server-config.git
cd my-conduit-matrix-server-config
```

Create your local config:

```bash
cp .env.example .env
nano .env
```

Set the server identity and the IP that belongs to the server's VPN interface:

```env
SERVER_NAME=192.168.196.65:6167
HOST_IP=192.168.196.65
```

`SERVER_NAME` is the Matrix homeserver name. Changing it later creates a different server identity, so set it correctly before the first start.

Install and start the service:

```bash
sudo ./install.sh
```

That command also enables `conduit-matrix.service`. After a reboot the service waits for your VPN IP and starts Matrix by itself. You do not need to add autostart by hand.

Connect a Matrix client to:

```text
http://192.168.196.65:6167
```

Replace that address with your own `http://$SERVER_NAME`.

Cinny Desktop works over HTTP. Other people on the same VPN can install stock Cinny, join ZeroTier, and use the same homeserver address. No custom Cinny build is required.

An optional Cinny web client is also published at:

```text
http://192.168.196.65:6168
```

## Voice Rooms

Cinny voice rooms work on this stack over HTTP. The installer advertises MatrixRTC discovery on HTTP only:

```text
http://$SERVER_NAME/.well-known/matrix/client
http://$SERVER_NAME/_matrix/client/v1/rtc/transports
```

Use `http://$SERVER_NAME` in Cinny, including the `http://` prefix. If someone types only `192.168.196.65:6167`, Cinny first tries HTTPS. That path uses a self-signed certificate and a fresh Cinny install will refuse it.

The optional Cinny web client is preconfigured with the HTTP homeserver address so people do not have to guess the URL.

Element Desktop can still refuse Element Call on Conduit with `MISSING_MATRIX_RTC_TRANSPORT`, even when the same discovery works in Cinny. This repo does not patch Element. Use Cinny for continuous voice rooms.

Sliding Sync is not required.

## Configuration

Edit `.env` before running `install.sh`.

```env
SERVICE_NAME=conduit-matrix
INSTALL_DIR=/opt/conduit-matrix
COMPOSE_PROJECT_NAME=conduit-matrix

SERVER_NAME=192.168.196.65:6167
HOST_IP=192.168.196.65
MATRIX_PORT=6167
FEDERATION_PORT=8448
CINNY_PORT=6168

LIVEKIT_TCP_PORT=7881
LIVEKIT_UDP_PORT=7882
LIVEKIT_KEY=devkey
LIVEKIT_SECRET=secretsecretsecretsecretsecretsecret

DATA_DIR=/var/lib/conduit-matrix
```

Important notes:

- `HOST_IP` must be an IP address that exists on the server, not on your client machine.
- Use the VPN/private IP if you only want Matrix reachable through the VPN.
- Use `0.0.0.0` only if you intentionally want to bind on all interfaces.
- Change `LIVEKIT_KEY` and `LIVEKIT_SECRET` before exposing the server beyond a private network.
- Leave `TURN_SECRET` empty unless you already run a TURN server.
- Existing Conduit data and TLS certificates are reused on reinstall.
- Do not commit your `.env`; it is intentionally ignored by git.

## After Installing

Check the service:

```bash
systemctl status conduit-matrix.service
```

Check the containers:

```bash
cd /opt/conduit-matrix
docker compose ps
```

Watch logs:

```bash
docker logs -f conduit
docker logs -f livekit-server
docker logs -f lk-jwt-service
docker logs -f conduit-proxy
```

Confirm MatrixRTC discovery:

```bash
curl -s http://192.168.196.65:6167/.well-known/matrix/client
curl -s http://192.168.196.65:6167/_matrix/client/v1/rtc/transports
```

Create the first account from a Matrix client. Registration is enabled by default.

## Reboot Behavior

`install.sh` writes and enables `conduit-matrix.service`. That service does this after every boot:

1. Waits for Docker.
2. Waits until `HOST_IP` appears on a local network interface.
3. Regenerates Nginx, Conduit, and LiveKit config from `.env` if needed.
4. Runs `docker compose up -d`.

The unit file lives in the repo as `templates/conduit-matrix.service.template`. The installer fills in the install path and copies it to `/etc/systemd/system/conduit-matrix.service`.

This prevents the common reboot failure where Docker starts before the VPN interface is ready.

If the VPN takes longer than `WAIT_TIMEOUT_SECONDS`, systemd retries the service every 15 seconds instead of giving up permanently.

## Updating

Pull the latest images and recreate the containers:

```bash
cd /opt/conduit-matrix
docker compose pull
sudo systemctl restart conduit-matrix.service
```

Your homeserver database stays in `DATA_DIR`. Existing TLS certificates are kept unless you delete them yourself.

## Troubleshooting

If the service does not start, check:

```bash
journalctl -u conduit-matrix.service -b --no-pager
```

If Docker says it cannot bind the address, verify that the IP exists on the server:

```bash
ip -brief addr
```

If a new Cinny install cannot find the homeserver:

- Make sure ZeroTier is connected first.
- Type `http://$SERVER_NAME` exactly, including `http://`.
- Do not type only the IP and port. Cinny will try HTTPS first and fail.
- Close Cinny completely and try again if the first attempt failed.

If clients can reach Matrix but Cinny still says calling is unsupported:

- Make sure the client is using `http://$SERVER_NAME`, not a different host or port.
- Confirm `/.well-known/matrix/client` contains `org.matrix.msc4143.rtc_foci`.
- Confirm `/_matrix/client/v1/rtc/transports` returns a LiveKit transport.
- Sign out and sign back in so the client reloads discovery.

If Matrix starts but a client cannot connect:

- Make sure the client is connected to the same VPN.
- Make sure `HOST_IP` is reachable from the client.
- Give the server 20-60 seconds after boot, especially on slow machines.

If Element Desktop shows `MISSING_MATRIX_RTC_TRANSPORT`, that is expected on Conduit. Use Cinny for voice rooms.

## Uninstall

Stop and disable the systemd service:

```bash
sudo systemctl disable --now conduit-matrix.service
sudo rm -f /etc/systemd/system/conduit-matrix.service
sudo systemctl daemon-reload
```

Remove the containers while keeping data:

```bash
cd /opt/conduit-matrix
docker compose down
```

Remove the data directory only if you want to permanently delete the homeserver:

```bash
sudo rm -rf /var/lib/conduit-matrix
```

## License

MIT
