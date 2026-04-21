# Rapport Technique — Projet Fil Rouge IC Group DevOps

**Auteur : Balde — Formation DevOps EazyTraining — 2026**

---

# 1. Contexte et Objectifs

Ce projet fil rouge s'inscrit dans le cadre de la formation DevOps EazyTraining. Il vise à déployer une infrastructure applicative complète, de la conteneurisation à l'orchestration, en passant par une chaîne CI/CD entièrement automatisée.

Le périmètre couvre trois grandes parties :

- 📦 **Partie 1** — Conteneurisation de l'application ic-webapp avec Docker
- ⚙️ **Partie 2** — Pipeline CI/CD automatisé avec Jenkins, Ansible et Terraform sur AWS
- ☸️ **Partie 3** — Orchestration Kubernetes avec Minikube sur VM Vagrant

## Applications déployées

| Application | Image Docker | Rôle |
|---|---|---|
| ic-webapp | alphabalde/ic-webapp:1.0 | Site vitrine front-end IC Group |
| Odoo | odoo:13.0 | ERP — gestion métier |
| PostgreSQL | postgres:13 | Base de données relationnelle |
| pgAdmin | dpage/pgadmin4 | Interface d'administration BDD |
| Jenkins | jenkins/jenkins:lts | Pipeline CI/CD automatisé |

## Stack technique globale

| Outil | Rôle |
|---|---|
| Docker | Conteneurisation des applications |
| Terraform | Provisioning infrastructure AWS (EC2, EIP, SG) |
| Ansible | Déploiement et configuration des serveurs distants |
| Jenkins | Orchestration du pipeline CI/CD (7 stages) |
| Minikube | Cluster Kubernetes local sur VM Vagrant |
| VirtualBox + Vagrant | Hyperviseur et provisioning de la VM de travail |

---

# 2. Infrastructure et Environnement

L'intégralité du projet est reproductible depuis une VM Vagrant sous Ubuntu 22.04. Cette approche garantit un environnement de travail isolé et portable, indépendant du poste de développement.

## Prérequis et mise en place

**Étape 1 — Démarrer la VM Vagrant :**

```bash
vagrant up && vagrant ssh
```

**Étape 2 — Cloner le dépôt (obligatoirement sous /home/vagrant) :**

```bash
cd ~
git clone https://github.com/nolse/projet-fils-rouge-vagrant_FINAL.git 
cd projet-fils-rouge-vagrant_INGDM
 
```

> ⚠️ Travailler impérativement sous `/home/vagrant` et non `/mnt/`. Le dossier `/mnt/` est world-writable — Ansible refusera de lire `ansible.cfg` depuis ce chemin.

**Étape 3 — Installer les prérequis via bootstrap :**

```bash
bash bootstrap.sh
source ~/.bashrc
```

Le script installe Ansible (via pip3), Terraform, AWS CLI et configure le PATH. La version pip3 est requise car la version apt (2.10.x) est incompatible avec `community.docker >= 3.0.0`.

**Étape 4 — Configurer les credentials AWS :**

```bash
aws configure
# Region : us-east-1 | Output : json
```

## Structure du projet

| Fichier / Dossier | Rôle |
|---|---|
| Dockerfile | Image ic-webapp (python:3.6-alpine + Flask) |
| Jenkinsfile | Pipeline CI/CD 7 stages |
| playbook.yml | Playbook Ansible principal (4 rôles) |
| bootstrap.sh | Installation des prérequis |
| reproduce_infra.sh | Provisioning AWS via Terraform |
| reproduce_deploy.sh | Déploiement initial via Ansible |
| setup-network.sh | Règles iptables pour Kubernetes |
| terraform/ | Modules EC2, EIP, Security Group, EBS |
| roles/ | odoo_role, pgadmin_role, webapp_role, jenkins_role |
| kubernetes/ | Manifests Kubernetes + scripts utilitaires |

---

# 3. Partie 1 — Conteneurisation Docker

La première partie consiste à conteneuriser l'application ic-webapp sous forme d'image Docker publiée sur Docker Hub, prête à être déployée sur n'importe quel environnement.

## Construction et publication de l'image

L'image ic-webapp est basée sur `python:3.6-alpine` et embarque l'application Flask ainsi que le fichier `releases.txt` utilisé pour la gestion des versions.

