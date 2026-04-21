# Projet Fil Rouge — IC Group DevOps

Deploiement complet d'une infrastructure DevOps en 3 parties :
conteneurisation, CI/CD Jenkins + Ansible + Terraform, et orchestration Kubernetes.
Tout est reproductible depuis une VM Vagrant Ubuntu 22.04.

## Stack technique

| Outil | Role |
|---|---|
| Docker | Conteneurisation des applications |
| Terraform | Provisioning infrastructure AWS |
| Ansible | Deploiement et configuration des serveurs |
| Jenkins | Pipeline CI/CD automatise |
| Minikube | Cluster Kubernetes local sur VM Vagrant |

## Applications deployees

| Application | Image | Description |
|---|---|---|
| ic-webapp | alphabalde/ic-webapp:1.0 | Site vitrine IC Group |
| Odoo | odoo:13.0 | ERP metier |
| PostgreSQL | postgres:13 | Base de donnees Odoo |
| pgAdmin | dpage/pgadmin4 | Interface admin BDD |
| Jenkins | jenkins/jenkins:lts | Pipeline CI/CD |

---

## Prerequis

### 1. Demarrer la VM Vagrant

```bash
vagrant up && vagrant ssh
```

### 2. Cloner le repo sous /home/vagrant

> **IMPORTANT** : Travailler obligatoirement sous `/home/vagrant` et non sous `/mnt/`.
> Le dossier `/mnt/` est world-writable — Ansible refusera de lire `ansible.cfg`
> depuis ce chemin (warning "world writable directory" + inventaire ignore).

```bash
cd ~
git clone https://github.com/nolse/projet-fils-rouge-vagrant_FINAL.git
cd projet-fils-rouge-vagrant
```

Verifier que ansible.cfg est bien reconnu :
```bash
ansible --version | grep "config file"
# Attendu : config file = /home/vagrant/sondes-projet-fils-rouge/projet-fils-rouge-vagrant_INGDM/ansible.cfg
```
### 3. Placer la cle SSH AWS dans ~/.ssh/

> La cle `projet-fil-rouge-key.pem` doit imperativement etre dans `~/.ssh/`
> avec les permissions 600. SSH refuse toute cle avec des permissions trop ouvertes.

```bash
cp .secrets/projet-fil-rouge-key.pem ~/.ssh/
chmod 600 ~/.ssh/projet-fil-rouge-key.pem

# Verifier
ls -la ~/.ssh/projet-fil-rouge-key.pem
# Attendu : -rw------- 1 vagrant vagrant ...
```

### 4. Creer le dossier .secrets/ (non versionne, dans .gitignore)

```bash
mkdir -p .secrets
cp ~/.ssh/projet-fil-rouge-key.pem .secrets/
```

### 5. Installer les prerequis via bootstrap
# Le script verifie si c'est présent sinon l'install

```bash
bash bootstrap.sh
```

> **Note** : Ansible est installe via `pip3` et non via `apt`.
> La version systeme (2.10.x) est trop ancienne pour `community.docker >= 3.0.0`.
> Le PATH est mis a jour automatiquement dans `~/.bashrc`.

Recharger le PATH apres bootstrap :
```bash
source ~/.bashrc
ansible --version | head -1
# Attendu : ansible [core 2.17.x]
```

### 6. Configurer les credentials AWS

```bash
aws configure
# AWS Access Key ID     : [votre cle IAM]
# AWS Secret Access Key : [votre secret]
# Default region name   : us-east-1
# Default output format : json
```

Verifier :
```bash
aws sts get-caller-identity
aws s3 ls s3://terraform-backend-balde
aws ec2 describe-key-pairs --key-names projet-fil-rouge-key --region us-east-1
```

### 7. Configurer Docker DNS pour Minikube

> **IMPORTANT** : Sans cette configuration, Minikube ne peut pas resoudre
> les noms de domaine externes (docker.io, github.com) et les pods restent
> bloques en `ContainerCreating`.

```bash
sudo bash -c 'cat > /etc/docker/daemon.json << EOF
{
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF'
sudo systemctl restart docker
```

---

## Partie 1 — Conteneurisation Docker

Image construite et publiee sur Docker Hub.

```bash
# Verifier l'image sur Docker Hub
docker pull alphabalde/ic-webapp:1.0

# Rebuilder si besoin (depuis la racine du repo)
docker build -t alphabalde/ic-webapp:1.0 .
docker push alphabalde/ic-webapp:1.0
```

