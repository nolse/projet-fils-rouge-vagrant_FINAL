// ============================================================
// Jenkinsfile — Pipeline CI/CD complet
//
// Ce pipeline couvre les 3 grandes phases du projet :
//   1. CI  : Build + Test + Push de l'image Docker ic-webapp
//   2. IaC : Provisioning AWS via Terraform (EC2 + EIPs)
//   3. CD  : Déploiement de la stack applicative via Ansible
//
// Prérequis Jenkins (Credentials) :
//   - docker-hub-credentials : Username/Password Docker Hub
//   - ansible-ssh-key        : Secret file (clé PEM AWS)
//   - aws-credentials        : Secret text ou AWS credentials
//                              (AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY)
//
// Prérequis outils sur l'agent Jenkins :
//   - Docker
//   - Terraform
//   - Ansible (ansible-core 2.15.x via pip3)
//   - collection community.docker 3.10.0
//   - jq
//   - aws cli configuré
// ============================================================

pipeline {
    agent any

    environment {
        // --------------------------------------------------------
        // Credentials Docker Hub (injectés par Jenkins)
        // DOCKER_HUB_CREDS_USR = login
        // DOCKER_HUB_CREDS_PSW = mot de passe
        // --------------------------------------------------------
        DOCKER_HUB_CREDS = credentials('docker-hub-credentials')

        // Compte Docker Hub et nom de l'image
        DOCKER_HUB_USER  = 'alphabalde'
        IMAGE_NAME       = 'ic-webapp'

        // --------------------------------------------------------
        // Clé SSH pour Ansible (Secret file Jenkins)
        // Jenkins écrit le fichier PEM dans un chemin temporaire
        // et expose ce chemin dans la variable ANSIBLE_KEY
        // --------------------------------------------------------
        ANSIBLE_KEY = credentials('ansible-ssh-key')

        // --------------------------------------------------------
        // Credentials AWS pour Terraform
        // Injectés comme variables d'environnement standard
        // Terraform les lit automatiquement (AWS_ACCESS_KEY_ID, etc.)
        // --------------------------------------------------------
        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')

        // Région AWS cible (doit correspondre à celle utilisée dans Terraform)
        AWS_DEFAULT_REGION = 'us-east-1'

        // --------------------------------------------------------
        // Délais d'attente (en secondes)
        // AWS_BOOT_WAIT : temps pour que les EC2 démarrent et acceptent SSH
        // PLAY_WAIT     : délai entre les plays Ansible
        // --------------------------------------------------------
        AWS_BOOT_WAIT = '90'
        PLAY_WAIT     = '20'
    }

    stages {

        // ----------------------------------------------------
        // Stage 1 : Récupération du code source
        // Cloner/actualiser le dépôt GitHub sur l'agent Jenkins
        // ----------------------------------------------------
        stage('Checkout') {
            steps {
                echo '==> [1/9] Récupération du code source...'
                // checkout scm utilise la configuration du job Jenkins
                // (URL du dépôt et branche définis dans la config du job)
                checkout scm
            }
        }

        // ----------------------------------------------------
        // Stage 2 : Lecture de la version depuis releases.txt
        // releases.txt contient les variables :
        //   version    <tag>
        //   ODOO_URL   <url>
        //   PGADMIN_URL <url>
        // Ces valeurs sont injectées dans les stages suivants
        // ----------------------------------------------------
        stage('Read Version') {
            steps {
                echo '==> [2/9] Lecture de la version depuis releases.txt...'
                script {
                    // Extraction de la version de l'image Docker
                    env.APP_VERSION = sh(
                        script: "awk '/version/{print \$2}' releases.txt",
                        returnStdout: true
                    ).trim()

                    // Extraction de l'URL Odoo (passée au conteneur ic-webapp)
                    env.ODOO_URL = sh(
                        script: "awk '/ODOO_URL/{print \$2}' releases.txt",
                        returnStdout: true
                    ).trim()

                    // Extraction de l'URL pgAdmin (passée au conteneur ic-webapp)
                    env.PGADMIN_URL = sh(
                        script: "awk '/PGADMIN_URL/{print \$2}' releases.txt",
                        returnStdout: true
                    ).trim()

                    echo "Version détectée    : ${env.APP_VERSION}"
                    echo "ODOO_URL            : ${env.ODOO_URL}"
                    echo "PGADMIN_URL         : ${env.PGADMIN_URL}"
                }
            }
        }

        // ----------------------------------------------------
        // Stage 3 : Build de l'image Docker
        // Construit l'image ic-webapp à partir du Dockerfile
        // et tague avec la version lue dans releases.txt
        // ----------------------------------------------------
        stage('Build') {
            steps {
                echo "==> [3/9] Build de l'image ${IMAGE_NAME}:${env.APP_VERSION}..."
                sh """
                    docker build \\
                        --build-arg ODOO_URL=${env.ODOO_URL} \\
                        --build-arg PGADMIN_URL=${env.PGADMIN_URL} \\
                        -t ${DOCKER_HUB_USER}/${IMAGE_NAME}:${env.APP_VERSION} .
                """
            }
        }

        // ----------------------------------------------------
        // Stage 4 : Tests du conteneur ic-webapp
        //
        // IMPORTANT — Docker-in-Docker :
        //   Jenkins tourne lui-même dans Docker, donc "localhost"
        //   depuis le shell Jenkins ne pointe pas vers le conteneur
        //   de test. On utilise "docker exec" pour faire les curl
        //   depuis l'intérieur du conteneur de test.
        //
        // Tests effectués :
        //   1. Taille de l'image (< 200 MB)
        //   2. Démarrage du conteneur
        //   3. Réponse HTTP 200
        //   4. Présence du texte "IC GROUP" dans la page
        //   5. Présence des URLs Odoo et pgAdmin dans la page
        // ----------------------------------------------------
        stage('Test') {
            steps {
                echo '==> [4/9] Tests du conteneur ic-webapp...'
                sh '''
                    # --- Test 1 : Taille de l'image ---
                    IMAGE_SIZE=$(docker image inspect $DOCKER_HUB_USER/$IMAGE_NAME:$APP_VERSION \
                        --format='{{.Size}}')
                    echo "Taille image : $IMAGE_SIZE bytes"
                    [ "$IMAGE_SIZE" -lt 200000000 ] || { echo "ERREUR : image > 200MB"; exit 1; }
                    echo "OK Taille image < 200MB"

                    # --- Test 2 : Démarrage du conteneur ---
                    docker run -d \
                        --name test-ic-webapp \
                        -p 8085:8080 \
                        -e ODOO_URL=$ODOO_URL \
                        -e PGADMIN_URL=$PGADMIN_URL \
                        $DOCKER_HUB_USER/$IMAGE_NAME:$APP_VERSION

                    # Attendre que Flask démarre (Alpine peut être lent)
                    sleep 10

                    # Vérifier que le conteneur est bien en cours d'exécution
                    docker ps | grep test-ic-webapp \
                        || { echo "ERREUR : conteneur non démarré"; exit 1; }
                    echo "OK Conteneur démarré"

                    # --- Test 3 : Réponse HTTP 200 (via docker exec) ---
                    HTTP_CODE=$(docker exec test-ic-webapp \
                        curl -s -o /dev/null -w "%{http_code}" http://localhost:8080)
                    echo "HTTP code : $HTTP_CODE"
                    [ "$HTTP_CODE" = "200" ] \
                        || { echo "ERREUR : HTTP $HTTP_CODE attendu 200"; exit 1; }
                    echo "OK HTTP 200"

                    # --- Test 4 : Présence du texte "IC GROUP" ---
                    docker exec test-ic-webapp \
                        curl -s http://localhost:8080 | grep -i "IC GROUP" \
                        || { echo "ERREUR : texte IC GROUP absent"; exit 1; }
                    echo "OK Texte IC GROUP présent"

                    # --- Test 5 : Présence des URLs dans la page ---
                    docker exec test-ic-webapp \
                        curl -s http://localhost:8080 | grep -i "$ODOO_URL" \
                        || { echo "ERREUR : lien Odoo absent"; exit 1; }
                    echo "OK Lien Odoo présent"

                    docker exec test-ic-webapp \
                        curl -s http://localhost:8080 | grep -i "$PGADMIN_URL" \
                        || { echo "ERREUR : lien pgAdmin absent"; exit 1; }
                    echo "OK Lien pgAdmin présent"
                '''
            }
            post {
                // Nettoyage du conteneur de test dans tous les cas
                // (succès ou échec) pour ne pas polluer l'agent Jenkins
                always {
                    sh '''
                        docker stop test-ic-webapp || true
                        docker rm   test-ic-webapp || true
                    '''
                }
            }
        }

        // ----------------------------------------------------
        // Stage 5 : Push de l'image sur Docker Hub
        // Pousse deux tags :
        //   - le tag versionné (ex: 1.0)
        //   - le tag "latest" pour toujours pointer sur la dernière
        // ----------------------------------------------------
        stage('Push') {
            steps {
                echo "==> [5/9] Push de l'image sur Docker Hub..."
                sh '''
                    # Authentification Docker Hub avec les credentials Jenkins
                    echo $DOCKER_HUB_CREDS_PSW \
                        | docker login -u $DOCKER_HUB_CREDS_USR --password-stdin

                    # Push du tag versionné
                    docker push $DOCKER_HUB_USER/$IMAGE_NAME:$APP_VERSION

                    # Tag "latest" et push
                    docker tag  $DOCKER_HUB_USER/$IMAGE_NAME:$APP_VERSION \
                                $DOCKER_HUB_USER/$IMAGE_NAME:latest
                    docker push $DOCKER_HUB_USER/$IMAGE_NAME:latest

                    echo "OK Image poussée sur Docker Hub"
                '''
            }
        }

        // ----------------------------------------------------
        // Stage 6 : Provisioning AWS avec Terraform (init)
        //
        // terraform init initialise le backend S3 et télécharge
        // les providers AWS nécessaires.
        // -reconfigure force la réinitialisation même si un
        // backend est déjà configuré localement.
        // ----------------------------------------------------
        stage('Terraform Init') {
            steps {
                echo '==> [6/9] Initialisation Terraform...'
                sh '''
                    cd terraform/app
                    terraform init -reconfigure
                    echo "OK Terraform initialisé"
                '''
            }
        }

        // ----------------------------------------------------
        // Stage 7 : Provisioning AWS avec Terraform (apply)
        //
        // Crée les ressources AWS :
        //   - 3 instances EC2 (jenkins, webapp, odoo)
        //   - 3 Elastic IPs associées
        //   - Security Group avec les ports nécessaires
        //
        // Les IPs publiques sont exportées dans terraform_ips.json
        // pour être consommées par le stage Generate Inventory.
        //
        // -auto-approve supprime la confirmation manuelle
        // (obligatoire en pipeline CI/CD)
        // ----------------------------------------------------
        stage('Terraform Apply') {
            steps {
                echo '==> [7/9] Provisioning AWS avec Terraform...'
                sh '''
                    cd terraform/app

                    # Création / mise à jour de l'infrastructure AWS
                    terraform apply -auto-approve

                    echo "OK Infrastructure AWS créée"

                    # Export des IPs publiques au format JSON
                    # Ce fichier sera lu par generate_inventory.sh
                    terraform output -json public_ips \
                        > ../../inventaire/terraform_ips.json

                    echo "OK IPs exportées dans inventaire/terraform_ips.json"

                    # Affichage récapitulatif des IPs
                    echo ""
                    echo "--- IPs publiques AWS ---"
                    cat ../../inventaire/terraform_ips.json
                '''
            }
        }

        // ----------------------------------------------------
        // Stage 8 : Génération de l'inventaire Ansible
        //
        // Le script generate_inventory.sh lit terraform_ips.json
        // et génère le fichier inventaire/hosts.yml avec les IPs
        // des 3 serveurs (jenkins, webapp, odoo).
        //
        // La clé SSH est injectée par Jenkins (Secret file)
        // et son chemin est disponible dans $ANSIBLE_KEY.
        // ----------------------------------------------------
        stage('Generate Inventory') {
            steps {
                echo '==> [8/9] Génération de l inventaire Ansible...'
                sh '''
                    # Vérifier que le fichier des IPs est bien présent
                    [ -f inventaire/terraform_ips.json ] \
                        || { echo "ERREUR : terraform_ips.json introuvable"; exit 1; }

                    # Générer hosts.yml depuis terraform_ips.json
                    bash inventaire/generate_inventory.sh

                    echo "OK Inventaire généré"
                    echo ""
                    echo "--- Contenu de hosts.yml ---"
                    cat inventaire/hosts.yml
                '''
            }
        }

        // ----------------------------------------------------
        // Stage 9 : Déploiement via Ansible
        //
        // Déploie la stack applicative sur les 3 serveurs AWS
        // dans l'ordre suivant (dépendances) :
        //   1. odoo  : PostgreSQL + Odoo
        //   2. webapp: ic-webapp + pgAdmin
        //   3. jenkins: Jenkins
        //
        // Un délai est respecté entre chaque play pour laisser
        // les services démarrer correctement.
        //
        // Première étape : vérification SSH (ping Ansible)
        // Si les instances ne répondent pas encore (cloud-init),
        // on attend et on réessaie une fois.
        // ----------------------------------------------------
        stage('Deploy') {
            steps {
                echo '==> [9/9] Déploiement via Ansible...'
                sh '''
                    # La clé PEM doit avoir les bons droits (600)
                    # sinon SSH et Ansible refusent de l'utiliser
                    chmod 600 $ANSIBLE_KEY

                    # ------------------------------------------------
                    # Attente du démarrage des instances EC2
                    # Les instances AWS ont besoin de temps pour :
                    #   - démarrer l'OS (cloud-init)
                    #   - lancer le service SSH
                    # ------------------------------------------------
                    echo "Attente démarrage SSH des instances EC2 (${AWS_BOOT_WAIT}s)..."
                    sleep $AWS_BOOT_WAIT

                    # ------------------------------------------------
                    # Vérification SSH avec ansible ping
                    # Si les instances ne répondent pas encore,
                    # on attend 30s supplémentaires et on réessaie
                    # ------------------------------------------------
                    echo "Vérification SSH (ansible ping)..."
                    ansible all \
                        -i inventaire/hosts.yml \
                        --private-key=$ANSIBLE_KEY \
                        -m ping \
                        --timeout=10 \
                    || {
                        echo "SSH pas encore prêt, attente 30s supplémentaires..."
                        sleep 30
                        ansible all \
                            -i inventaire/hosts.yml \
                            --private-key=$ANSIBLE_KEY \
                            -m ping \
                            --timeout=10 \
                        || { echo "ERREUR : instances SSH inaccessibles"; exit 1; }
                    }
                    echo "OK Toutes les instances sont accessibles"

                    # ------------------------------------------------
                    # Play 1 : Odoo + PostgreSQL
                    # Odoo doit démarrer en premier car ic-webapp
                    # a besoin de son URL pour la configuration
                    # ------------------------------------------------
                    echo ""
                    echo "--- Play 1/3 : Déploiement Odoo + PostgreSQL ---"
                    ansible-playbook \
                        -i inventaire/hosts.yml \
                        --private-key=$ANSIBLE_KEY \
                        --limit odoo \
                        -e "webapp_image=$DOCKER_HUB_USER/$IMAGE_NAME:$APP_VERSION" \
                        -e "odoo_url=$ODOO_URL" \
                        -e "pgadmin_url=$PGADMIN_URL" \
                        playbook.yml -v

                    echo "Attente démarrage Odoo + PostgreSQL (${PLAY_WAIT}s)..."
                    sleep $PLAY_WAIT

                    # ------------------------------------------------
                    # Play 2 : ic-webapp + pgAdmin
                    # ------------------------------------------------
                    echo ""
                    echo "--- Play 2/3 : Déploiement ic-webapp + pgAdmin ---"
                    ansible-playbook \
                        -i inventaire/hosts.yml \
                        --private-key=$ANSIBLE_KEY \
                        --limit webapp \
                        -e "webapp_image=$DOCKER_HUB_USER/$IMAGE_NAME:$APP_VERSION" \
                        -e "odoo_url=$ODOO_URL" \
                        -e "pgadmin_url=$PGADMIN_URL" \
                        playbook.yml -v

                    echo "Attente démarrage ic-webapp + pgAdmin (${PLAY_WAIT}s)..."
                    sleep $PLAY_WAIT

                    # ------------------------------------------------
                    # Play 3 : Jenkins
                    # Jenkins en dernier car il ne dépend d'aucun autre service
                    # ------------------------------------------------
                    echo ""
                    echo "--- Play 3/3 : Déploiement Jenkins ---"
                    ansible-playbook \
                        -i inventaire/hosts.yml \
                        --private-key=$ANSIBLE_KEY \
                        --limit jenkins \
                        -e "webapp_image=$DOCKER_HUB_USER/$IMAGE_NAME:$APP_VERSION" \
                        -e "odoo_url=$ODOO_URL" \
                        -e "pgadmin_url=$PGADMIN_URL" \
                        playbook.yml -v

                    echo ""
                    echo "OK Déploiement complet terminé"

                    # ------------------------------------------------
                    # Récapitulatif des URLs d'accès
                    # ------------------------------------------------
                    JENKINS_IP=$(jq -r '.jenkins' inventaire/terraform_ips.json)
                    WEBAPP_IP=$(jq  -r '.webapp'  inventaire/terraform_ips.json)
                    ODOO_IP=$(jq    -r '.odoo'    inventaire/terraform_ips.json)

                    echo ""
                    echo "============================================"
                    echo " Accès aux services déployés :"
                    echo "   Jenkins   -> http://${JENKINS_IP}:8080"
                    echo "   ic-webapp -> http://${WEBAPP_IP}"
                    echo "   pgAdmin   -> http://${WEBAPP_IP}:5050"
                    echo "   Odoo      -> http://${ODOO_IP}:8069"
                    echo "============================================"
                '''
            }
        }
    }

    // --------------------------------------------------------
    // Post-actions globales du pipeline
    // Exécutées après tous les stages, dans tous les cas
    // --------------------------------------------------------
    post {

        // Notification Slack en cas de succès (vert)
        success {
            slackSend(
                channel: '#jenkins-eazytraining-alpha-alerte',
                color: '#00FF00',
                message: """
                    SUCCESS : ${env.JOB_NAME} [${env.BUILD_NUMBER}]
                    Image   : ${DOCKER_HUB_USER}/${IMAGE_NAME}:${env.APP_VERSION}
                    Détails : ${env.BUILD_URL}
                """.stripIndent()
            )
        }

        // Notification Slack en cas d'échec (rouge)
        failure {
            slackSend(
                channel: '#jenkins-eazytraining-alpha-alerte',
                color: '#FF0000',
                message: """
                    FAILED : ${env.JOB_NAME} [${env.BUILD_NUMBER}]
                    Détails : ${env.BUILD_URL}
                """.stripIndent()
            )
        }

        // Nettoyage des images Docker orphelines dans tous les cas
        // Libère de l'espace disque sur l'agent Jenkins
        always {
            sh 'docker image prune -f || true'
        }
    }
}
