#!/usr/bin/env bash
# Quête 6 - Fil rouge étape 3 : isoler la base derrière l'API.
#   demo_front : demo-api (publiée sur 8080)
#   demo_back  : demo-api + demo-db (aucun port publié)
# Un conteneur branché seulement sur demo_front ne partage aucun réseau avec
# demo-db : il ne peut ni résoudre son nom ni la joindre.
#
# À lancer depuis la racine du repo (Linux, macOS, WSL ou Git Bash).
set -euo pipefail

cd "$(dirname "$0")"

# Git Bash : empêche MSYS de réécrire les chemins passés à docker,
# et donne à Docker Desktop un chemin Windows pour le bind mount.
export MSYS_NO_PATHCONV=1
HOST_DIR="$(pwd -W 2>/dev/null || pwd)"

IMAGE=demo-api:1.0
IP_FMT='{{range $net, $cfg := .NetworkSettings.Networks}}  {{$net}}: {{$cfg.IPAddress}}{{"\n"}}{{end}}'

cleanup() {
  docker rm -f demo-api demo-db >/dev/null 2>&1 || true
  docker network rm demo_front demo_back >/dev/null 2>&1 || true
}

# Repartir d'un état propre
cleanup

echo "==> 1. Build de l'image $IMAGE"
docker build -q -t "$IMAGE" ./api

echo "==> 2. Réseaux personnalisés"
docker network create demo_front
docker network create demo_back

echo "==> 3. demo-db sur demo_back uniquement, sans -p"
docker run -d --name demo-db --network demo_back \
  --mount type=bind,source="$HOST_DIR/db/init.sql",target=/docker-entrypoint-initdb.d/init.sql,readonly \
  -e POSTGRES_USER=demo -e POSTGRES_PASSWORD=demo -e POSTGRES_DB=demo \
  postgres:16-alpine >/dev/null
until docker exec demo-db pg_isready -U demo -d demo >/dev/null 2>&1; do
  sleep 1
done
echo "    base prête"

echo "==> 4. demo-api sur demo_front + demo_back, publiée sur 8080"
docker run -d --name demo-api --network demo_front -p 8080:3000 \
  -e PGHOST=demo-db "$IMAGE" >/dev/null
docker network connect demo_back demo-api
until curl -sf localhost:8080/health >/dev/null; do
  sleep 1
done
echo "    API prête"

echo
echo "==> Ports publiés sur l'hôte (docker port)"
echo "-- demo-api"; docker port demo-api
echo "-- demo-db";  docker port demo-db | grep . || echo "  (aucun port publié)"

echo
echo "==> demo-api résout demo-db par son nom"
echo "\$ docker exec demo-api getent hosts demo-db"
docker exec demo-api getent hosts demo-db

echo
echo "==> Un conteneur tiers sur demo_front seulement ne joint pas demo-db"
echo "\$ docker run --rm --network demo_front alpine nc -zv -w 2 demo-db 5432"
if docker run --rm --network demo_front alpine nc -zv -w 2 demo-db 5432 2>&1; then
  echo "ÉCHEC : demo-db est joignable depuis demo_front" >&2
  cleanup
  exit 1
else
  echo "OK : demo-db introuvable depuis demo_front, la base est isolée (aucun réseau commun)"
fi

echo
echo "==> Adresses IPv4 par réseau"
echo "-- demo-db"
docker inspect -f "$IP_FMT" demo-db | grep .
echo "-- demo-api"
docker inspect -f "$IP_FMT" demo-api | grep .

echo

echo "==> curl -s localhost:8080/products"
curl -s localhost:8080/products
echo

echo
echo "==> Nettoyage"
cleanup
docker network ls --filter name=demo_ --format '{{.Name}}' | grep . || echo "    réseaux demo_* supprimés"
