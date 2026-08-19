# Conduit Matrix VPN Docker Starter

Run a self-hosted [Conduit](https://conduit.rs) Matrix homeserver with Docker Compose, bound to a VPN address such as ZeroTier, Tailscale, WireGuard, or any other private interface.

This stack publishes the MatrixRTC discovery used by Cinny, Element Desktop, and Element X for continuous voice rooms. Nginx multiplexes HTTP and HTTPS on one Matrix port, LiveKit handles media, and a systemd service waits until the VPN IP exists before starting Docker Compose.

## Important: every Cinny Desktop user must install the certificate

This is the part that will break voice rooms if you skip it. Do not skip it on a new computer.

Chat works over HTTP. Cinny Desktop still re-checks voice rooms over HTTPS after login. That HTTPS check uses this server's local certificate. A new PC will log in and then say:

`Your homeserver does not support calling.`

Fix it once per person. Future installs should only need this:

1. Join the same VPN / ZeroTier network.
2. Open [http://192.168.196.65:6167/trust/](http://192.168.196.65:6167/trust/).
3. Click **One-click Windows installer**, or download and install `neura-matrix-ca.crt`.
4. Fully close Cinny and open it again.
5. Sign in with exactly `http://192.168.196.65:6167`, including `http://`.

Windows one-click installer:

```text
http://192.168.196.65:6167/trust/install-matrix-ca.cmd
```

Or from a clone of this repo:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\trust-matrix-ca.ps1
```

Chinese Windows button names:

- 安装证书 = Install Certificate
- 当前用户 = Current User
- 将所有的证书都放入下列存储 = Place all certificates in the following store
- 受信任的根证书颁发机构 = Trusted Root Certification Authorities
- 是 = Yes
- 完成 = Finish

Do not skip the certificate because "HTTP already works". Login can succeed and voice can still fail.

The optional Cinny web client at `http://192.168.196.65:6168` does not need the certificate.

## What This Installs

- A Conduit homeserver.
- Nginx on one public Matrix port, serving both HTTP and HTTPS.
- LiveKit plus Element's LiveKit JWT service for MatrixRTC / Cinny voice rooms.
- A `/trust/` page that serves the local certificate and a Windows installer.
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
- `openssl`, used once to generate a certificate if none exists yet.
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

That command also enables `conduit-matrix.service`. After a reboot the service waits for your VPN IP and starts Matrix by itself.

Connect a Matrix client to:

```text
http://192.168.196.65:6167
```

An optional Cinny web client is also published at:

```text
http://192.168.196.65:6168
```

## Invite checklist

Send this to every new person:

1. Join the ZeroTier / VPN network.
2. Open `http://192.168.196.65:6167/trust/` and install the certificate. This step is required for Cinny Desktop voice rooms.
3. Install Cinny Desktop.
4. Sign in with `http://192.168.196.65:6167`. The `http://` prefix is required.
5. Join the voice room.

If they type only `192.168.196.65:6167`, Cinny tries HTTPS first and fails.

## iPhone / Element X

Element X on iPhone can log in over HTTP, then fail voice rooms with `MISSING_MATRIX_RTC_TRANSPORT` until it trusts this server's HTTPS certificate.

On the iPhone, in Safari:

1. Open [http://192.168.196.65:6167/trust/](http://192.168.196.65:6167/trust/).
2. Tap **Install on iPhone**.
3. Settings → General → VPN & Device Management → install **Neura Matrix Trust**.
4. Settings → General → About → Certificate Trust Settings → enable Full Trust for **Neura Matrix Local CA**.
5. Force-close Element X and open it again.
6. Sign in with `http://192.168.196.65:6167`.

## Voice Rooms

Cinny voice rooms work on this stack over HTTP after the certificate is trusted.

The installer advertises MatrixRTC discovery here:

```text
http://$SERVER_NAME/.well-known/matrix/client
http://$SERVER_NAME/_matrix/client/v1/rtc/transports
```

Element X and Element Desktop use the same MatrixRTC transport as Cinny. The well-known response must contain only `org.matrix.msc4143.rtc_foci`; do not add the older `m.rtc_foci` field at the same time, because current Element X versions reject duplicate aliases. The homeserver and LiveKit URLs are both HTTPS to avoid mixed-content discovery failures on iPhone.

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
- Change `LIVEKIT_KEY` and `LIVEKIT_SECRET` before exposing the server beyond a private network.
- Existing Conduit data and TLS certificates are reused on reinstall.
- Do not commit your `.env`; it is intentionally ignored by git.
- `certs/neura-matrix-ca.crt` is the public certificate people install. Never commit a `.key` file.

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

Confirm MatrixRTC discovery and the trust page:

```bash
curl -s http://192.168.196.65:6167/.well-known/matrix/client
curl -s http://192.168.196.65:6167/_matrix/client/v1/rtc/transports
curl -sI http://192.168.196.65:6167/trust/
curl -sI http://192.168.196.65:6167/trust/neura-matrix-ca.crt
```

Create the first account from a Matrix client. Registration is enabled by default.

## Reboot Behavior

`install.sh` writes and enables `conduit-matrix.service`. After every boot it:

1. Waits for Docker.
2. Waits until `HOST_IP` appears on a local network interface.
3. Regenerates Nginx, Conduit, and LiveKit config from `.env` if needed.
4. Runs `docker compose up -d`.

If the VPN takes longer than `WAIT_TIMEOUT_SECONDS`, systemd retries the service every 15 seconds.

## Updating

```bash
cd /opt/conduit-matrix
docker compose pull
sudo systemctl restart conduit-matrix.service
```

Your homeserver database stays in `DATA_DIR`. Existing TLS certificates are kept unless you delete them yourself.

## Troubleshooting

If a new Cinny install can log in but voice says the homeserver does not support calling:

1. Open `http://$SERVER_NAME/trust/`.
2. Install `neura-matrix-ca.crt`.
3. Fully close Cinny.
4. Sign in again with `http://$SERVER_NAME`.

If a new Cinny install cannot find the homeserver:

- Make sure ZeroTier is connected first.
- Type `http://$SERVER_NAME` exactly, including `http://`.
- Do not type only the IP and port.

If Element X or Element Desktop shows `MISSING_MATRIX_RTC_TRANSPORT`, fully close the app and reopen it after the server configuration changes so cached homeserver discovery is discarded. Confirm that the response contains `org.matrix.msc4143.rtc_foci` and does not contain `m.rtc_foci`.

## Uninstall

```bash
sudo systemctl disable --now conduit-matrix.service
sudo rm -f /etc/systemd/system/conduit-matrix.service
sudo systemctl daemon-reload
cd /opt/conduit-matrix
docker compose down
```

Remove the data directory only if you want to permanently delete the homeserver:

```bash
sudo rm -rf /var/lib/conduit-matrix
```

## License

MIT

