#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
umask 077

readonly DEFAULT_OPENVPN_IMAGE="kylemanna/openvpn"

CONTAINER_RUNTIME="${CONTAINER_RUNTIME:-docker}"
OPENVPN_IMAGE="${OPENVPN_IMAGE:-$DEFAULT_OPENVPN_IMAGE}"
OVPN_DATA="${OVPN_DATA:-ovpn-data}"
OPENVPN_PORT="${OPENVPN_PORT:-1194}"
SERVER_CONTAINER_NAME="${SERVER_CONTAINER_NAME:-openvpn}"
PUBLIC_IPV4="${PUBLIC_IPV4:-}"
ALLOW_UNENCRYPTED_PKI="${ALLOW_UNENCRYPTED_PKI:-0}"
ALLOW_UNENCRYPTED_CLIENT_KEY="${ALLOW_UNENCRYPTED_CLIENT_KEY:-0}"

usage() {
  cat <<'USAGE'
Usage: ./auto-ovpn.sh <client-name>

Environment variables:
  CONTAINER_RUNTIME              docker (default) or podman
  OPENVPN_IMAGE                  Container image; pin a trusted digest for production
  OVPN_DATA                      Named volume (default: ovpn-data)
  OPENVPN_PORT                   UDP port (default: 1194)
  SERVER_CONTAINER_NAME          Container name (default: openvpn)
  PUBLIC_IPV4                    Override automatic public IPv4 discovery
  ALLOW_UNENCRYPTED_PKI=1        Create an unencrypted CA key (not recommended)
  ALLOW_UNENCRYPTED_CLIENT_KEY=1 Create an unencrypted client key (not recommended)
USAGE
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

is_valid_ipv4() {
  local ip="$1" octet
  local -a octets
  IFS='.' read -r -a octets <<<"$ip"
  [[ ${#octets[@]} -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] || return 1
    ((10#$octet <= 255)) || return 1
  done
}

discover_public_ipv4() {
  local discovered=""

  if [[ -n "$PUBLIC_IPV4" ]]; then
    is_valid_ipv4 "$PUBLIC_IPV4" || die "PUBLIC_IPV4 is not a valid IPv4 address"
    return
  fi

  if command -v dig >/dev/null 2>&1; then
    discovered="$(dig +short @resolver4.opendns.com myip.opendns.com A | head -n1)"
  elif command -v curl >/dev/null 2>&1; then
    discovered="$(curl --fail --silent --show-error --max-time 10 https://api.ipify.org)"
  else
    die "install dig or curl, or set PUBLIC_IPV4 explicitly"
  fi

  is_valid_ipv4 "$discovered" || die "could not determine a valid public IPv4 address"
  PUBLIC_IPV4="$discovered"
}

client_name="${1:-}"
[[ -n "$client_name" ]] || { usage >&2; exit 2; }
[[ "$client_name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || \
  die "client name must be 1-64 characters using only letters, numbers, dot, underscore or hyphen"
[[ "$OPENVPN_PORT" =~ ^[0-9]+$ ]] || die "OPENVPN_PORT must be numeric"
((OPENVPN_PORT >= 1 && OPENVPN_PORT <= 65535)) || die "OPENVPN_PORT must be between 1 and 65535"
[[ "$ALLOW_UNENCRYPTED_PKI" =~ ^[01]$ ]] || die "ALLOW_UNENCRYPTED_PKI must be 0 or 1"
[[ "$ALLOW_UNENCRYPTED_CLIENT_KEY" =~ ^[01]$ ]] || die "ALLOW_UNENCRYPTED_CLIENT_KEY must be 0 or 1"

require_command "$CONTAINER_RUNTIME"
discover_public_ipv4

printf 'Using public endpoint udp://%s:%s\n' "$PUBLIC_IPV4" "$OPENVPN_PORT"
printf 'Using container image %s\n' "$OPENVPN_IMAGE"

if ! "$CONTAINER_RUNTIME" volume inspect "$OVPN_DATA" >/dev/null 2>&1; then
  "$CONTAINER_RUNTIME" volume create "$OVPN_DATA" >/dev/null
  "$CONTAINER_RUNTIME" run --rm \
    -v "${OVPN_DATA}:/etc/openvpn" \
    "$OPENVPN_IMAGE" \
    ovpn_genconfig -b -u "udp://${PUBLIC_IPV4}:${OPENVPN_PORT}"

  pki_args=()
  if [[ "$ALLOW_UNENCRYPTED_PKI" == "1" ]]; then
    printf 'WARNING: creating an unencrypted CA private key.\n' >&2
    pki_args=(nopass)
  fi
  "$CONTAINER_RUNTIME" run --rm -it \
    -v "${OVPN_DATA}:/etc/openvpn" \
    "$OPENVPN_IMAGE" \
    ovpn_initpki "${pki_args[@]}"
else
  printf 'Reusing existing volume %s; PKI initialization skipped.\n' "$OVPN_DATA"
fi

if "$CONTAINER_RUNTIME" container inspect "$SERVER_CONTAINER_NAME" >/dev/null 2>&1; then
  "$CONTAINER_RUNTIME" start "$SERVER_CONTAINER_NAME" >/dev/null
else
  "$CONTAINER_RUNTIME" run -d \
    --name "$SERVER_CONTAINER_NAME" \
    --restart unless-stopped \
    -v "${OVPN_DATA}:/etc/openvpn" \
    -p "${OPENVPN_PORT}:1194/udp" \
    --cap-add=NET_ADMIN \
    "$OPENVPN_IMAGE" >/dev/null
fi

client_args=()
if [[ "$ALLOW_UNENCRYPTED_CLIENT_KEY" == "1" ]]; then
  printf 'WARNING: creating an unencrypted client private key.\n' >&2
  client_args=(nopass)
fi

"$CONTAINER_RUNTIME" run --rm -it \
  -v "${OVPN_DATA}:/etc/openvpn" \
  "$OPENVPN_IMAGE" \
  easyrsa build-client-full "$client_name" "${client_args[@]}"

output_file="${client_name}.ovpn"
temporary_file="${output_file}.tmp"
trap 'rm -f -- "$temporary_file"' EXIT

"$CONTAINER_RUNTIME" run --rm \
  -v "${OVPN_DATA}:/etc/openvpn" \
  "$OPENVPN_IMAGE" \
  ovpn_getclient "$client_name" >"$temporary_file"

mv -- "$temporary_file" "$output_file"
trap - EXIT
printf 'Client profile written to %s with permissions restricted by umask 077.\n' "$output_file"
printf 'Treat this file as a secret and never commit it.\n'
