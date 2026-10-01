# FortiGate IPsec VPN on Linux (Docker)

Connect to a FortiGate VPN using **IPsec + PSK + XAuth + email OTP** in a container.
No host installation of FortiClient or strongSwan is required: the image builds strongSwan 6.0.5 with
an [email OTP patch](src/xauth-email-token.patch).

## Quick start

1. **Create your configuration** (copy the examples and fill in the details provided by your VPN administrator):
   ```bash
   cp config/ipsec.conf.example    config/ipsec.conf
   cp config/ipsec.secrets.example config/ipsec.secrets
   chmod 600 config/ipsec.secrets
   ```
   - `ipsec.conf`: gateway IP, username, and profile name (`conn ...`).
   - `ipsec.secrets`: PSK and password for each user.
2. **Name your profiles** using the `conn` blocks in `ipsec.conf` (the example includes `company-full` and `company-split`).
3. **Stop strongSwan on the host** if it is running, to avoid conflicts on ports 500/4500: `sudo ipsec stop`
4. **Connect**:
   ```bash
   docker compose run --rm vpn <connection-name>     # example: docker compose run --rm vpn company-full
   ```
   When `OTP code (from email):` appears, check your email and enter the code **within about 60 seconds**.
   Once you see `✓ connected`, you are connected. **Press Ctrl+C to disconnect.**

The first `run` builds the image, which takes a few minutes.

## Verify that traffic goes through the VPN

```bash
curl https://ifconfig.me     # should show the gateway's IP, not your ISP's IP
```
(This only applies to a full tunnel with `rightsubnet=0.0.0.0/0`. For a split tunnel, try accessing an internal resource.)

## Project structure

| Path | Purpose |
|---|---|
| `config/` | Your configuration and secrets, mounted into the container (not included in the image) |
| `docker-compose.yml` | A single `vpn` service; pass the `conn` name at runtime and run only one VPN at a time |
| `vpn.sh` | Entrypoint: starts charon, prompts for the OTP, and keeps the connection alive |
| `Dockerfile` | Builds strongSwan with the patch; the final image is approximately 110 MB |
| `src/` | OTP patch (from `north3rnlights/strongswan-fortigate-email-2fa`) |
| `backup/` | Legacy scripts for running directly on the host, kept locally for reference and excluded from Git |

## Add a new profile

1. Add a `conn <name>` block to `config/ipsec.conf` and a `<user> : XAUTH "..."` line to `config/ipsec.secrets`.
2. Run `docker compose run --rm vpn <name>`. No changes to `docker-compose.yml` are needed.

## Troubleshooting

| Symptom | Common cause or action |
|---|---|
| `failed before OTP` | Incorrect PSK, username/password, or encryption settings (`ike=`/`esp=`) that do not match the gateway. Check the 20 log lines printed. |
| `no OTP challenge` | The gateway did not send an OTP challenge: the profile is incorrect or email 2FA is not enabled for the account. |
| Connection fails after entering the OTP | The code was entered too slowly (more than about 60 seconds) and was ignored. Run again to receive a new code. |
| Connected, but the public IP is still your ISP's IP | Check `vpn.sh` (the NAT bypass rule) and whether the Docker bridge subnet overlaps the VPN's virtual IP range. |
| Ports 500/4500 are already in use | Run `sudo ipsec stop` on the host. |

## Notes

- The container uses `network_mode: host` with `NET_ADMIN`, so the VPN applies to **the entire host**.
- Each connection attempt triggers an OTP email; avoid repeated attempts unless needed.
- Never commit `config/ipsec.secrets`.
