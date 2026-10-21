#!/usr/bin/env bash
# Starts the local Nextcloud 34 + Memories test server under rootless Podman
# and exports Caddy's root CA for installing on the test iPhone.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../config/dev-server" && pwd)"
ENV_FILE="$DIR/.env"
PODMAN_SOCKET="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/podman/podman.sock"
export DOCKER_HOST="${DOCKER_HOST:-unix://$PODMAN_SOCKET}"

compose() { docker compose --project-directory "$DIR" "$@"; }
occ() { compose exec -T -u www-data nextcloud php occ "$@"; }

require_podman() {
  command -v podman >/dev/null || { echo "Podman is not installed: omarchy pkg add podman" >&2; exit 1; }
  systemctl --user enable --now podman.socket >/dev/null
  [[ -S "$PODMAN_SOCKET" ]] || { echo "Podman socket missing at $PODMAN_SOCKET" >&2; exit 1; }
}

create_env() {
  [[ -f "$ENV_FILE" ]] && return
  local ip
  ip="$(ip -4 route get 1.1.1.1 | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')"
  [[ -n "$ip" ]] || { echo "Couldn't detect this machine's LAN IP; create $ENV_FILE from .env.example" >&2; exit 1; }
  (
    umask 077
    cat >"$ENV_FILE" <<EOF
HOST_IP=$ip
HTTPS_PORT=8443
DB_PASSWORD=$(openssl rand -hex 24)
ADMIN_PASSWORD=$(openssl rand -hex 12)
EOF
  )
  echo "Created $ENV_FILE for $ip"
}

wait_for_install() {
  echo "Waiting for Nextcloud to finish installing (first start takes a few minutes)..."
  for _ in $(seq 1 120); do
    if occ status --output=json 2>/dev/null | jq -e '.installed' >/dev/null 2>&1; then return; fi
    sleep 5
  done
  echo "Nextcloud didn't finish installing within 10 minutes. Logs: DOCKER_HOST=$DOCKER_HOST docker compose --project-directory $DIR logs nextcloud" >&2
  exit 1
}

install_memories() {
  local apps
  apps="$(occ app:list --output=json)"
  if jq -e '.enabled.memories' <<<"$apps" >/dev/null; then return; fi
  if jq -e '.disabled.memories' <<<"$apps" >/dev/null; then
    occ app:enable memories
    return
  fi
  occ app:install memories
}

export_root_ca() {
  local ca=/data/caddy/pki/authorities/local/root.crt
  for _ in $(seq 1 30); do
    if compose exec -T caddy test -f "$ca"; then
      compose cp "caddy:$ca" "$DIR/root.crt"
      return
    fi
    sleep 1
  done
  echo "Caddy didn't create its root CA at $ca" >&2
  exit 1
}

require_podman
create_env
compose up -d
wait_for_install
install_memories
export_root_ca

# shellcheck source=/dev/null
source "$ENV_FILE"
echo
echo "Server:   https://$HOST_IP:$HTTPS_PORT (user: admin, password: ADMIN_PASSWORD in $ENV_FILE)"
echo "Root CA:  $DIR/root.crt (install on the iPhone, see docs/dev-server.md)"
