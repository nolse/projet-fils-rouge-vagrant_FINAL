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
// ============================================================

pipeline {
    agent any

    // --------------------------------------------------------
    // Variables globales du pipeline
    // La version est lue depuis releases.txt et utilisee
    // comme tag de l'image Docker
    // IPs des serveurs stockees dans Jenkins Global Variables
    // --------------------------------------------------------
    environment {
        // Identifiants Docker Hub stockes dans Jenkins Credentials
        DOCKER_HUB_CREDS = credentials('docker-hub-credentials')
        DOCKER_HUB_USER  = 'alphabalde'
        IMAGE_NAME       = 'ic-webapp'
        // Cle SSH pour Ansible - stockee dans Jenkins Credentials
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
        // La version sera utilisee comme tag de l'image Docker
        // ----------------------------------------------------
        stage('Read Version') {
            steps {
                echo ' Lecture de la version depuis releases.txt...'
                script {
                    // Extraction via awk (meme mecanisme que le Dockerfile)
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
        // Tag = version lue dans releases.txt
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
        // Etape 4 : Test du container
        // Lance un container, verifie qu'il repond sur le port 8085
        // puis le supprime
        // ----------------------------------------------------
        stage('Test') {
            steps {
                echo ' Test du container ic-webapp...'
                sh """
                    docker run -d \\
                        --name test-ic-webapp \\
                        -p 8085:8080 \\
                        -e ODOO_URL=${env.ODOO_URL} \\
                        -e PGADMIN_URL=${env.PGADMIN_URL} \\
                        ${DOCKER_HUB_USER}/${IMAGE_NAME}:${env.APP_VERSION}
                    sleep 5
                    docker ps | grep test-ic-webapp
                    curl -sf http://localhost:8085 | grep -i "IC GROUP" && echo " Test OK" || echo " Test FAILED"
                """
            }
            post {
                always {
                    // Nettoyage du container de test dans tous les cas
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
        // Guillemets simples intentionnels : evite l'interpolation
        // Groovy sur DOCKER_HUB_CREDS_PSW (securite credentials)
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
        // Etape 6 : Generation de l'inventaire Ansible
        // hosts.yml est gitignore - genere dynamiquement
        // depuis les IPs stockees dans Jenkins Global Variables
        // (JENKINS_IP, WEBAPP_IP, ODOO_IP)
        // ----------------------------------------------------
        stage('Generate Inventory') {
            steps {
                echo ' Generation de l'inventaire Ansible...'
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
        // Lance le playbook principal sur les 3 serveurs
        // Guillemets simples intentionnels : evite l'interpolation
        // Groovy sur ANSIBLE_KEY (securite credentials)
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

    }  //  ferme stages

    // --------------------------------------------------------
    // Notifications post-pipeline
    // --------------------------------------------------------
    post {
        success {
            echo " Pipeline termine avec succes - version ${env.APP_VERSION} deployee !"
        }
        failure {
            echo " Pipeline en echec - verifiez les logs ci-dessus."
        }
        always {
            // Nettoyage des images Docker non utilisees pour liberer l'espace
            sh 'docker image prune -f || true'
        }
    }

}  //  ferme pipeline
