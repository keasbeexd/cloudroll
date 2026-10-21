# Local test server

Cloudroll's native features need Memories 9+, which needs Nextcloud 34+. This runs both on your Linux machine so an iPhone on the same Wi-Fi can test them.

## One-time setup (needs sudo)

```sh
omarchy pkg add podman
sudo ufw allow from 192.168.1.0/24 to any port 8443 proto tcp comment 'cloudroll dev server'
```

Rootless Podman is used instead of Docker. On Omarchy, Docker access means root access. Rootless containers run as your user, and they can't bind ports below 1024, which is why the server uses 8443.

## Start

```sh
scripts/dev-server.sh
```

The script creates `config/dev-server/.env` with random passwords and starts Nextcloud, MariaDB and Caddy. It also installs Memories and copies Caddy's root certificate to `config/dev-server/root.crt`. It's safe to run again.

## Trust the certificate on the iPhone

The app accepts only https, and Caddy signs the server's certificate with its own local CA.

1. Get `root.crt` onto the phone, e.g. email it to yourself and open the attachment.
2. Settings → General → VPN & Device Management → install the downloaded profile.
3. Settings → General → About → Certificate Trust Settings → turn on full trust for "Caddy Local Authority".

Whoever holds the CA's private key could intercept any https connection from the phone. The key stays in the `caddy` volume on your machine. Remove the profile when you're done testing.

## Stop or reset

```sh
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
docker compose --project-directory config/dev-server down      # stop, keep data
docker compose --project-directory config/dev-server down -v   # delete all data
```

Deleting the data also creates a new CA, so the phone needs the new `root.crt`.