```bash
# Construire l'image
docker build -t alphabalde/ic-webapp:1.0 .

# Publier sur Docker Hub
docker push alphabalde/ic-webapp:1.0
```

Image disponible : https://hub.docker.com/r/alphabalde/ic-webapp

## Test rapide de l'image

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

L'application accepte deux variables d'environnement configurables : `ODOO_URL` et `PGADMIN_URL`, qui paramètrent les liens affichés sur la page d'accueil.

<p align="center">
  <img src="./images/DOCKER_HUB.png" width="700">
</p>

---

# 4. Partie 2 — CI/CD Jenkins + Ansible + Terraform

Cette partie met en place une chaîne CI/CD complète avec provisioning automatique de l'infrastructure AWS via Terraform, déploiement via Ansible et orchestration via Jenkins.

## Étape 1 — Provisioning infrastructure AWS

```bash
bash reproduce_infra.sh
```

Ce script initialise Terraform (backend S3 : `terraform-backend-balde`), crée 3 instances EC2 avec leurs EIPs et Security Groups, puis exporte les IPs dans `inventaire/terraform_ips.json`.

| Serveur | Rôle |
|---|---|
| jenkins | Serveur Jenkins CI/CD |
| odoo | Serveur applicatif Odoo + PostgreSQL |
| webapp | Serveur ic-webapp + pgAdmin |

## Étape 2 — Déploiement initial via Ansible

```bash
bash reproduce_deploy.sh
```

Le script vérifie la clé SSH, installe les collections Ansible, génère l'inventaire depuis `terraform_ips.json`, attend la disponibilité SSH des instances, puis exécute les 4 rôles Ansible.

## Étape 3 — Configuration Jenkins

Accéder à l'interface Jenkins sur `http://<jenkins_ip>:8080` et récupérer le mot de passe initial :

```bash
ssh -i ~/.ssh/projet-fil-rouge-key.pem ubuntu@<jenkins_ip>
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

**Credentials à configurer** (Manage Jenkins → Credentials → Global) :

| ID Credential | Type | Contenu |
|---|---|---|
| ansible-ssh-key | Secret file | Uploader projet-fil-rouge-key.pem |
| docker-hub-credentials | Username with password | Login Docker Hub |

> ⚠️ Utiliser impérativement le type **Secret file** pour `ansible-ssh-key`. Le type "SSH Username with private key" provoque une erreur `error in libcrypto` incompatible avec Ansible.

**Variables globales à définir** (Manage Jenkins → System → Global properties) :

| Variable | Valeur |
|---|---|
| JENKINS_IP | IP publique du serveur Jenkins |
| WEBAPP_IP | IP publique du serveur webapp |
| ODOO_IP | IP publique du serveur Odoo |

## Étape 4 — Pipeline CI/CD (7 stages)

| Stage | Action |
|---|---|
| 1. Checkout | Récupération du code source depuis GitHub |
| 2. Read Version | Lecture de la version et des URLs depuis releases.txt |
| 3. Build | Construction de l'image docker ic-webapp:\<version\> |
| 4. Test | Vérification que le container répond sur le port 8085 |
| 5. Push | Publication sur Docker Hub (tag version + latest) |
| 6. Generate Inventory | Génération dynamique de hosts.yml avec les IPs AWS |
| 7. Deploy | Exécution du playbook Ansible sur les 3 serveurs |

### Détail du stage de test (qualité et validation)

Le stage **Test** joue un rôle critique dans le pipeline CI/CD. Il permet de valider automatiquement le bon fonctionnement de l'application avant son déploiement.

Contrairement à un simple build, ce stage vérifie le comportement réel du container.

Les vérifications effectuées sont les suivantes :

- **Validation de la taille de l'image Docker**
  - L'image doit être inférieure à 200MB
  - Objectif : garantir une image optimisée et légère

- **Démarrage du container**
  - Lancement avec les variables d'environnement dynamiques (ODOO_URL, PGADMIN_URL)
  - Vérification que le container est bien en état "running"

- **Test HTTP**
  - Requête HTTP exécutée depuis l'intérieur du container (`docker exec`)
  - Vérification du code de retour (HTTP 200)

- **Validation du contenu applicatif**
  - Présence du texte "IC GROUP"
  - Vérification des liens injectés dynamiquement :
    - Odoo
    - pgAdmin

Ce choix de test depuis l'intérieur du container est volontaire :
Jenkins étant lui-même exécuté dans Docker, cela garantit un test fiable dans un contexte Docker-in-Docker.

> En cas d'échec d'un seul test, le pipeline est immédiatement interrompu, empêchant le déploiement d'une version non fonctionnelle.

## Déclenchement automatique via webhook

```bash
sed -i 's/^version 1.0/version 1.1/' releases.txt
git add releases.txt && git commit -m 'release: version 1.1' && git push
```

Configuration du webhook (Settings → Webhooks) : Payload URL = `http://<jenkins_ip>:8080/github-webhook/` | Content type = `application/json` | Trigger = push event.

