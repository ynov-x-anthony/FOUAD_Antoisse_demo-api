#!/usr/bin/env bash
# Quête 5 - Fil rouge étape 2 : persistance de demo-api avec un named volume.
# Prouve que les données de PostgreSQL survivent à la suppression + recréation
# du conteneur de base, tant que le volume demo_pgdata est conservé.
#
# À lancer depuis la racine du repo (Linux, macOS, WSL ou Git Bash).
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash : empêche MSYS de réécrire les chemins passés à docker,
# et donne à Docker Desktop un chemin Windows pour le bind mount.
export MSYS_NO_PATHCONV=1
HOST_DIR="$(pwd -W 2>/dev/null || pwd)"

IMAGE=demo-api:1.0
VOLUME=demo_pgdata
NETWORK=demo_net

wait_db() {
  echo "==> Attente de PostgreSQL (pg_isready)"
  until docker exec demo-db pg_isready -U demo -d demo >/dev/null 2>&1; do
    sleep 1
  done
  echo "    base prête"
}

wait_api() {
  echo "==> Attente de l'API"
  until curl -sf localhost:8080/health >/dev/null; do
    sleep 1
  done
  echo "    API prête"
}

start_db() {
  echo "==> Lancement de demo-db sur le volume $VOLUME"
  docker run -d --name demo-db --network "$NETWORK" \
    --mount type=volume,source="$VOLUME",target=/var/lib/postgresql/data \
    --mount type=bind,source="$HOST_DIR/db/init.sql",target=/docker-entrypoint-initdb.d/init.sql,readonly \
    -e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=demo \
    postgres:16-alpine >/dev/null
  wait_db
}

start_api() {
  echo "==> Lancement de demo-api"
  docker run -d --name demo-api --network "$NETWORK" -p 8080:3000 \
    -e PGHOST=demo-db "$IMAGE" >/dev/null
  wait_api
}

# Repartir d'un état propre (sans toucher au volume)
docker rm -f demo-api demo-db >/dev/null 2>&1 || true
docker network rm "$NETWORK" >/dev/null 2>&1 || true

echo "==> 1. Build de l'image $IMAGE"
docker build -q -t "$IMAGE" ./api

echo "==> 2. Volume et réseau"
docker volume create "$VOLUME"
docker network create "$NETWORK" >/dev/null

start_db
start_api

echo "==> 3. Ajout d'un produit"
# Corps envoyé via stdin : sous Windows, un argument -d passe par la page de
# code ANSI et casse l'accent ; stdin garde les octets UTF-8 du script.
printf '%s' '{"name":"Casquette Démo","price_cents":1200}' |
  curl -s -X POST -H 'content-type: application/json' \
    --data-binary @- localhost:8080/products
echo

echo "==> AVANT suppression : GET /products"
curl -s localhost:8080/products
echo

echo "==> 4. Suppression du conteneur de base (le volume reste)"
docker rm -f demo-db demo-api

start_db
start_api

echo "==> APRÈS recréation sur le même volume : GET /products"
AFTER="$(curl -s localhost:8080/products)"
echo "$AFTER"

if echo "$AFTER" | grep -q "Casquette Démo"; then
  echo "OK : « Casquette Démo » a survécu à la suppression du conteneur de base"
else
  echo "ÉCHEC : produit absent après recréation" >&2
  exit 1
fi

echo "==> Volume"
docker volume ls | grep "$VOLUME"
echo "==> curl localhost:8080/products (final)"
curl -s localhost:8080/products
echo

echo "==> Nettoyage (conteneurs + réseau, volume conservé)"
docker rm -f demo-api demo-db >/dev/null
docker network rm "$NETWORK" >/dev/null

# Pour tout effacer, données comprises :
# docker volume rm demo_pgdata