**Image disponible :** https://hub.docker.com/r/alphabalde/ic-webapp

Test rapide :
```bash
docker run -d \
  --name test-ic-webapp \
  -p 8085:8080 \
  -e ODOO_URL=https://www.odoo.com \
  -e PGADMIN_URL=https://www.pgadmin.org \
  alphabalde/ic-webapp:1.0

curl http://localhost:8085
docker rm -f test-ic-webapp
```
---

## Partie 2 — CI/CD Jenkins + Ansible + Terraform

### Etape 1 — Provisioning infrastructure AWS

```bash
bash reproduce_infra.sh
```

Ce script :
- Initialise Terraform (backend S3 : `terraform-backend-balde`)
- Cree 3 instances EC2 + Security Group + EIPs
- Exporte les IPs dans `inventaire/terraform_ips.json`

Resultat attendu :
```
jenkins = "X.X.X.X"
odoo    = "X.X.X.X"
webapp  = "X.X.X.X"
```

### Etape 2 — Deploiement initial via Ansible

> **Types d'instances EC2 utilisées par défaut :**
> | Serveur | Type | Raison |
> |---|---|---|
> | Jenkins | t3.medium | CI/CD — besoin de ressources |
> | Odoo | t3.medium | ERP — besoin de ressources |
> | webapp | t3.micro | Site vitrine + pgAdmin |
>
> Pour modifier le type d'instance, éditer `terraform/app/main.tf`
> et changer la valeur `instance_type` du serveur concerné avant de lancer `reproduce_infra.sh`.

> Ce script effectue le deploiement initial avant configuration de Jenkins.
> Une fois Jenkins configure, c'est le pipeline CI/CD qui prend le relai.

```bash
bash reproduce_deploy.sh
```

Ce script :
- Verifie la cle SSH
- Installe les dependances Ansible (collections)
- Genere l'inventaire depuis `terraform_ips.json`
- Attend que les instances AWS soient disponibles en SSH
- Deploie Odoo, ic-webapp, pgAdmin et Jenkins via Ansible (4 roles)

### Identifiants de connexion

| Application | Identifiant | Mot de passe |
|---|---|---|
| pgAdmin | admin@icgroup.fr | pgadmin_password |
| Odoo | admin | admin |
| PostgreSQL (via pgAdmin) | odoo | odoo_password |

Connexion PostgreSQL depuis pgAdmin : Host = `postgres-service` | Port = `5432` | Database = `odoo`

> **Première connexion Odoo** : à la première ouverture, Odoo affiche un formulaire
> de création de base de données. Remplir les champs puis créer la base avant
> de pouvoir se connecter avec les identifiants admin/admin.


###  Troubleshooting :

sysctl permission denied dans jenkins_role — Ces warnings apparaissent lors de l'installation de paquets apt dans le container Jenkins (Docker sans privilèges kernel). Ils sont non bloquants et n'affectent pas le fonctionnement de Jenkins.

### Etape 3 — Configuration Jenkins

Ouvrir `http://<jenkins_ip>:8080`

**Recuperer le mot de passe initial :**
```bash
# Se connecter au serveur Jenkins
ssh -i ~/.ssh/projet-fil-rouge-key.pem ubuntu@<jenkins_ip>

# Recuperer le mot de passe (sans sudo si reconnexion apres deploy)
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

> Si `permission denied` sur docker : se deconnecter et se reconnecter en SSH.
> Le groupe docker est charge uniquement a la connexion.

**Dans l'interface Jenkins :**
1. Unlock Jenkins avec le mot de passe initial
2. Install suggested plugins
3. Creer le compte admin

**Ajouter les Credentials** — Manage Jenkins → Credentials → Global → Add :

| ID | Kind | Contenu |
|---|---|---|
| `ansible-ssh-key` | **Secret file** | Uploader `projet-fil-rouge-key.pem` |
| `docker-hub-credentials` | Username with password | Login Docker Hub |

> **Important** : Utiliser le type **Secret file** pour `ansible-ssh-key`.
> Le type "SSH Username with private key" provoque une erreur `error in libcrypto`
> lors de l'execution d'Ansible depuis Jenkins.

**Ajouter les Variables globales** — Manage Jenkins → System → Global properties → Environment variables :

| Variable | Valeur |
|---|---|
| JENKINS_IP | IP du serveur Jenkins |
| WEBAPP_IP | IP du serveur webapp |
| ODOO_IP | IP du serveur Odoo |

**Creer le job Pipeline :**
```
New Item → ic-webapp → Pipeline → OK
Definition           : Pipeline script from SCM
SCM                  : Git
Repository URL       : https://github.com/nolse/projet-fils-rouge-vagrant_FINAL.git 
Branch               : */main
Script Path          : Jenkinsfile
Lightweight checkout : decocher
```

> **Important** : Decocher "Lightweight checkout" — sinon Jenkins ne recupere
> que le Jenkinsfile et les stages Build, Deploy... echouent faute de fichiers.

**Activer le trigger automatique :**
```
Configure → Build Triggers → GitHub hook trigger for GITScm polling
```

**Configurer le webhook GitHub :**
```
Repo GitHub → Settings → Webhooks → Add webhook
Payload URL  : http://<jenkins_ip>:8080/github-webhook/
Content type : application/json
Trigger      : Just the push event

