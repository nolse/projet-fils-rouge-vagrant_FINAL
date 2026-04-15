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
git clone https://github.com/nolse/projet-fils-rouge-vagrant.git
cd projet-fils-rouge-vagrant
```

Verifier que ansible.cfg est bien reconnu :
```bash
ansible --version | grep "config file"
# Attendu : config file = /home/vagrant/projet-fils-rouge-vagrant/ansible.cfg
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
Repository URL       : https://github.com/nolse/projet-fils-rouge-vagrant.git
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

# 5. Fin de session
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

# Deployer l'Ingress
kubectl apply -f kubernetes/ingress.yml
```

**Ajouter dans `C:\Windows\System32\drivers\etc\hosts` (Windows) :**
```
192.168.49.100  ic-webapp.icgroup.fr
192.168.49.100  odoo.icgroup.fr
192.168.49.100  pgadmin.icgroup.fr
```

| Application | URL Ingress |
|---|---|
| ic-webapp | http://ic-webapp.icgroup.fr |
| Odoo | http://odoo.icgroup.fr |
| pgAdmin | http://pgadmin.icgroup.fr |

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
├── Jenkinsfile                 # Pipeline CI/CD 7 stages (doit etre en ASCII pur)
├── playbook.yml                # Playbook Ansible principal (orchestre les 4 roles)
├── ansible.cfg                 # Config Ansible (inventaire, remote_user, callbacks)
├── requirements.yml            # Collections Ansible (community.docker >= 3.0.0)
├── bootstrap.sh                # Installation des prerequis (pip3, terraform, aws, ansible)
├── reproduce_infra.sh          # Provisioning AWS via Terraform (supporte destroy)
├── reproduce_deploy.sh         # Deploiement initial via Ansible
├── setup-network.sh            # Regles iptables Kubernetes (detection bridge auto)
├── .secrets/                   # Cles SSH (gitignore — ne jamais committer)
│   └── projet-fil-rouge-key.pem
├── terraform/
│   ├── app/
│   │   ├── main.tf
│   │   ├── outputs.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars    # region us-east-1, key_name projet-fil-rouge-key
│   └── modules/
│       ├── ec2/
│       ├── eip/
│       ├── security_group/
│       └── ebs/
├── roles/
│   ├── odoo_role/              # Deploiement Odoo + PostgreSQL via docker-compose
│   ├── pgadmin_role/           # Deploiement pgAdmin + servers.json preconfigure
│   ├── webapp_role/            # Deploiement ic-webapp
│   └── jenkins_role/           # Jenkins + Docker CLI + Ansible integres dans le container
├── inventaire/
│   ├── generate_inventory.sh   # Generation hosts.yml depuis terraform_ips.json
│   ├── terraform_ips.json      # IPs exportees par Terraform (gitignore)
│   └── hosts.yml.example       # Exemple d'inventaire Ansible
└── kubernetes/
    ├── namespace.yml           # Namespace icgroup (label env=prod)
    ├── secrets.yml             # Secrets Kubernetes (base64)
    ├── ingress.yml             # Ingress NGINX — routage par nom de domaine
    ├── commandes_utils.sh      # Script deploy/clean/status/urls/creds
    ├── README.md               # Documentation specifique Kubernetes
    ├── postgres/               # Manifests PostgreSQL (Deployment + PVC + Service)
    ├── odoo/                   # Manifests Odoo (Deployment + PVC + Service)
    ├── pgadmin/                # Manifests pgAdmin (Deployment + ConfigMap + Service)
    └── webapp/                 # Manifests ic-webapp (Deployment + Service)
```

---

## Auteur

Balde — Formation DevOps EazyTraining
