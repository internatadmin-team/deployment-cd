#!/usr/bin/env bash
# A lancer dans un AUTRE terminal, EN PARALLELE de rolling-update.sh, pour prouver
# qu'aucune requete n'est perdue pendant la mise a jour.
#
# Usage : ./scripts/watch-healthz.sh [duree_en_secondes]
# Lance rolling-update.sh dans le premier terminal pendant que celui-ci tourne.

set -uo pipefail

DURATION="${1:-90}"
URL="http://localhost:8080/healthz"
END=$((SECONDS + DURATION))
TOTAL=0
ERRORS=0

echo "Verification de ${URL} toutes les 0.5s pendant ${DURATION}s..."
while [ $SECONDS -lt $END ]; do
    TOTAL=$((TOTAL + 1))
    if curl -fsS -o /dev/null -m 2 "$URL"; then
        printf '.'
    else
        ERRORS=$((ERRORS + 1))
        echo
        echo "$(date +%T) ECHEC (requete #${TOTAL})"
    fi
    sleep 0.5
done

echo
echo "Total requetes : ${TOTAL}, echecs : ${ERRORS}"
if [ "$ERRORS" -eq 0 ]; then
    echo "Aucune erreur : la mise a jour n'a provoque aucune interruption visible."
else
    echo "Des echecs ont ete releves : voir les horodatages ci-dessus pour les situer dans le temps."
fi
