# Contexte Projet Fil Rouge — IC Group DevOps
# À coller en début de session Claude pour reprendre sans perte de contexte

## Stack technique
- Terraform 1.14.5 | AWS us-east-1 | Backend S3 : terraform-backend-balde
- Ansible >= 2.12 | Collection community.docker
- Docker | Images : alphabalde/ic-webapp:1.0, jenkins/jenkins:lts, odoo:13.0, dpage/pgadmin4
- Repo infra  : https://github.com/nolse/projet_fil_rouge_infra
- Repo ansible: https://github.com/nolse/projet-fils-rouge

## Architecture serveurs AWS
| Serveur | Type      | Ce qui tourne                     | Ports        |
|---------|-----------|-----------------------------------|--------------|
| jenkins | t3.medium | jenkins/jenkins:lts               | 8080, 50000  |
| webapp  | t3.micro  | ic-webapp (port 80) + pgAdmin     | 80, 5050     |
| odoo    | t3.medium | Odoo 13 + PostgreSQL              | 8069, 5432   |

## Notes importantes
- sadofrazer/jenkins remplacé par jenkins/jenkins:lts
  → CentOS 7 EOL depuis juin 2024 + incompatibilité cgroups v2 Ubuntu 22.04
- Clé SSH dans projet_fil_rouge_infra/.secrets/projet-fil-rouge-key.pem
- Ansible DOIT être lancé depuis ~/projet-fils-rouge (filesystem Linux natif WSL)
- Terraform est sur Windows (Git Bash), Ansible dans WSL → workflow spécifique

## Workflow WSL (à suivre à chaque session)
```bash
# 1. Depuis Git Bash — déployer infra
cd ~/cursus-devops/projet_fil_rouge_infra/app && terraform apply

# 2. Depuis Git Bash — exporter les IPs
terraform output -json public_ips > ~/cursus-devops/projet-fils-rouge/inventaire/terraform_ips.json

# 3. Depuis WSL — resync + inventaire + déploiement
wsl
rm -rf ~/projet-fils-rouge
cp -r /mnt/c/Users/balde/cursus-devops/projet-fils-rouge ~/projet-fils-rouge
cp /mnt/c/Users/balde/cursus-devops/projet_fil_rouge_infra/.secrets/projet-fil-rouge-key.pem ~/projet-fil-rouge-key.pem
chmod 600 ~/projet-fil-rouge-key.pem
cd ~/projet-fils-rouge
bash inventaire/generate_inventory.sh
ansible-playbook -i inventaire/hosts.yml playbook.yml -v

# 4. Depuis Git Bash — destroy fin de session
cd ~/cursus-devops/projet_fil_rouge_infra/app && terraform destroy
```

## Structure Terraform
```
projet_fil_rouge_infra/app/
├── main.tf          # Backend S3 + provider + modules sg/ec2/eip
├── outputs.tf       # output public_ips (map jenkins/webapp/odoo)
├── variables.tf     # region, key_name, environment
└── terraform.tfvars # region=us-east-1 | key=projet-fil-rouge-key | env=prod
modules/ : security_group | ec2 | eip
Ports SG : 22, 80, 8080, 8069, 5050
```

## Structure Ansible
```
projet-fils-rouge/
├── Dockerfile                         # python:3.6-alpine, lit releases.txt via awk
├── releases.txt                       # ODOO_URL, PGADMIN_URL, version (tag image)
├── Jenkinsfile                        # Pipeline CI/CD complet
├── ansible.cfg                        # Config globale Ansible
├── playbook.yml                       # Playbook principal (3 plays)
├── requirements.yml                   # community.docker
├── README.md                          # Guide de reproduction
├── inventaire/
│   ├── generate_inventory.sh          # Lit terraform_ips.json → génère hosts.yml
│   ├── terraform_ips.json             # Généré depuis Git Bash (ignoré par git)
│   └── hosts.yml.example              # Modèle inventaire (hosts.yml ignoré par git)
├── jenkins-tools/
│   ├── Dockerfile                     # Image Jenkins custom (CentOS7 — non utilisée)
│   ├── docker-compose.yml             # Référence sadofrazer/jenkins
│   ├── jenkins.conf                   # Config Nginx reverse proxy
│   ├── jenkins-install.sh             # Script installation Jenkins
│   └── init/README-credentials.md    # Guide configuration credentials Jenkins
├── odoo/docker-compose.yml            # Odoo 13 + PostgreSQL
├── pgadmin/
│   ├── docker-compose.yml             # pgAdmin4
│   └── servers.json                   # Préconfiguration connexion BDD
├── templates/index.html               # Site vitrine IC Group
├── static/                            # CSS + images
└── roles/
    ├── odoo_role/                     # Odoo 13 + PostgreSQL via docker-compose
    ├── pgadmin_role/                  # pgAdmin4 + servers.json préconfiguré
    ├── webapp_role/                   # ic-webapp + ODOO_URL/PGADMIN_URL injectées
    └── jenkins_role/                  # jenkins/jenkins:lts
```

## Pipeline Jenkins — étapes
1. Checkout       — récupération du code
2. Read Version   — lecture version/URLs depuis releases.txt via awk
3. Build          — docker build, tag = version releases.txt
4. Test           — container test-ic-webapp, curl sur port 8085
5. Push           — docker push sur Docker Hub (tag version + latest)
6. Deploy         — ansible-playbook sur les 3 serveurs

## Credentials Jenkins à configurer (1 seule fois)
- docker-hub-credentials : Username/password Docker Hub (alphabalde)
- ansible-ssh-key        : Secret file → projet-fil-rouge-key.pem

## Avancement
- [x] Partie 1 : Conteneurisation Docker — COMPLÈTE
- [x] Partie 2 : CI/CD Jenkins + Ansible — COMPLÈTE (reste : credentials + test pipeline)
- [ ] Partie 3 : Kubernetes (Minikube) — À FAIRE