### Notifications Slack (observabilité du pipeline)

Afin d'améliorer la visibilité et le suivi des exécutions, des notifications Slack ont été intégrées au pipeline Jenkins.

#### Fonctionnement

Le pipeline envoie automatiquement un message dans un canal Slack dédié :

- Succès → message vert
- Échec → message rouge

Chaque notification contient :
- Le nom du job
- Le numéro du build
- Un lien direct vers Jenkins

#### Mise en place

La configuration repose sur le plugin Slack Jenkins et un token d'authentification.

1. **Récupération du token Slack**
   - Slack → Apps → Jenkins CI → Configuration
   - Copier le token généré

2. **Ajout dans Jenkins**
   - Manage Jenkins → Credentials → Add Credentials
   - Type : Secret text
   - ID : `slack-token`

3. **Configuration globale**
   - Manage Jenkins → Configure System → Slack
   - Association du workspace et du credential
   - Définition du canal par défaut

Un test de connexion permet de valider la configuration (message "Success" + notification reçue).

#### Intérêt

- Suivi en temps réel des déploiements
- Réactivité en cas d'échec
- Intégration dans un workflow collaboratif

> Cette fonctionnalité rapproche le pipeline d'un fonctionnement DevOps réel en entreprise, où la supervision et la communication sont essentielles.

## URLs d'accès (Partie 2)

| Application | URL |
|---|---|
| Jenkins | http://\<jenkins_ip\>:8080 |
| ic-webapp | http://\<webapp_ip\> |
| pgAdmin | http://\<webapp_ip\>:5050 |
| Odoo | http://\<odoo_ip\>:8069 |

```bash
# Destruction de l'infrastructure AWS en fin de session
bash reproduce_infra.sh destroy
```
<p align="center">
  <img src="./images/IC_WEBAPP_URL_OK.png" width="700">
  <img src="./images/PGADMIN_URL_OK.png" width="700"><br><br>
  <img src="./images/ODOO_URL_OK.png" width="700">
</p>

<p align="center">
  <img src="./images/TEST_CONNEXION_SLACK_OK.png" width="600"><br>
  <img src="./images/PIPELINE_IC_WEBAPP_OK2.png" width="600"><br>
  <img src="./images/NOTIFICATION_SUCCES_PIPELINE_WEBAPP.png" width="600"><br>
  <img src="./images/PIPELINE_IC_WEBAPP_BLUEOCEAN_OK3_WITHNOTIF.png" width="600"><br>
  <img src="./images/NOTIFICATION_SUCCES_PIPELINE_WEBAPP_FINAL.png" width="600"><br>
  <img src="./images/bash_reproduce_infra.sh_destroy.png" width="600">
</p>


---

# 5. Partie 3 — Architecture Kubernetes

La troisième partie orchestre l'ensemble des applications dans un cluster Kubernetes local (Minikube single-node) sur la VM Vagrant, en respectant le schéma synoptique fourni par le formateur.

## Environnement Kubernetes

| Composant | Détail |
|---|---|
| Orchestrateur | Minikube (single-node, driver Docker) |
| Namespace | icgroup (label env=prod) |
| IP du nœud | 192.168.56.100 |
| Accès externe | NodePort via règles iptables (setup-network.sh) |
| Stockage | StorageClass standard (provisioning automatique) |

<p align="center">
  <img src="./images/ARCHITECTURE_GLOBAL.png" width="600">

  <img src="./images/synoptique_Kubernetes.jpeg" width="600">
