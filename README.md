# demo-api

Le fil rouge des quêtes Docker : une mini-API "catalogue" que tu vas
conteneuriser, faire persister, mettre en réseau, orchestrer et sécuriser,
une quête à la fois.

Le métier est volontairement trivial (`Node` + `Express` + `PostgreSQL`,
un catalogue de produits) : toute la difficulté est sur **Docker**, jamais
sur le code applicatif.

## Lancer la stack avec Docker Compose

La stack complète est décrite dans [`compose.yml`](compose.yml) :

| Service | Image | Accès |
|---|---|---|
| `api` | construite depuis `./api` | http://localhost:8080 (`API_PORT`) |
| `db` | `postgres:16-alpine` | **non publiée**, joignable seulement par `api` sur le réseau du projet |
| `adminer` | `adminer:4` | http://localhost:8081 (`ADMINER_PORT`) |

- `db` : volume nommé `pgdata` (données), `db/init.sql` monté en lecture
  seule (joué au premier démarrage uniquement), healthcheck `pg_isready`.
- `api` : démarre seulement quand `db` est *healthy*
  (`depends_on: condition: service_healthy`), `restart: unless-stopped`.
- Le mot de passe de la base passe par **Docker Secrets** : `db` le lit via
  `POSTGRES_PASSWORD_FILE` et `api` via `PGPASSWORD_FILE` (support ajouté dans
  `api/db.js`). Il n'apparaît ni dans `compose.yml`, ni dans `.env`, ni dans
  `printenv` des conteneurs.

### Prérequis

- Docker Engine + Compose v2 (`docker compose version`), Docker Desktop sous
  macOS / Windows.
- `git`, `curl` (sous PowerShell, utiliser `curl.exe`).

### Démarrage

```bash
# 1. Variables d'interpolation ${} (fichier .env non commité)
cp .env.example .env

# 2. Mot de passe de la base, en secret hors Git (secrets/ est dans .gitignore)
mkdir -p secrets
openssl rand -base64 18 > secrets/db_password.txt   # ou n'importe quel mot de passe

# 3. Build + démarrage en arrière-plan
docker compose up -d --build
```

| Variable (`.env`) | Rôle | Défaut |
|---|---|---|
| `POSTGRES_USER` | utilisateur PostgreSQL, aussi utilisé par l'API | `demo` |
| `POSTGRES_DB` | base PostgreSQL | `demo` |
| `API_PORT` | port hôte de l'API | `8080` |
| `ADMINER_PORT` | port hôte d'Adminer | `8081` |

URLs :

- API : http://localhost:8080/products
- Adminer : http://localhost:8081 (système *PostgreSQL*, serveur `db`,
  utilisateur `demo`, mot de passe = contenu de `secrets/db_password.txt`)

### Commande testée et résultat

Testé le 09/10/2026 (Windows 11, Docker Desktop, Engine 29.8.2,
Compose v5.5.1) avec `docker compose up -d --build` :

```text
$ docker compose ps
NAME                                IMAGE                         STATUS                    PORTS
fouad_antoisse_demo-api-adminer-1   adminer:4                     Up 32 seconds             0.0.0.0:8081->8080/tcp
fouad_antoisse_demo-api-api-1       fouad_antoisse_demo-api-api   Up 26 seconds (healthy)   0.0.0.0:8080->3000/tcp
fouad_antoisse_demo-api-db-1        postgres:16-alpine            Up 32 seconds (healthy)   5432/tcp
```

Persistance vérifiée : un produit ajouté survit à `down` puis `up`.

```text
$ curl -s -X POST -H 'content-type: application/json' -d '{"name":"Gourde","price_cents":900}' localhost:8080/products
{"id":4,"name":"Gourde","price_cents":900,"created_at":"2026-10-09T11:42:58.129Z"}

$ docker compose down && docker compose up -d
$ curl -s localhost:8080/products
[{"id":4,"name":"Gourde","price_cents":900,...},{"id":3,"name":"T-shirt conteneur",...},{"id":2,"name":"Mug Docker",...},{"id":1,"name":"Sticker Demo",...}]

$ docker compose exec api sh -c "printenv | grep ^PG"
PGDATABASE=demo
PGPASSWORD_FILE=/run/secrets/db_password
PGHOST=db
PGUSER=demo
```

### Arrêter / repartir de zéro

