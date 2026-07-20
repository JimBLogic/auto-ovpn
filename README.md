# auto-ovpn

A small Bash utility that bootstraps an OpenVPN server in Docker or Podman and exports a client profile.

> **Security note:** an OpenVPN profile contains client key material and must be treated like a password. Never commit generated `.ovpn` files, private keys, PKI data, or environment files.

## What the script does

1. Detects or accepts the server's public IPv4 address.
2. Creates a named container volume for OpenVPN state.
3. Generates the server configuration and initializes the PKI on first run.
4. Starts a restartable OpenVPN container.
5. Creates one client identity and writes `<client-name>.ovpn` with restrictive local permissions.

## Requirements

- Bash 4+
- Docker or Podman
- `dig` or `curl` for public IP discovery, unless `PUBLIC_IPV4` is supplied
- UDP port `1194` reachable from the internet by default

## Usage

```bash
chmod +x auto-ovpn.sh
./auto-ovpn.sh laptop
```

The secure default prompts for passphrases when the PKI or client key is created.

For a non-interactive lab deployment, the previous unencrypted behavior can be enabled explicitly:

```bash
ALLOW_UNENCRYPTED_PKI=1 \
ALLOW_UNENCRYPTED_CLIENT_KEY=1 \
./auto-ovpn.sh laptop
```

That mode is convenient, but it increases the impact of a stolen volume or client profile.

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `CONTAINER_RUNTIME` | `docker` | Use `docker` or `podman` |
| `OPENVPN_IMAGE` | `kylemanna/openvpn` | Container image; use a trusted digest for reproducible deployments |
| `OVPN_DATA` | `ovpn-data` | Named volume containing server configuration and PKI |
| `OPENVPN_PORT` | `1194` | Public UDP port |
| `SERVER_CONTAINER_NAME` | `openvpn` | Server container name |
| `PUBLIC_IPV4` | auto-detected | Explicit public IPv4 override |
| `ALLOW_UNENCRYPTED_PKI` | `0` | Opt in to an unencrypted CA key |
| `ALLOW_UNENCRYPTED_CLIENT_KEY` | `0` | Opt in to an unencrypted client key |

For higher-assurance use, set `OPENVPN_IMAGE` to a reviewed immutable digest rather than a mutable tag.

## Operational cautions

- Restrict inbound firewall rules to the chosen UDP port.
- Back up the PKI volume securely; losing it prevents clean certificate management.
- Revoke lost client certificates rather than only deleting local profile files.
- Do not expose Docker's socket or daemon API to untrusted networks.
- Review the upstream container image and OpenVPN configuration before production use.

## Validation

The repository CI checks Bash syntax and runs ShellCheck. A full integration test requires a privileged container runtime and real network configuration, so it is intentionally not executed in pull requests.

## Scope

This is a compact learning and lab utility, not a managed VPN service or a substitute for infrastructure review, monitoring, patching, backups, and certificate lifecycle management.
