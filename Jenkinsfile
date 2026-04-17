// ============================================================
// Jenkinsfile - Pipeline CI/CD ic-webapp - IC Group
// Declenche automatiquement a chaque push sur le repo
// ou manuellement depuis l'interface Jenkins
//
// Etapes :
//   1. Checkout          - recuperation du code source
//   2. Read Version      - lecture version/URLs depuis releases.txt
//   3. Build             - construction de l'image Docker
//   4. Test              - verification que le container demarre
//   5. Push              - push de l'image sur Docker Hub
//   6. Generate Inventory- generation dynamique de hosts.yml
//   7. Deploy            - deploiement via Ansible sur les 3 serveurs
//   8. Verify Deploy     - verification que les apps repondent
// ============================================================

pipeline {
    agent any

    environment {
        DOCKER_HUB_CREDS = credentials('docker-hub-credentials')
        DOCKER_HUB_USER  = 'alphabalde'
        IMAGE_NAME       = 'ic-webapp'
        ANSIBLE_KEY      = credentials('ansible-ssh-key')
    }

    stages {

        // ----------------------------------------------------
        // Etape 1 : Recuperation du code source
        // ----------------------------------------------------
        stage('Checkout') {
            steps {
                echo ' Recuperation du code source...'
                checkout scm
            }
        }

        // ----------------------------------------------------
        // Etape 2 : Lecture de la version depuis releases.txt
        // ----------------------------------------------------
        stage('Read Version') {
            steps {
                echo ' Lecture de la version depuis releases.txt...'
                script {
                    env.APP_VERSION = sh(
                        script: "awk '/version/{print \$2}' releases.txt",
                        returnStdout: true
                    ).trim()
                    env.ODOO_URL = sh(
                        script: "awk '/ODOO_URL/{print \$2}' releases.txt",
                        returnStdout: true
                    ).trim()
                    env.PGADMIN_URL = sh(
                        script: "awk '/PGADMIN_URL/{print \$2}' releases.txt",
                        returnStdout: true
                    ).trim()
                    echo "Version detectee   : ${env.APP_VERSION}"
                    echo "ODOO_URL           : ${env.ODOO_URL}"
                    echo "PGADMIN_URL        : ${env.PGADMIN_URL}"
                }
            }
        }

        // ----------------------------------------------------
        // Etape 3 : Build de l'image Docker
        // ----------------------------------------------------
        stage('Build') {
            steps {
                echo " Build de l'image ${IMAGE_NAME}:${env.APP_VERSION}..."
                sh """
                    docker build \\
                        --build-arg ODOO_URL=${env.ODOO_URL} \\
                        --build-arg PGADMIN_URL=${env.PGADMIN_URL} \\
                        -t ${DOCKER_HUB_USER}/${IMAGE_NAME}:${env.APP_VERSION} .
                """
            }
        }

        // ----------------------------------------------------
        // Etape 4 : Test du container ic-webapp
        // - Vérifie que le container démarre correctement
        // - Vérifie la taille de l'image (< 200MB)
        // - Vérifie le code HTTP 200
        // - Vérifie que le contenu "IC GROUP" est présent
        // - Vérifie que les liens Odoo et PgAdmin sont bien
        //   injectés dans la page
        // Le pipeline échoue si un test ne passe pas (exit 1)
        // ----------------------------------------------------
        stage('Test') {
            steps {
                echo ' Test du container ic-webapp...'
                sh """
                    # 1. Vérifier la taille de l'image avant de lancer le container
                    IMAGE_SIZE=\$(docker image inspect ${DOCKER_HUB_USER}/${IMAGE_NAME}:${env.APP_VERSION} --format='{{.Size}}')
                    echo "Taille image : \$IMAGE_SIZE bytes"
                    [ "\$IMAGE_SIZE" -lt 200000000 ] || exit 1
                    echo "Taille image OK (< 200MB)"

                    # 2. Lancer le container de test
                    docker run -d \\
                        --name test-ic-webapp \\
                        -p 8085:8080 \\
                        -e ODOO_URL=${env.ODOO_URL} \\
                        -e PGADMIN_URL=${env.PGADMIN_URL} \\
                        ${DOCKER_HUB_USER}/${IMAGE_NAME}:${env.APP_VERSION}
                    sleep 30 

                    # 3. Vérifier que le container tourne
                    docker ps | grep test-ic-webapp || exit 1
                    echo "Container démarré OK"

                    # 4. Vérifier le code HTTP 200
                    HTTP_CODE=\$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8085)
                    [ "\$HTTP_CODE" = "200" ] || exit 1
                    echo "HTTP 200 OK"

                    # 5. Vérifier que la page contient IC GROUP
                    curl -sf http://localhost:8085 | grep -i "IC GROUP" || exit 1
                    echo "Contenu IC GROUP OK"

                    # 6. Vérifier que le lien Odoo est bien injecté
                    curl -sf http://localhost:8085 | grep -i "${env.ODOO_URL}" || exit 1
                    echo "Lien Odoo présent OK"

                    # 7. Vérifier que le lien PgAdmin est bien injecté
                    curl -sf http://localhost:8085 | grep -i "${env.PGADMIN_URL}" || exit 1
                    echo "Lien PgAdmin présent OK"
                """
            }
            post {
                always {
                    sh '''
                        docker stop test-ic-webapp || true
                        docker rm   test-ic-webapp || true
                    '''
                }
            }
        }

        // ----------------------------------------------------
        // Etape 5 : Push de l'image sur Docker Hub
        // Tag version + tag latest
        // ----------------------------------------------------
        stage('Push') {
            steps {
                echo " Push de l'image sur Docker Hub..."
                sh '''
                    echo $DOCKER_HUB_CREDS_PSW | docker login -u $DOCKER_HUB_CREDS_USR --password-stdin
                    docker push $DOCKER_HUB_USER/$IMAGE_NAME:$APP_VERSION
                    docker tag  $DOCKER_HUB_USER/$IMAGE_NAME:$APP_VERSION \
                                $DOCKER_HUB_USER/$IMAGE_NAME:latest
                    docker push $DOCKER_HUB_USER/$IMAGE_NAME:latest
                '''
            }
        }

        // ----------------------------------------------------
        // Etape 6 : Generation de l inventaire Ansible
        // ----------------------------------------------------
        stage('Generate Inventory') {
            steps {
                echo ' Generation de l inventaire Ansible...'
                sh '''
                    cat > inventaire/hosts.yml << EOF
---
all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: $ANSIBLE_KEY
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
  children:
    jenkins:
      hosts:
        jenkins_server:
          ansible_host: $JENKINS_IP
    webapp:
      hosts:
        webapp_server:
          ansible_host: $WEBAPP_IP
    odoo:
      hosts:
        odoo_server:
          ansible_host: $ODOO_IP
EOF
                '''
            }
        }

        // ----------------------------------------------------
        // Etape 7 : Deploiement via Ansible
        // ----------------------------------------------------
        stage('Deploy') {
            steps {
                echo ' Deploiement via Ansible...'
                sh '''
                    chmod 600 $ANSIBLE_KEY
                    ansible-playbook \
                        -i inventaire/hosts.yml \
                        --private-key=$ANSIBLE_KEY \
                        -e "webapp_image=$DOCKER_HUB_USER/$IMAGE_NAME:$APP_VERSION" \
                        -e "odoo_url=$ODOO_URL" \
                        -e "pgadmin_url=$PGADMIN_URL" \
                        playbook.yml
                '''
            }
        }

        // ----------------------------------------------------
        // Etape 8 : Verification post-deploiement
        // Vérifie que chaque application répond correctement
        // après le déploiement Ansible
        // ----------------------------------------------------
        stage('Verify Deploy') {
            steps {
                echo ' Verification du deploiement sur les serveurs...'
                sh '''
                    sleep 15
                    curl -sf http://$ODOO_IP:8069 || exit 1
                    echo "Odoo OK"
                    curl -sf http://$WEBAPP_IP:5050 || exit 1
                    echo "PgAdmin OK"
                    curl -sf http://$WEBAPP_IP:8080 || exit 1
                    echo "ic-webapp OK"
                '''
            }
        }

    }  //  ferme stages

    // --------------------------------------------------------
    // Notifications Slack selon le resultat du pipeline
    // Plugin "Slack Notification" requis
    // Canal : #jenkins-eazytraining-alpha-alerte
    // --------------------------------------------------------
    post {
        success {
            slackSend(
                channel: '#jenkins-eazytraining-alpha-alerte',
                color: '#00FF00',
                message: "✅ SUCCESS: ${env.JOB_NAME} [${env.BUILD_NUMBER}] - ic-webapp:${env.APP_VERSION} deployee ! ${env.BUILD_URL}"
            )
        }
        failure {
            slackSend(
                channel: '#jenkins-eazytraining-alpha-alerte',
                color: '#FF0000',
                message: "❌ FAILED: ${env.JOB_NAME} [${env.BUILD_NUMBER}] - ic-webapp:${env.APP_VERSION} ${env.BUILD_URL}"
            )
        }
        unstable {
            slackSend(
                channel: '#jenkins-eazytraining-alpha-alerte',
                color: '#FFA500',
                message: "⚠️ UNSTABLE: ${env.JOB_NAME} [${env.BUILD_NUMBER}] - ic-webapp:${env.APP_VERSION} ${env.BUILD_URL}"
            )
        }
        always {
            sh 'docker image prune -f || true'
        }
    }

}  //  ferme pipeline