```bash
docker compose down      # supprime conteneurs + réseau, GARDE le volume pgdata (données conservées)
docker compose down -v   # supprime AUSSI le volume pgdata : données perdues, init.sql rejoué au prochain up
```

## Point de départ

Ce dossier est ce que tu clones **avant ta première quête Docker**. Il n'y a
volontairement **aucun fichier Docker** dedans, ni `Dockerfile`, ni
`compose.yml` : ce sont précisément les fichiers que tu vas écrire, quête
après quête, en faisant grossir ce dépôt.

Sans conteneur, cette API ne démarre pas telle quelle : elle a besoin d'un
PostgreSQL joignable pour répondre. C'est normal, et c'est tout le sujet de
la première quête que de la faire tourner dans Docker.

## Récupérer ce starter dans ton propre repo

Ce dépôt est un **starter en lecture seule** : tu ne pousses jamais
directement ici. Avant de démarrer la première quête :

1. **Clone** ce repo starter :
   ```bash
   git clone git@github.com:ynov-x-anthony/docker-demo-api-starter.git NOM_prenom_demo-api
   cd NOM_prenom_demo-api
   ```
2. **Supprime le remote `origin`** (il pointe vers le starter, pas vers toi) :
   ```bash
   git remote remove origin
   ```
3. **Crée ton propre repo** sur GitHub, dans l'organisation `ynov-x-anthony`,
   en respectant la nomenclature **`NOM_prenom_demo-api`** (ex. :
   `DUPONT_jean_demo-api`), puis ajoute-le comme nouveau remote et pousse :
   ```bash
   git remote add origin git@github.com:ynov-x-anthony/NOM_prenom_demo-api.git
   git push -u origin main
   ```

À partir de là, c'est **ton** repo : chaque quête s'y ajoute par des commits,
et c'est lui qui sera évalué, pas le starter.

## Ce que contient le repo

| Fichier | Rôle |
|---|---|
| `api/server.js` | l'API Express (`/`, `/version`, `/health`, `/ready`, `/products`) |
| `api/db.js` | connexion PostgreSQL, entièrement pilotée par des variables d'environnement |
| `api/package.json`, `api/package-lock.json` | dépendances (`express`, `pg`) |
| `db/init.sql` | création de la table `products` + quelques données de démo |

## Les routes de l'API

| Méthode | Route | Effet |
|---|---|---|
| `GET` | `/` | infos application + version |
| `GET` | `/version` | numéro de version courant |
| `GET` | `/health` | liveness, ne touche pas la base |
| `GET` | `/ready` | readiness, teste la connexion à la base |
| `GET` | `/products` | liste des produits |
| `POST` | `/products` | crée un produit : `{ "name": "...", "price_cents": 1234 }` |

## Ta progression, quête après quête

| Quête | Ce que tu ajoutes au repo |
|---|---|
| Découverte de Docker | rien ici, tu manipules des images publiques et un `psql` en conteneur |
| Le Dockerfile | `api/Dockerfile`, `api/.dockerignore` : l'API tourne enfin dans un conteneur |
| Les volumes | un volume nommé pour la persistance de PostgreSQL |
| Les réseaux | des réseaux dédiés, la base jamais exposée directement |
| Compose | `compose.yml`, `.env.example` : tous les services démarrent ensemble |
| Dockerfile et sécurité | ton `Dockerfile` durci : utilisateur non-root, `HEALTHCHECK` |
| Builds multi-étapes et gestion des secrets | `api/Dockerfile.multi` : image allégée, secrets hors de l'image |
| Analyse de vulnérabilité avec Trivy | un pipeline CI qui scanne ton image et bloque sur les failles critiques |

## Prérequis machine (macOS / Linux / Windows)

- **Docker Engine + Compose v2** : le plugin intégré, invoqué en deux mots
  `docker compose` (pas l'ancien binaire autonome `docker-compose` v1).
  `docker compose version` doit répondre `v2.x` ou une version supérieure
  (v3, v4, v5…). Ce qui compte, c'est que ce ne soit pas du v1 legacy.
- macOS / Windows : **Docker Desktop** (ou Colima / Rancher Desktop).
  Sous Windows, backend **WSL 2** : travaille depuis un terminal **WSL**.
- `git`, `curl`. Node est nécessaire **seulement** si tu régénères
  `package-lock.json` (`cd api && npm install`, déjà commité ici).
