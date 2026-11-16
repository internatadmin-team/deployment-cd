# Securite et qualite du code — InternatAdmin

Ce document resume les analyses de securite automatisees integrees aux pipelines
CI (`backend-ci` et `frontend-ci`), les seuils de blocage retenus, et la politique
de gestion des exceptions. Il correspond a l'etape 5 (Securite & Qualite) de
l'examen.

## Vue d'ensemble des outils

| Outil | Depot(s) | Ce qu'il analyse | Seuil de blocage du build |
|---|---|---|---|
| Trivy (scan d'image) | backend-ci, frontend-ci | Vulnerabilites connues dans l'image Docker finale (OS + dependances) | Toute vulnerabilite **CRITICAL** fait echouer le build |
| OWASP Dependency-Check | backend-ci | Vulnerabilites connues dans les dependances Maven (CVE) | Score CVSS **>= 9** (parametre `DC_FAIL_CVSS`) |
| npm audit | frontend-ci | Vulnerabilites connues dans les dependances npm | Severite **high** ou plus (`--audit-level=high`) |

Chaque outil tourne a chaque build (sur chaque push, grace au declenchement
automatique CI) et ses rapports sont archives comme artefacts Jenkins pour
tracabilite, meme quand le build reussit.

## Resultats actuels

### Backend (`backend-ci`)

- **Trivy** : image basee sur `eclipse-temurin:21-jdk-alpine` (Alpine 3.24.2).
  Aucune vulnerabilite CRITICAL detectee sur les derniers builds : le stage
  "Scan de l'image (Trivy)" passe sans declenchement du seuil de blocage.
  Le rapport complet HIGH+CRITICAL est archive dans `reports/trivy/image.txt`
  a chaque build pour revue manuelle, meme si rien ne bloque.
- **OWASP Dependency-Check** : execute sur les dependances Maven avec la base
  NVD complete (cle API `nvd-api-key`). Aucune dependance ne depasse le score
  CVSS de 9 : le stage passe. Les rapports HTML et JSON sont archives
  (`target/dependency-check-report.*`) pour consultation detaillee des CVE
  rencontrees, meme sous le seuil de blocage.

### Frontend (`frontend-ci`)

- **Trivy** : image basee sur `nginxinc/nginx-unprivileged:1.30-alpine`
  (Alpine 3.24.2). Meme politique que le backend : aucune vulnerabilite
  CRITICAL detectee, rapport archive dans `reports/trivy/image.txt`.
- **npm audit** : 16 vulnerabilites de severite **moderate** signalees,
  concentrees sur la chaine de dependances `glob` / `minimatch` utilisee en
  interne par `@angular/cli` (outil de build, jamais embarque dans l'image
  finale servie par nginx). Correctif disponible uniquement via
  `npm audit fix --force`, qui imposerait une mise a jour majeure et cassante
  de `@angular/cli` (passage a la version 22.2.7) sans benefice de securite
  en production puisque ces paquets ne tournent pas dans le conteneur livre.
  Le seuil de blocage du pipeline est fixe a `high`, donc ces vulnerabilites
  moderate n'interrompent pas le build ; elles restent visibles dans le
  rapport archive `reports/npm-audit/audit.json` pour suivi.

## Gestion des exceptions

Deux mecanismes de suppression existent dans le pipeline backend, tous deux
**vides a ce jour** : aucune exception n'a ete necessaire sur ce projet.

- **`owasp-suppressions.xml`** : permet d'exclure une CVE precise d'OWASP
  Dependency-Check lorsqu'elle est averee non applicable (faux positif).
  Chaque entree doit porter une justification (`<notes>`) expliquant pourquoi
  la CVE ne s'applique pas au contexte du projet.
- **`.trivyignore`** : permet d'exclure une CVE precise de Trivy. La
  convention imposee sur ce projet est `CVE-AAAA-NNNNN exp:AAAA-MM-JJ` : toute
  exception doit porter une date d'expiration, apres laquelle elle redevient
  bloquante automatiquement. Cela evite qu'une exception "temporaire" ne soit
  oubliee indefiniment dans le pipeline.

Si une vulnerabilite non corrigeable apparait a l'avenir, elle devra etre
documentee dans l'un de ces deux fichiers avec sa justification, plutot que
d'augmenter les seuils globaux (`DC_FAIL_CVSS`, `--audit-level`), afin de
garder le controle au cas par cas.

## Notification des resultats

Chaque build (succes ou echec) de `backend-ci`, `frontend-ci` et
`deployment-cd` envoie une notification dans le canal Slack
`#tous-the-devops`, incluant le commit, la version et le statut, pour que
toute l'equipe soit informee sans avoir a consulter Jenkins.