```
#### Configuration rapide

1. Installer le plugin Slack :
   - Manage Jenkins → Plugins → Available plugins
   - Rechercher "Slack Notification" → Install
   - Redémarrer Jenkins si demandé

2. Récupérer le token Slack :
   - Slack → Apps → Jenkins CI → Configuration → copier le token

3. Ajouter le credential dans Jenkins :
   - Manage Jenkins → Credentials → Global → Add Credentials
   - Kind : **Secret text**
   - Secret : token Slack
   - ID : `slack-token`

4. Configurer Slack dans Jenkins :
   - Manage Jenkins → Configure System → Slack
   - Workspace : votre workspace # exemple pozosworkspace
   - Credential : `slack-token`
   - Channel : `#jenkins-eazytraining-alpha-alerte`

Tester avec **Test Connection** → message "Success"

### Notifications Slack (Jenkins)

Le pipeline envoie automatiquement une notification Slack :
- Succes → message vert
- Echec → message rouge

Tester avec **Test Connection** → message "Success"

> Une fois Jenkins configuré à l'étape 3, c'est le pipeline CI/CD qui prendra le relai.

La configuration Slack doit être effectuée avant le premier run du pipeline. Sans le credential slack-token, 
le pipeline échouera sur l'étape de notification.
```
### Etape 4 — Run manuel (version 1.0)

Dans Jenkins → job `ic-webapp` → **Build Now**

Le pipeline execute 7 stages :
1. Checkout — recuperation du code source
2. Read Version — lecture version/URLs depuis releases.txt
3. Build — docker build ic-webapp:1.0
4. Test — verification que le container repond sur :8085
5. Push — docker push sur Docker Hub (tag 1.0 + latest)
6. Generate Inventory — generation dynamique de hosts.yml avec les IPs AWS
7. Deploy — ansible-playbook sur les 3 serveurs AWS

### Tests automatises du pipeline

Le pipeline Jenkins integre une etape de test du container `ic-webapp` avant le push sur Docker Hub.

Ces tests permettent de verifier rapidement que l'application fonctionne correctement avant de la deployer.

Verifications effectuees :

- Taille de l'image Docker (< 200MB)
- Demarrage du container
- Reponse HTTP (code 200)
- Verification du contenu de la page :
  - Presence du texte "IC GROUP"
  - Presence des liens Odoo et pgAdmin

Les tests sont executes directement depuis le container (`docker exec`) car Jenkins tourne lui-meme dans Docker.

> Si un test echoue, le pipeline est automatiquement interrompu.

### Etape 5 — Run automatique (version 1.1)

Modifier `releases.txt` pour declencher automatiquement le pipeline via webhook :

```bash
sed -i 's/^version 1.0/version 1.1/' releases.txt
git add releases.txt
git commit -m "release: version 1.1"
git push
```

Le webhook GitHub declenche automatiquement le pipeline Jenkins.
Verifier dans Jenkins que le build se lance sans intervention manuelle.

> **Remise a zero apres test** :
> ```bash
> sed -i 's/^version 1.1/version 1.0/' releases.txt
> git add releases.txt && git commit -m "reset: version 1.0" && git push
> ```

### Acces aux services

| Application | URL |
|---|---|
| Jenkins | http://<jenkins_ip>:8080 |
| ic-webapp | http://<webapp_ip> |
| pgAdmin | http://<webapp_ip>:5050 |
| Odoo | http://<odoo_ip>:8069 |

### Fin de session AWS

```bash
bash reproduce_infra.sh destroy
```
---

## Partie 3 — Kubernetes (Minikube)

Deploiement de toutes les applications dans un cluster Kubernetes local
sur la VM Vagrant. Deux modes d'acces sont disponibles : NodePort (acces
direct par IP:port) et Ingress (acces par nom de domaine via NGINX + MetalLB).

### Workflow par session

```bash
# 1. Demarrer Minikube
minikube start --driver=docker