</p>

## Identification des ressources (A → H)

| Ressource | Type Kubernetes | Nom | Rôle |
|---|---|---|---|
| A | Service NodePort | ic-webapp-service | Point d'entrée externe — port 30080 |
| B | Deployment (2 pods) | ic-webapp | Front-end IC Group — 2 réplicas (HA) |
| C | Service NodePort | odoo-service | Exposition Odoo — port 30069 |
| D | Deployment (2 pods) | odoo | ERP Odoo — 2 réplicas (HA) |
| E | Service ClusterIP | postgres-service | Accès interne BDD — non exposé |
| F | Deployment (1 pod) | postgres | PostgreSQL — données persistées via PVC |
| G | Service NodePort | pgadmin-service | Exposition pgAdmin — port 30050 |
| H | Deployment (1 pod) | pgadmin | Interface admin PostgreSQL |

> Point clé : PostgreSQL est le seul service en ClusterIP — la base de données n'est jamais exposée directement à l'extérieur.

---

# 6. Déploiement des Manifests Kubernetes

## Procédure de déploiement

```bash
# 1. Démarrer le cluster Minikube
minikube start --driver=docker

# 2. Configurer les règles réseau iptables
bash setup-network.sh

# 3. Déployer toutes les ressources Kubernetes
bash kubernetes/commandes_utils.sh deploy
```
> ⚠️ Les règles iptables sont perdues à chaque redémarrage de la VM. Relancer `setup-network.sh` à chaque nouvelle session.

## Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: icgroup
  labels:
    env: prod
```

## Déploiement PostgreSQL (Deployment + Service + PVC)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: postgres
  namespace: icgroup
spec:
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    spec:
      containers:
        - name: postgres
          image: postgres:13
          env:
            - name: POSTGRES_DB
              value: odoo
            - name: POSTGRES_USER
              value: odoo
            - name: POSTGRES_PASSWORD
              value: odoo_password
          volumeMounts:
            - mountPath: /var/lib/postgresql/data
              name: postgres-storage
      volumes:
        - name: postgres-storage
          persistentVolumeClaim:
            claimName: postgres-pvc
```

## Scripts utilitaires Kubernetes

| Commande | Action |
|---|---|
| `commandes_utils.sh deploy` | Déployer toutes les ressources |
| `commandes_utils.sh status` | État des pods, services et PVC |
| `commandes_utils.sh urls` | Afficher les URLs d'accès |
| `commandes_utils.sh creds` | Afficher les identifiants |
| `commandes_utils.sh clean` | Supprimer toutes les ressources |

---

# 7. Persistance des Données

Deux PersistentVolumeClaims garantissent la persistance des données applicatives entre les redémarrages des pods.

| PVC | Application | Capacité | Mode d'accès | StorageClass |
|---|---|---|---|---|
| postgres-pvc | PostgreSQL | 2 Gi | ReadWriteOnce | standard |
| odoo-pvc | Odoo | 1 Gi | ReadWriteOnce | standard |

```bash
kubectl get pvc -n icgroup

# Résultat attendu
NAME           STATUS   VOLUME                                     CAPACITY   ACCESS MODES
odoo-pvc       Bound    pvc-34147d49-f4a2-4f3c-8f37-a414cd756640   1Gi        RWO
postgres-pvc   Bound    pvc-3e35963e-4c56-4b26-9910-3ca9d07cafdd   2Gi        RWO
```
---

# 8. Vérification du Déploiement

## État des Pods

```bash
kubectl get pods -n icgroup

NAME                         READY   STATUS    RESTARTS   AGE
ic-webapp-69db74c864-9bj7d   1/1     Running   0          3h37m
ic-webapp-69db74c864-wdv5p   1/1     Running   0          30s
odoo-775d57c458-ggghh        1/1     Running   0          10s
odoo-775d57c458-q6sx4        1/1     Running   0          3h38m
pgadmin-78f5966bc7-8qlsv     1/1     Running   0          3h37m
postgres-784c6d4b47-tmgs8    1/1     Running   0          3h39m
```

✅ 2 réplicas pour ic-webapp — conforme au schéma synoptique  
✅ 2 réplicas pour Odoo — conforme au schéma synoptique  
✅ Tous les pods en état Running

