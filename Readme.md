# Projet Fil Rouge — IC Group DevOps

Deploiement complet d'une infrastructure DevOps en 3 parties :
conteneurisation, CI/CD et orchestration Kubernetes.
Tout est reproductible depuis une VM Vagrant Ubuntu 22.04.

## Stack technique

- **Docker** — conteneurisation des applications
- **Terraform** — provisioning infrastructure AWS
- **Ansible** — deploiement et configuration des serveurs
- **Jenkins** — pipeline CI/CD
- **Kubernetes (Minikube)** — orchestration locale sur VM Vagrant

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

### Depuis Windows — demarrer la VM Vagrant
```bash
cd /d/cursus_devops/vagrant/minikube/minikube_ubuntu22
vagrant up && vagrant ssh
```

### Dans la VM Vagrant — cloner le repo
```bash
git clone https://github.com/nolse/projet-fils-rouge-vagrant.git
cd projet-fils-rouge-vagrant

# Placer la cle SSH AWS dans ~/.ssh/
cp projet-fil-rouge-key.pem ~/.ssh/
chmod 600 ~/.ssh/projet-fil-rouge-key.pem
```

### Outils requis dans la VM
```bash
# Terraform
sudo apt install -y terraform

# AWS CLI + credentials
sudo apt install -y awscli
aws configure

# jq (parsing JSON)
sudo apt install -y jq

# Ansible
sudo apt install -y ansible
ansible-galaxy collection install community.docker
```

---

## Partie 1 — Conteneurisation Docker

Image deja construite et publiee sur Docker Hub.

```bash
# Verifier l'image sur Docker Hub
docker pull alphabalde/ic-webapp:1.0

# Rebuilder si besoin
docker build -t alphabalde/ic-webapp:1.0 .
docker push alphabalde/ic-webapp:1.0
```

**Image disponible :** https://hub.docker.com/r/alphabalde/ic-webapp

---

## Partie 2 — CI/CD Jenkins + Ansible

Provisioning AWS via Terraform, deploiement via Ansible.
Tout se fait depuis la VM Vagrant avec deux scripts.

### Etape 1 — Provisioning infrastructure AWS
```bash
bash reproduce_infra.sh
```
Ce script :
- Initialise Terraform (backend S3)
- Cree les 3 instances EC2 + Security Group + EIPs
- Exporte les IPs dans `inventaire/terraform_ips.json`

### Etape 2 — Deploiement Ansible
```bash
bash reproduce_deploy.sh
```
Ce script :
- Verifie la cle SSH
- Installe les dependances Ansible
- Genere l'inventaire depuis terraform_ips.json
- Attend que les instances AWS soient disponibles en SSH
- Deploie Odoo, ic-webapp, pgAdmin et Jenkins via Ansible

### Acces aux services

| Application | URL |
|---|---|
| Jenkins | http://<jenkins_ip>:8080 |
| ic-webapp | http://<webapp_ip> |
| pgAdmin | http://<webapp_ip>:5050 |
| Odoo | http://<odoo_ip>:8069 |

### Fin de session
```bash
cd terraform/app && terraform destroy
```

---

## Partie 3 — Kubernetes (Minikube)

Deploiement de toutes les applications dans un cluster Kubernetes local
sur la VM Vagrant (IP fixe : 192.168.56.100).

Les NodePorts sont accessibles depuis Windows via des regles iptables
configurees par `setup-network.sh`. Aucun port-forward necessaire.

### Workflow par session
```bash
# 1. Demarrer Minikube
minikube start --driver=docker

# 2. Configurer le reseau iptables
bash setup-network.sh

# 3. Deployer toutes les ressources
bash kubernetes/commandes_utils.sh deploy

# 4. Verifier
kubectl get all -n icgroup

# 5. Fin de session
minikube stop
```

### Acces depuis Windows (ports fixes)

| Application | URL |
|---|---|
| ic-webapp | http://192.168.56.100:30080 |
| Odoo | http://192.168.56.100:30069 |
| pgAdmin | http://192.168.56.100:30050 |

### Credentials

| Application | Login | Password |
|---|---|---|
| Odoo | admin | admin |
| pgAdmin | admin@icgroup.fr | pgadmin_password |
| PostgreSQL | odoo | odoo_password |

---

## Structure du projet
## Auteur

Balde — Formation DevOps EazyTraining
