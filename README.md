# deployment-cd — InternatAdmin

Depot de deploiement continu de l'application InternatAdmin : orchestration
par Docker Compose des 3 services (backend, frontend, base de donnees) a
partir des images publiees sur Docker Hub par `backend-ci` et `frontend-ci`.

## Architecture du deploiement

```
                 ┌────────────┐      ┌────────────┐
  push sur       │ backend-ci │      │frontend-ci │   push sur
  backend-ci --> │  Jenkins   │      │  Jenkins   │ <-- frontend-ci
                 └─────┬──────┘      └─────┬──────┘
                       │  build job (tag)  │
                       └─────────┬─────────┘
                                 v
                        ┌─────────────────┐
                        │  deployment-cd  │
                        │     Jenkins     │
                        └────────┬────────┘
                                 v
                    docker compose (3 services)
          ┌─────────────┬──────────────┬──────────────┐
          │  postgres   │   backend    │   frontend   │
          │ (volume     │ (daara-      │ (daara-      │
          │  nomme,     │  backend)    │  frontend,   │
          │  persistant)│              │  nginx,      │
          │             │              │  port 8080)  │
          └─────────────┴──────────────┴──────────────┘
```

`deployment-cd` ne construit aucune image : il recupere les images deja
publiees sur Docker Hub (`abdoulaye940/daara-backend`,
`abdoulaye940/daara-frontend`) et met a jour la pile Docker Compose.

## Variables d'environnement

Le pipeline Jenkins genere un fichier `.env` a chaque execution (jamais
commite, supprime en fin de build). Pour une execution manuelle hors Jenkins,
cree toi-meme un `.env` a la racine avec ces variables :

| Variable | Role |
|---|---|
| `POSTGRES_DB` | Nom de la base PostgreSQL |
| `POSTGRES_USER` | Utilisateur PostgreSQL |
| `POSTGRES_PASSWORD` | Mot de passe PostgreSQL (secret) |
| `JWT_SECRET` | Cle de signature des jetons JWT (secret) |
| `JWT_EXPIRATION_MINUTES` | Duree de validite des jetons (ex. `480`) |
| `ADMIN_INITIAL_PASSWORD_HASH` | Hash bcrypt du mot de passe admin initial (secret, optionnel apres le premier demarrage) |
| `CORS_ALLOWED_ORIGINS` | Origine(s) autorisee(s) a appeler l'API |
| `FRONTEND_PORT` | Port expose par le frontend (ex. `8080`) |
| `BACKEND_IMAGE` / `BACKEND_TAG` | Image et tag backend a deployer |
| `FRONTEND_IMAGE` / `FRONTEND_TAG` | Image et tag frontend a deployer |

Aucune valeur reelle de secret n'est partagee ici ; les secrets reels vivent
uniquement dans les credentials Jenkins (`postgres-password`, `jwt-secret`,
`admin-initial-password-hash`).

## Commandes de deploiement

```bash
docker compose --project-name internatadmin pull backend frontend
docker compose --project-name internatadmin up -d --remove-orphans
```

Verification de sante apres deploiement :

```bash
curl -fsS http://localhost:8080/healthz
docker compose --project-name internatadmin ps
```

## Mise a jour sans interruption

`docker compose up -d` ne recree que les services dont l'image ou la
configuration a reellement change. Un push sur `backend-ci` seul ne
recree donc que le conteneur `backend` ; le `frontend` et la base de
donnees restent en place et continuent de servir les requetes pendant la
mise a jour. Meme principe dans l'autre sens pour un push sur
`frontend-ci`.

## Persistance des donnees

PostgreSQL utilise un volume Docker nomme, jamais recree ni supprime par
`docker compose up`, meme lors d'un `--remove-orphans`. Les donnees
(eleves, personnel, paiements, comptabilite) survivent donc a chaque
redeploiement du backend ou du frontend.

## Pipeline CD (`Jenkinsfile`)

Le job `deployment-cd` est declenche :

- **automatiquement**, depuis `backend-ci` ou `frontend-ci`, des qu'un build
  reussi sur `main` publie une nouvelle image (parametre
  `TRIGGER_DEPLOY=true` par defaut) ; chaque pipeline CI ne transmet que le
  tag qu'il connait (`BACKEND_TAG` ou `FRONTEND_TAG`), l'autre service garde
  le dernier tag deploye avec succes ;
- **manuellement**, via "Build with Parameters" si besoin de redeployer sans
  nouveau build CI.

Etapes du pipeline : generation du `.env` a partir des credentials Jenkins,
recuperation des images, mise a jour de la pile Docker Compose, verification
de sante (`/healthz`, jusqu'a 20 tentatives espacees de 3 secondes),
suppression du `.env`, puis notification Slack du resultat (succes ou echec)
dans `#tous-the-devops`.

Voir `docs/securite.md` pour le detail des analyses de securite effectuees en
amont, dans `backend-ci` et `frontend-ci`.