# 2. Configurer le reseau iptables
# Les regles sont perdues a chaque redemarrage de la VM.
# L'interface bridge Minikube est detectee automatiquement.
bash setup-network.sh

# 3. Deployer toutes les ressources (premier demarrage uniquement)
bash kubernetes/commandes_utils.sh deploy

# 4. Verifier l'etat
kubectl get pods -n icgroup;kubectl get svc -n icgroup;kubectl get pvc -n icgroup

# Attendre que tous les pods soient READY et se connecter avec les URLS
kubectl get pods -n icgroup
# 5. A la Fin de session
minikube stop
```

### Acces via NodePort

| Application | URL |
|---|---|
| ic-webapp | http://192.168.56.100:30080 |
| Odoo | http://192.168.56.100:30069 |
| pgAdmin | http://192.168.56.100:30050 |

### Acces via Ingress (noms de domaine)

L'Ingress Controller NGINX et MetalLB permettent un acces par nom de domaine
depuis la machine hote Windows.

**Installation :**
```bash

# Activer les addons Minikube
minikube addons enable ingress
minikube addons enable metallb

# Configurer le pool d'IPs MetalLB
kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - 192.168.49.100-192.168.49.110
EOF

# Patcher l'ingress-nginx en LoadBalancer pour que MetalLB lui attribue
# une IP fixe (192.168.49.100) depuis le pool configure ci-dessus.
# Par defaut l'addon ingress de Minikube cree un service de type NodePort
# avec un port aleatoire — le patch force le type LoadBalancer ce qui
# stabilise l'IP et le port 80 entre les sessions.
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Deployer l'Ingress
kubectl apply -f kubernetes/ingress.yml

# Verifier que l'external IP soit attribué.
kubectl get svc -n ingress-nginx
kubectl get svc -n ingress-nginx
# Relancer les regles iptables pour prendre en compte le nouveau
# NodePort cree par l'ingress-nginx (change a chaque activation).
# Sans cette etape, les URLs en noms de domaine restent inaccessibles
# depuis Windows meme si l'Ingress est correctement configure.
bash setup-network.sh

