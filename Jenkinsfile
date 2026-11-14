// Pipeline de deploiement : recupere les images par tag, injecte les secrets depuis les
// credentials Jenkins, (re)demarre la pile docker-compose, verifie la sante, notifie.
//
// Declenchement : manuellement, ou automatiquement depuis les pipelines backend-ci/frontend-ci
// (parametre TRIGGER_DEPLOY de ces pipelines) via "build job: 'deployment-cd'". Chaque pipeline CI
// ne declenche qu'avec le tag qu'il connait (BACKEND_TAG ou FRONTEND_TAG) : l'autre garde sa valeur
// par defaut (dernier tag deploye avec succes), d'ou DEFAULT_IMAGE_TAG plutot que 'latest' en dur.
//
// Prerequis Jenkins :
//   - agent MI_AG (meme machine que les pipelines CI, avec Docker Desktop) ;
//   - credentials (texte secret) : postgres-password, jwt-secret, admin-initial-password-hash ;
//   - credential (texte secret) optionnel : slack-webhook-url (sinon notification journal seulement).

pipeline {
    agent { label 'MI_AG' }

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
        timeout(time: 20, unit: 'MINUTES')
    }

    parameters {
        // BACKEND_SERVICES : parametre informatif envoye par le pipeline backend-ci (non utilise
        // directement ici), conserve pour ne pas faire echouer son appel "build job".
        string(name: 'BACKEND_SERVICES', defaultValue: '', description: 'Informatif : service(s) ayant declenche ce deploiement')
        string(name: 'BACKEND_TAG', defaultValue: 'latest', description: 'Tag de l\'image backend a deployer')
        string(name: 'FRONTEND_TAG', defaultValue: 'latest', description: 'Tag de l\'image frontend a deployer')
    }

    environment {
        DOCKERHUB_USER  = 'abdoulaye940'
        BACKEND_IMAGE   = "${DOCKERHUB_USER}/daara-backend"
        FRONTEND_IMAGE  = "${DOCKERHUB_USER}/daara-frontend"
        COMPOSE_PROJECT = 'internatadmin'
        HEALTH_URL      = 'http://localhost:8080/healthz'
    }

    stages {
        stage('Checkout') {
            steps { checkout scm }
        }

        stage('Preparer .env') {
            steps {
                withCredentials([
                    string(credentialsId: 'postgres-password', variable: 'POSTGRES_PASSWORD'),
                    string(credentialsId: 'jwt-secret', variable: 'JWT_SECRET'),
                    string(credentialsId: 'admin-initial-password-hash', variable: 'ADMIN_INITIAL_PASSWORD_HASH')
                ]) {
                    // .env est regenere a chaque deploiement, jamais versionne (voir .gitignore),
                    // et supprime en fin de build (post.always) : aucun secret ne reste sur le disque
                    // entre deux executions, et aucun secret n'apparait dans le journal de la commande.
                    writeFile file: '.env', text: """POSTGRES_DB=internatadmin
POSTGRES_USER=internatadmin
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
JWT_SECRET=${JWT_SECRET}
JWT_EXPIRATION_MINUTES=480
ADMIN_INITIAL_PASSWORD_HASH=${ADMIN_INITIAL_PASSWORD_HASH}
CORS_ALLOWED_ORIGINS=http://localhost:8080
FRONTEND_PORT=8080
BACKEND_IMAGE=${BACKEND_IMAGE}
BACKEND_TAG=${params.BACKEND_TAG}
FRONTEND_IMAGE=${FRONTEND_IMAGE}
FRONTEND_TAG=${params.FRONTEND_TAG}
"""
                }
            }
        }

        stage('Recuperer les images') {
            steps {
                sh 'docker compose --project-name "$COMPOSE_PROJECT" pull backend frontend'
            }
        }

        stage('Deployer (mise a jour sans interruption)') {
            steps {
                // "up -d" ne recree que les services dont l'image ou la configuration a change :
                // postgres reste en place, les donnees du volume nomme ne sont jamais touchees.
                sh 'docker compose --project-name "$COMPOSE_PROJECT" up -d --remove-orphans'
            }
        }

        stage('Verifier la sante') {
            steps {
                script {
                    def ok = false
                    for (int i = 0; i < 20; i++) {
                        def status = sh(returnStatus: true, script: "curl -fsS ${HEALTH_URL} > /dev/null")
                        if (status == 0) { ok = true; break }
                        sleep(time: 3, unit: 'SECONDS')
                    }
                    sh 'docker compose --project-name "$COMPOSE_PROJECT" ps'
                    if (!ok) {
                        error("Le frontend ne repond pas sur ${HEALTH_URL} apres le deploiement")
                    }
                }
            }
        }
    }

    post {
        always {
            sh 'rm -f .env'
        }
        success {
            script { notify("Deploiement InternatAdmin reussi : backend=${params.BACKEND_TAG}, frontend=${params.FRONTEND_TAG}, build #${env.BUILD_NUMBER}") }
        }
        failure {
            script { notify("Deploiement InternatAdmin en echec : build #${env.BUILD_NUMBER}, voir ${env.BUILD_URL}") }
        }
    }
}

// Notification Slack si le credential est configure, sinon seulement dans le journal Jenkins
// (la carte T11 autorise les deux : "Slack ou journal").
def notify(String message) {
    echo message
    try {
        withCredentials([string(credentialsId: 'slack-webhook-url', variable: 'SLACK_WEBHOOK_URL')]) {
            // Message compose uniquement de tags et de numeros de build (voir les appels ci-dessus) :
            // jamais de guillemet a echapper, donc le JSON peut etre ecrit directement.
            writeFile file: 'slack-payload.json', text: "{\"text\": \"${message}\"}"
            sh 'curl -fsS -X POST -H "Content-Type: application/json" --data-binary @slack-payload.json "$SLACK_WEBHOOK_URL" > /dev/null'
            sh 'rm -f slack-payload.json'
        }
    } catch (ignored) {
        echo 'Notification Slack non configuree (credential slack-webhook-url absent) : notification journalisee seulement.'
    }
}
