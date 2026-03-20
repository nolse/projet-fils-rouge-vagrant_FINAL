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