## État des Services

```bash
kubectl get svc -n icgroup

NAME                TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)
ic-webapp-service   NodePort    10.99.108.174   <none>        8080:30080/TCP
odoo-service        NodePort    10.105.25.244   <none>        8069:30069/TCP
pgadmin-service     NodePort    10.107.15.134   <none>        80:30050/TCP
postgres-service    ClusterIP   10.106.88.245   <none>        5432/TCP
```

✅ `postgres-service` en ClusterIP — base de données non exposée à l'extérieur  
✅ `ic-webapp-service`, `odoo-service` et `pgadmin-service` en NodePort — accessibles depuis Windows

---

# 9 . Ingress Controller et MetalLB

## Objectif

Au-delà de l'accès via NodePort, une couche Ingress a été mise en place pour exposer les applications via des **noms de domaine personnalisés** (`ic-webapp.icgroup.fr`, `odoo.icgroup.fr`, `pgadmin.icgroup.fr`), avec routage HTTP centralisé par l'Ingress Controller NGINX.

## MetalLB — Load Balancer bare-metal

Minikube ne disposant pas de Load Balancer natif (contrairement à un cloud provider), **MetalLB** a été installé pour attribuer une IP externe aux services de type `LoadBalancer`.

### Installation

```bash

# Activer l'addon MetalLB intégré à Minikube
minikube addons enable metallb

# Configurer la plage d'IPs attribuables
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

# Par défaut, l'addon ingress de Minikube crée ingress-nginx en type NodePort
# avec un port aléatoire. Il faut le patcher en LoadBalancer pour que MetalLB
# lui attribue une IP fixe (192.168.49.100) depuis le pool configuré ci-dessus.
# Sans ce patch, MetalLB n'intervient pas et l'EXTERNAL-IP reste vide.
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec": {"type": "LoadBalancer"}}'
```
### Vérification

```bash
# Vérifier que l'EXTERNAL-IP est bien attribuée par MetalLB
kubectl get svc -n ingress-nginx
NAME                                 TYPE           CLUSTER-IP       EXTERNAL-IP      PORT(S)
ingress-nginx-controller             LoadBalancer   10.97.114.215    192.168.49.100   80:30938/TCP,443:32025/TCP
```

## Ingress Controller NGINX

### Installation

```bash
minikube addons enable ingress

# Vérifier que le controller est Running
kubectl get pods -n ingress-nginx
NAME                                        READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-7799c6795f-xk9qp   1/1     Running   0          5m
```

## Manifest Ingress (`kubernetes/ingress.yml`)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: icgroup-ingress
  namespace: icgroup
spec:
  ingressClassName: nginx
  rules:
    - host: ic-webapp.icgroup.fr
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ic-webapp-service
                port:
                  number: 8080

    - host: odoo.icgroup.fr
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: odoo-service
                port:
                  number: 8069

    - host: pgadmin.icgroup.fr
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: pgadmin-service
                port:
                  number: 80
```
> ⚠️ L'annotation `nginx.ingress.kubernetes.io/rewrite-target: /` a été volontairement supprimée. Elle provoquait une réécriture systématique des URLs vers `/`, cassant la navigation dans Odoo et pgAdmin (sous-routes non résolues). Sans cette annotation, le routage fonctionne correctement pour les trois applications.

### Déploiement

```bash
kubectl apply -f kubernetes/ingress.yml