```
**Ajouter dans `C:\Windows\System32\drivers\etc\hosts` (Windows) l'ip de la VM :**
```
192.168.56.100  ic-webapp.icgroup.fr
192.168.56.100  odoo.icgroup.fr
192.168.56.100  pgadmin.icgroup.fr
```

| Application | URL Ingress |
|---|---|
| ic-webapp | http://ic-webapp.icgroup.fr |
| Odoo | http://odoo.icgroup.fr |
| pgAdmin | http://pgadmin.icgroup.fr |

## Sondes Liveness, Readiness & Startup

Les sondes permettent à Kubernetes de surveiller l'état réel de chaque application
et d'agir automatiquement en cas de problème (self-healing).

### Les 3 rôles

| Sonde | Question posée | Conséquence si échec |
|---|---|---|
| `readinessProbe` | Le pod est-il prêt à recevoir du trafic ? | Retiré du Service — pas tué |
| `livenessProbe` | Le pod est-il toujours vivant ? | Tué et redémarré automatiquement |
| `startupProbe` | Le pod a-t-il fini de démarrer ? | Désactive liveness et readiness pendant le démarrage |

### Les 3 types de check

| Type | Mécanisme | Utilisé pour |
|---|---|---|
| `httpGet` | Requête HTTP — 200-399 = succès | ic-webapp, Odoo, pgAdmin |
| `exec` | Commande shell — code retour 0 = succès | PostgreSQL (`pg_isready`) |
| `tcpSocket` | Connexion TCP — établie = succès | Odoo (liveness) |

### Récapitulatif par application

| Application | Readiness | Liveness | Particularité |
|---|---|---|---|
| ic-webapp | httpGet `/` port 8080 | httpGet `/` port 8080 | Application stateless simple |
| PostgreSQL | exec `pg_isready -U odoo` | exec `pg_isready -U odoo` | Pas de HTTP — outil natif pg_isready |
| Odoo | httpGet `/` port 8069 | tcpSocket port 8069 | startupProbe + initContainer wait-for-postgres |
| pgAdmin | httpGet `/misc/ping` port 80 | httpGet `/misc/ping` port 80 | Route /misc/ping dédiée aux health checks |

### initContainer sur Odoo

Kubernetes ne garantit pas l'ordre de démarrage des pods. Odoo démarre avant que
PostgreSQL soit prêt à accepter des connexions, ce qui provoque un crash immédiat.

Un `initContainer` (busybox) bloque le démarrage d'Odoo en boucle TCP sur
`postgres-service:5432` toutes les 2s, jusqu'à ce que PostgreSQL réponde.

```bash
# Vérifier que les sondes sont bien configurées
kubectl describe pod -n icgroup -l app=ic-webapp | grep -A 10 "Liveness\|Readiness"
kubectl describe pod -n icgroup -l app=postgres | grep -A 10 "Liveness\|Readiness"
kubectl describe pod -n icgroup -l app=odoo | grep -A 15 "Liveness\|Readiness\|Startup"
kubectl describe pod -n icgroup -l app=pgadmin | grep -A 10 "Liveness\|Readiness"
```

> **Note** : L'annotation `rewrite-target` a ete supprimee de `ingress.yml` —
> elle provoquait des erreurs de navigation dans Odoo et pgAdmin.

### Commandes utiles

```bash
bash kubernetes/commandes_utils.sh urls    # Afficher les URLs
bash kubernetes/commandes_utils.sh creds   # Afficher les credentials
bash kubernetes/commandes_utils.sh status  # Etat pods/services/PVC
bash kubernetes/commandes_utils.sh clean   # Supprimer toutes les ressources
```

Connexion PostgreSQL depuis pgAdmin :
```
Host     : postgres-service
Port     : 5432
Database : odoo
```

---

## Troubleshooting

### Ansible ignore ansible.cfg (world writable)
```
[WARNING]: Ansible is being run in a world writable directory, ignoring it as ansible.cfg source
```
**Cause** : Travailler depuis `/mnt/` au lieu de `/home/vagrant/`
**Fix** : Cloner le repo sous `~/` et travailler depuis `/home/vagrant/`

### ansible-playbook introuvable apres bootstrap
**Cause** : `~/.local/bin` absent du PATH apres installation via pip
**Fix** :
```bash
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Docker permission denied dans Jenkins
```
permission denied while trying to connect to the Docker daemon socket
```
**Cause** : Session SSH ouverte avant l'ajout de l'utilisateur au groupe docker
**Fix** : Se deconnecter et se reconnecter en SSH

### Load key error in libcrypto (Ansible depuis Jenkins)
```
Load key "****": error in libcrypto — Permission denied (publickey)
```
**Cause** : Credential Jenkins de type "SSH Username with private key" incompatible
**Fix** : Recreer le credential `ansible-ssh-key` avec le type **Secret file**

### DNS Minikube ne resout pas docker.io (pods bloques en ContainerCreating)
**Symptome** : Les pods restent en `ContainerCreating` indefiniment
**Diagnostic** :
```bash
minikube ssh "curl -s -o /dev/null -w '%{http_code}' https://registry-1.docker.io/v2/"
# Si retourne 000 : DNS casse
```
**Fix** :
```bash
sudo bash -c 'cat > /etc/docker/daemon.json << EOF
{
  "dns": ["8.8.8.8", "8.8.4.4"]
}
EOF'
sudo systemctl restart docker
minikube start --driver=docker
```

### URLs Kubernetes inaccessibles depuis l'hote apres redemarrage
**Cause** : Les regles iptables sont perdues au redemarrage. De plus, l'interface
bridge Minikube change de nom (br-XXXX) a chaque redemarrage de Docker.
**Fix** :
```bash
# Verifier l'interface bridge actuelle
ip route | grep 192.168.49

# Relancer setup-network.sh (detection automatique de l'interface)
sudo iptables -t nat -F
sudo iptables -F FORWARD
bash setup-network.sh
```

### Ingress — 404 sur sous-routes Odoo/pgAdmin
**Cause** : Annotation `nginx.ingress.kubernetes.io/rewrite-target: /` active
**Fix** : Supprimer l'annotation de `kubernetes/ingress.yml` et re-appliquer :
```bash
kubectl apply -f kubernetes/ingress.yml
```

### MetalLB — EXTERNAL-IP en \<pending\>
**Cause** : Pool d'IPs MetalLB non configure ou mal applique
**Fix** : Verifier et re-appliquer le ConfigMap MetalLB avec la bonne plage d'IPs

