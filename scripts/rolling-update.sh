#!/usr/bin/env bash
# Met a jour le backend et le frontend sans interruption de service.
#
# Backend (demarrage lent, ~30s avant d'etre sain) : la technique utilisee est le
# partage d'alias reseau Docker. Un deuxieme conteneur backend est demarre sur le
# MEME alias reseau ("backend") que l'ancien. Pendant que les deux coexistent, le
# DNS interne de Docker fait tourner les requetes entre les deux (round-robin) :
# l'ancien repond tout seul jusqu'a ce que le nouveau devienne sain, puis les deux
# repondent, puis seul le nouveau repond une fois l'ancien arrete. A aucun moment
# il n'y a zero conteneur backend disponible.
#
# Frontend (Nginx, demarre en <1s) : mise a jour classique via "docker compose up
# -d --no-deps frontend". La coupure du port publie est trop courte (le nouveau
# conteneur est pret avant que la plupart des clients aient retente) pour etre vue
# dans le test de la boucle curl (voir watch-healthz.sh). C'est une vraie
# different avec le backend, a savoir expliquer a l'oral (cf. NOTES-INTEGRATION.md).
#
# Usage : ./scripts/rolling-update.sh [backend_tag] [frontend_tag]
# Sans argument : reutilise les tags deja presents dans .env.

set -euo pipefail
cd "$(dirname "$0")/.."

BACKEND_IMAGE="${BACKEND_IMAGE:-abdoulaye940/daara-backend}"
FRONTEND_IMAGE="${FRONTEND_IMAGE:-abdoulaye940/daara-frontend}"

# Charge .env (POSTGRES_*, JWT_SECRET, etc.) pour reconstruire exactement les
# memes variables d'environnement que celles que docker-compose.yml donne au
# service "backend" — necessaire puisque ce conteneur est demarre avec "docker
# run", donc en dehors de la substitution automatique de Compose.
set -a
# shellcheck disable=SC1091
source .env
set +a

BACKEND_TAG="${1:-${BACKEND_TAG:-latest}}"
FRONTEND_TAG="${2:-${FRONTEND_TAG:-latest}}"

OLD_BACKEND_ID="$(docker compose ps -q backend)"
if [ -z "$OLD_BACKEND_ID" ]; then
    echo "Aucun conteneur backend en cours (lance d'abord 'docker compose up -d')." >&2
    exit 1
fi
NETWORK="$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{end}}' "$OLD_BACKEND_ID")"

echo "== Backend : demarrage de la nouvelle instance (${BACKEND_IMAGE}:${BACKEND_TAG}) =="
docker pull "${BACKEND_IMAGE}:${BACKEND_TAG}" 2>/dev/null || echo "(image non trouvee sur Docker Hub, utilisation de l'image locale si elle existe)"

NEW_BACKEND_ID="$(docker run -d --network "$NETWORK" --network-alias backend \
    -e DB_URL="jdbc:postgresql://postgres:5432/${POSTGRES_DB}" \
    -e DB_USERNAME="${POSTGRES_USER}" \
    -e DB_PASSWORD="${POSTGRES_PASSWORD}" \
    -e JWT_SECRET="${JWT_SECRET}" \
    -e JWT_EXPIRATION_MINUTES="${JWT_EXPIRATION_MINUTES:-480}" \
    -e ADMIN_INITIAL_PASSWORD_HASH="${ADMIN_INITIAL_PASSWORD_HASH}" \
    -e CORS_ALLOWED_ORIGINS="${CORS_ALLOWED_ORIGINS:-http://localhost:8080}" \
    -e SERVER_PORT=8080 \
    -e LOGO_DIR=/data/logos \
    -e PAIEMENT_LOCK_TIMEOUT="${PAIEMENT_LOCK_TIMEOUT:-5s}" \
    "${BACKEND_IMAGE}:${BACKEND_TAG}")"

echo "Nouvelle instance : ${NEW_BACKEND_ID:0:12}. Attente qu'elle soit saine..."
STATUS="starting"
for i in $(seq 1 30); do
    STATUS="$(docker inspect -f '{{.State.Health.Status}}' "$NEW_BACKEND_ID" 2>/dev/null || echo starting)"
    if [ "$STATUS" = "healthy" ]; then
        echo "Nouvelle instance backend saine apres $((i * 2))s."
        break
    fi
    sleep 2
done

if [ "$STATUS" != "healthy" ]; then
    echo "ECHEC : la nouvelle instance n'est jamais devenue saine. Elle est supprimee, l'ancienne reste active (rollback automatique)." >&2
    docker rm -f "$NEW_BACKEND_ID"
    exit 1
fi

echo "== Bascule : les deux instances repondent un court instant, puis arret de l'ancienne =="
docker stop "$OLD_BACKEND_ID" >/dev/null
docker rm "$OLD_BACKEND_ID" >/dev/null
echo "Ancienne instance arretee. Seule la nouvelle repond desormais sur l'alias 'backend'."

echo
echo "== Frontend : mise a jour (${FRONTEND_IMAGE}:${FRONTEND_TAG}) =="
BACKEND_TAG="$BACKEND_TAG" FRONTEND_TAG="$FRONTEND_TAG" docker compose up -d --no-deps frontend

echo
echo "== Etat final =="
docker compose ps

echo
echo "Remarque : le conteneur backend issu de ce script n'est pas reconnu par Compose"
echo "(demarre avec 'docker run', pas 'docker compose up'). Un futur 'docker compose up -d'"
echo "le recreera proprement avec le meme tag et la meme configuration : c'est normal et sans risque."