# Vérifier
kubectl get ingress -n icgroup
NAME               CLASS   HOSTS                                                        ADDRESS          PORTS   AGE
icgroup-ingress    nginx   ic-webapp.icgroup.fr,odoo.icgroup.fr,pgadmin.icgroup.fr     192.168.49.100   80      2m
```

## Résolution DNS locale (fichier hosts)

Pour accéder aux applications via leurs noms de domaine depuis Windows, ajouter les entrées suivantes avec l'ip de la VM dans `C:\Windows\System32\drivers\etc\hosts` :

```
192.168.56.100  ic-webapp.icgroup.fr
192.168.56.100  odoo.icgroup.fr
192.168.56.100  pgadmin.icgroup.fr
```

> L'IP `192.168.49.100` est l'adresse attribuée par MetalLB à l'Ingress Controller NGINX. Toutes les requêtes HTTP vers les trois domaines arrivent sur ce point d'entrée unique, puis sont routées vers le bon service selon le `Host` header.
> L'IP `192.168.49.100` est attribuée par MetalLB à l'Ingress Controller NGINX à l'intérieur du réseau Minikube. 
Le fichier hosts pointe vers `192.168.56.100` (IP de la VM Vagrant) 
car les règles iptables de setup-network.sh redirigent le trafic entrant vers l'Ingress Controller.

## URLs d'accès via Ingress (Partie 3 — bonus)

| Application | URL Ingress | Service cible |
|---|---|---|
| ic-webapp | http://ic-webapp.icgroup.fr | ic-webapp-service:8080 |
| Odoo | http://odoo.icgroup.fr | odoo-service:8069 |
| pgAdmin | http://pgadmin.icgroup.fr | pgadmin-service:80 |

# 10. Sondes Liveness, Readiness & Startup

## Objectif

Dans un cluster Kubernetes, un pod en état `Running` ne signifie pas nécessairement
que l'application est opérationnelle. Les sondes permettent à Kubernetes de distinguer
trois états distincts : le pod démarre, le pod est prêt à servir, le pod est vivant.

## Les trois types de sondes

### readinessProbe — "Prêt à recevoir du trafic ?"

La readiness probe détermine si un pod peut recevoir des requêtes via son Service.
Tant qu'elle échoue, le pod est retiré de la rotation du Service mais reste vivant.

Cas concret : au démarrage d'Odoo, l'application met plusieurs dizaines de secondes
à charger ses modules. Sans readiness probe, le Service enverrait des requêtes vers
un pod qui retourne des erreurs 500. Avec la sonde, Kubernetes attend que l'application
soit réellement opérationnelle avant de lui envoyer du trafic.

### livenessProbe — "Toujours vivant ?"

La liveness probe détecte les pods bloqués (boucle infinie, deadlock, crash silencieux)
et les redémarre automatiquement. C'est le mécanisme de **self-healing** de Kubernetes.

### startupProbe — "A-t-il fini de démarrer ?"

La startup probe résout le problème des applications lentes à démarrer.
Tant qu'elle n'a pas réussi, les sondes liveness et readiness sont complètement
désactivées — l'application peut s'initialiser sans être perturbée ni tuée.

## Les trois types de check

| Type | Mécanisme | Cas d'usage |
|---|---|---|
| `httpGet` | Requête HTTP — 200-399 = succès | Applications web exposant une route |
| `exec` | Commande shell — code retour 0 = succès | Bases de données, outils CLI |
| `tcpSocket` | Connexion TCP — établie = succès | Vérification légère qu'un process écoute |

## Implémentation par application

### ic-webapp

Application Flask stateless — sonde `httpGet` sur `/` port 8080.
Dès que Flask répond, le pod est considéré prêt et vivant.

### PostgreSQL

Pas d'interface HTTP — sonde `exec` avec `pg_isready -U odoo`.
`pg_isready` est l'outil officiel PostgreSQL qui retourne 0 uniquement
quand le serveur accepte des connexions TCP sur le port 5432.

### Odoo

Odoo présente deux problèmes spécifiques :

**1. Dépendance à PostgreSQL** : Odoo crashe immédiatement si PostgreSQL n'est pas prêt.
Kubernetes ne garantissant pas l'ordre de démarrage des pods, un `initContainer`
(busybox) bloque le démarrage d'Odoo en boucle sur `postgres-service:5432`
jusqu'à ce que la connexion TCP s'établisse.

**2. Démarrage lent avec `--update=web`** : la régénération des assets CSS/JS
provoque des erreurs 500 pendant l'initialisation, ce qui déclenchait des
faux positifs sur la liveness probe (pod tué alors qu'il était en train de démarrer).
La `startupProbe` désactive liveness et readiness pendant 5 minutes maximum,
laissant Odoo finir son initialisation sans interruption.

| Sonde | Type | Détail |
|---|---|---|
| startupProbe | httpGet `/` | 30 tentatives × 10s = 5 min max |
| readinessProbe | httpGet `/` | Activée après succès de la startup |
| livenessProbe | tcpSocket 8069 | Check TCP léger — suffisant pour détecter un crash |

### pgAdmin

pgAdmin expose une route dédiée `/misc/ping` recommandée par l'image officielle
`dpage/pgadmin4`. Les `initialDelaySeconds` ont été calibrés à 60s (readiness)
et 120s (liveness) car pgAdmin initialise une base SQLite interne au démarrage —
des délais trop courts provoquaient des redémarrages en boucle (faux positifs).

## Bilan

| Application | initContainer | startupProbe | readinessProbe | livenessProbe |
|---|---|---|---|---|
| ic-webapp | ✗ | ✗ | httpGet `/` | httpGet `/` |
| PostgreSQL | ✗ | ✗ | exec `pg_isready` | exec `pg_isready` |
| Odoo | ✅ wait-for-postgres | ✅ httpGet `/` | httpGet `/` | tcpSocket |
| pgAdmin | ✗ | ✗ | httpGet `/misc/ping` | httpGet `/misc/ping` |

L'ajout des sondes transforme le déploiement en infrastructure **auto-réparatrice** :
tout pod défaillant est détecté et redémarré sans intervention manuelle,
et aucun pod non prêt ne reçoit de trafic utilisateur.

## Illustrations du travail

<p align="center">
  <img src="./images/pipeline.jpeg" width="700">
</p>

<p align="center">
  <img src="./images/DOCKER_PUSH_WEBAPP_V1P1_POSTWEBHOOK.png" width="700"><br><br>
</p>

<p align="center">
  <img src="./images/REPRODUCE_INFRA_OK.png" width="700">
  <img src="./images/REPRODUCE_INFRA_INPROGRESS.png" width="700"><br><br>

  <img src="./images/ansible-ssh-key.png" width="700">
  <img src="./images/export_var.jpeg" width="700"><br><br>
</p>

<p align="center">
  <img src="./images/REPRODUCE_DEPLOY_INPROGRESS.png" width="700">
  <img src="./images/REPRODUCE_DEPLOY_OK.png" width="700">

  <img src="./images/VARIABLES_ENV1.png" width="700"><br><br>
  <img src="./images/VARIABLES_ENV2.png" width="700"><br><br>
</p>

<p align="center">
  <img src="./images/JENKINS_URL_OK.png" width="700">
  <img src="./images/JOB_IC_WEBAPP.png" width="700"><br><br>

  <img src="./images/CREDENTIALS_MAJ_ANSIBLE_SSHKEY_FILE.png" width="700">
  <img src="./images/PIPELINE_IC_WEBAPP_OK1.png" width="700"><br><br>

  <img src="./images/PIPELINE_IC_WEBAPP_BLUEOCEAN_OK2.png" width="700">
  <img src="./images/CONSOLEOUTPUT_PIPELINE_ICWEBAPP.png" width="700"><br><br>
</p>

<p align="center">
  <img src="./images/CONF_WEBHOOK_TRIGGERS.png" width="700">
  <img src="./images/GITHUB_CONF_WEBHOOK_TRIGGERS.png" width="700"><br><br>

  <img src="./images/WEBHOOK_DEPLOY_V1P1_PIPELINE.png" width="700">
  <img src="./images/WEBHOOK_DEPLOY_V1P1_PIPELINE_SUCCES.png" width="700"><br><br>

  <img src="./images/DOCKER_PUSH_WEBAPP_V1P1_POSTWEBHOOK.png" width="700">
  <img src="./images/POST_PIPELINERUN_3URLSOK.png" width="700"><br><br>
</p>

<p align="center">
  <img src="./images/PART3_URLS_OK_UP.png" width="700"><br><br>

  <img src="./images/PART3_LOGIN_URLS_OK.png" width="700">
</p>

<p align="center">
  <img src="./images/PART3_PODS_PVC_SVC_UP.png" width="700">
  <img src="./images/PART3_PODS_REPLICAS_EGAL2.png" width="700"><br><br>

  <img src="./images/PART3_INGRESS_METALLB.png" width="700">
  <img src="./images/PART3_ODOO_URLOK1.png" width="700"><br><br>

  <img src="./images/PART3_ICWEBAPP_URLOK1.png" width="700">
  <img src="./images/PART3_PGADMIN_URLOK1.png" width="700"><br><br>

  <img src="./images/PART3_ODOO_URLOK2.png" width="700">
  <img src="./images/PART3_PGADMIN_URLOK2.png" width="700"><br><br>
</p>

---

# 11. Tests de Fonctionnement

## URLs d'accès depuis Windows (NodePort — Partie 3)

| Application | URL | Port NodePort |
|---|---|---|
| ic-webapp | http://192.168.56.100:30080 | 30080 |
| Odoo | http://192.168.56.100:30069 | 30069 |
| pgAdmin | http://192.168.56.100:30050 | 30050 |

## Identifiants de connexion

| Application | Identifiant | Mot de passe |
|---|---|---|
| pgAdmin | admin@icgroup.fr | pgadmin_password |
| Odoo | admin | admin |
| PostgreSQL (via pgAdmin) | odoo | odoo_password |

Connexion PostgreSQL depuis pgAdmin : Host = `postgres-service` | Port = `5432` | Database = `odoo`

---

# 12. Troubleshooting

| Problème | Cause | Solution |
|---|---|---|
| Ansible ignore ansible.cfg (world writable) | Travail depuis /mnt/ au lieu de /home/vagrant/ | Cloner le repo sous ~/ et travailler depuis /home/vagrant/ |
| ansible-playbook introuvable après bootstrap | ~/.local/bin absent du PATH | `export PATH="$HOME/.local/bin:$PATH" && source ~/.bashrc` |
| Docker permission denied dans Jenkins | Session SSH ouverte avant ajout au groupe docker | Se déconnecter et se reconnecter en SSH |
| error in libcrypto (Ansible depuis Jenkins) | Credential de type SSH Username with private key | Recréer le credential ansible-ssh-key en type Secret file |
| Pods bloqués en ContainerCreating (DNS Minikube) | DNS cassé — docker.io non résolu | Configurer /etc/docker/daemon.json avec dns 8.8.8.8 et redémarrer Docker |
| URLs Kubernetes inaccessibles après redémarrage | Règles iptables perdues + interface bridge changée | Relancer setup-network.sh (détection automatique de l'interface) |
| git push rejeté (remote ahead) | Divergence de branches | `git pull --rebase origin main && git push` |
| Minikube SSH handshake failed | Clé Minikube corrompue | `minikube delete && minikube start --driver=docker` |
| Ingress — 404 sur sous-routes Odoo/pgAdmin | Annotation rewrite-target active | Supprimer l'annotation `nginx.ingress.kubernetes.io/rewrite-target` de ingress.yml |
| MetalLB — EXTERNAL-IP en \<pending\> | Pool d'IPs non configuré | Appliquer le ConfigMap MetalLB avec la bonne plage d'IPs |

---

# 13. Conclusion

Ce projet fil rouge a permis de mettre en œuvre un pipeline DevOps complet, de la conteneurisation à l'orchestration, en couvrant l'ensemble des pratiques modernes du métier.

## Bilan des réalisations

✅ Partie 1 — Image Docker ic-webapp construite et publiée sur Docker Hub  
✅ Partie 2 — Infrastructure AWS provisionnée via Terraform (3 EC2 + EIPs + SG)  
✅ Partie 2 — Déploiement automatisé sur AWS via Ansible (4 rôles)  
✅ Partie 2 — Pipeline CI/CD Jenkins 7 stages avec déclenchement automatique via webhook GitHub  
✅ Partie 3 — Architecture Kubernetes conforme au schéma synoptique  
✅ Partie 3 — Namespace dédié `icgroup` avec isolation des ressources  
✅ Partie 3 — Haute disponibilité : 2 réplicas pour ic-webapp et Odoo  
✅ Partie 3 — Persistance des données via PVC pour PostgreSQL et Odoo  
✅ Partie 3 — Isolation réseau : PostgreSQL accessible uniquement en ClusterIP  
✅ Partie 3 — Accès externe via NodePort pour ic-webapp, Odoo et pgAdmin  
✅ Partie 3 — Ingress Controller NGINX avec routage par nom de domaine  
✅ Partie 3 — MetalLB pour l'attribution d'une IP externe en environnement bare-metal  

---

*Balde — Formation DevOps EazyTraining — 2026*
