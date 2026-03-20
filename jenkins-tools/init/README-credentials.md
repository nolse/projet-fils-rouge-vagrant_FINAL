# Configuration des Credentials Jenkins

## Prérequis
Jenkins doit être démarré et accessible sur http://<jenkins_ip>:8080

## 2 credentials à créer manuellement dans Jenkins

### 1. docker-hub-credentials
```
Jenkins > Manage Jenkins > Credentials > System > Global > Add Credentials
- Kind     : Username with password
- Username : alphabalde
- Password : <ton mot de passe Docker Hub>
- ID       : docker-hub-credentials
- Description : Docker Hub — alphabalde
```

### 2. ansible-ssh-key
```
Jenkins > Manage Jenkins > Credentials > System > Global > Add Credentials
- Kind     : Secret file
- File     : .secrets/projet-fil-rouge-key.pem
- ID       : ansible-ssh-key
- Description : Clé SSH AWS — projet fil rouge
```

## Vérification
Une fois les credentials créés, lancer le pipeline manuellement
depuis Jenkins > ic-webapp > Build Now

## Accès initial Jenkins

### 1. Récupérer le mot de passe admin initial
```bash
ssh -i .secrets/projet-fil-rouge-key.pem ubuntu@<jenkins_ip> "docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword"
```

### 2. Se connecter
- URL : http://<jenkins_ip>:8080
- Login : admin
- Password : résultat de la commande ci-dessus

### 3. Suivre le wizard Jenkins
- Installer les plugins suggérés
- Créer le premier utilisateur admin
- Configurer l'URL Jenkins