### git push rejete (remote ahead)
```
error: failed to push some refs — Updates were rejected
```
**Fix** :
```bash
git pull --rebase origin main
git push
```

### Minikube SSH handshake failed
```
ssh: handshake failed: attempted methods [none publickey]
```
**Fix** :
```bash
minikube delete
minikube start --driver=docker
```

---

## Structure du projet

```
projet-fils-rouge-vagrant/
├── Dockerfile                  # Image ic-webapp (python:3.6-alpine + Flask)
├── app.py                      # Application Flask ic-webapp
├── releases.txt                # Version + URLs Odoo/pgAdmin (lu par Jenkinsfile + Dockerfile)
├── Jenkinsfile                 # Pipeline CI/CD 7 stages (doit être en ASCII pur)
├── playbook.yml                # Playbook Ansible principal (orchestre les 4 rôles)
├── ansible.cfg                 # Config Ansible (inventaire, remote_user, callbacks)
├── requirements.yml            # Collections Ansible (community.docker >= 3.0.0)
├── bootstrap.sh                # Installation des prérequis (pip3, terraform, aws, ansible)
├── reproduce_infra.sh          # Provisioning AWS via Terraform (supporte destroy)
├── reproduce_deploy.sh         # Déploiement initial via Ansible
├── setup-network.sh            # Règles iptables Kubernetes (détection bridge auto)
├── Projet Fil Rouge.pdf        # Sujet officiel du projet (document fourni)
├── rapport_final.md            # Rapport final rédigé pour le projet
├── Readme.md                   # Documentation principale du dépôt
│
├── images/                     # Images d’illustrations (schémas, captures, diagrammes)
│   └── releases.txt            # Fichier texte conservé (non-image)
│
├── .secrets/                   # Clés SSH (gitignore — ne jamais committer)
│   └── projet-fil-rouge-key.pem
│
├── terraform/
│   ├── app/
│   │   ├── main.tf             # Ressources EC2, EBS, SG, outputs
│   │   ├── outputs.tf          # Valeurs exportées (IP, volumes…)
│   │   ├── variables.tf        # Variables Terraform
│   │   └── terraform.tfvars    # region us-east-1, key_name projet-fil-rouge-key
│   └── modules/
│       ├── ec2/                # Module EC2 (instance + user_data)
│       ├── eip/                # Module Elastic IP
│       ├── security_group/     # Module Security Group (ports Odoo, pgAdmin, webapp)
│       └── ebs/                # Module EBS (volume PostgreSQL)
│
├── roles/
│   ├── odoo_role/              # Déploiement Odoo + PostgreSQL via docker-compose
│   ├── pgadmin_role/           # Déploiement pgAdmin + servers.json préconfiguré
│   ├── webapp_role/            # Déploiement ic-webapp
│   └── jenkins_role/           # Jenkins + Docker CLI + Ansible intégrés dans le container
│
├── inventaire/
│   ├── generate_inventory.sh   # Génération hosts.yml depuis terraform_ips.json
│   ├── terraform_ips.json      # IPs exportées par Terraform (gitignore)
│   └── hosts.yml.example       # Exemple d’inventaire Ansible
│
└── kubernetes/
    ├── namespace.yml           # Namespace icgroup (label env=prod)
    ├── secrets.yml             # Secrets Kubernetes (base64)
    ├── ingress.yml             # Ingress NGINX — routage par nom de domaine
    ├── commandes_utils.sh      # Script deploy/clean/status/urls/creds
    ├── README.md               # Documentation spécifique Kubernetes
    │
    ├── postgres/               # Manifests PostgreSQL (Deployment + PVC + Service)
    │   ├── pvc.yml             # Volume persistant PostgreSQL
    │   ├── deployment.yml      # Déploiement PostgreSQL
    │   └── service.yml         # Service PostgreSQL (ClusterIP)
    │
    ├── odoo/                   # Manifests Odoo (Deployment + PVC + Service)
    │   ├── pvc.yml
    │   ├── configmap.yml       # Variables d’environnement Odoo
    │   ├── service.yml
    │   └── deployment.yml
    │
    ├── pgadmin/                # Manifests pgAdmin (Deployment + ConfigMap + Service)
    │   ├── configmap.yml
    │   ├── service.yml
    │   └── deployment.yml
    │
    └── webapp/                 # Manifests ic-webapp (Deployment + Service)
        ├── service.yml
        └── deployment.yml

```

---

## Auteur

Balde — Formation DevOps EazyTraining
