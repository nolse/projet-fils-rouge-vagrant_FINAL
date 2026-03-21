# Projet Fil Rouge — Avancement

## Stack
- Terraform 1.14.5 | AWS us-east-1
- Backend S3 : terraform-backend-balde
- Repo infra  : https://github.com/nolse/projet_fil_rouge_infra
- Repo ansible: https://github.com/nolse/projet-fils-rouge

## IPs (dynamiques — regénérer après chaque apply)
- Workflow : terraform apply → terraform_ips.json → generate_inventory.sh

## Étapes
- [x] Partie 1 : Conteneurisation Docker — COMPLÈTE
      - [x] Dockerfile (python:3.6-alpine, awk releases.txt)
      - [x] releases.txt (ODOO_URL, PGADMIN_URL, version)
      - [x] ic-webapp:1.0 buildée et pushée → alphabalde/ic-webapp:1.0
      - [x] odoo/docker-compose.yml
      - [x] pgadmin/docker-compose.yml + servers.json
      - [x] jenkins-tools/
- [x] Partie 2 : CI/CD Jenkins + Ansible
      - [x] roles : odoo_role / pgadmin_role / webapp_role / jenkins_role
      - [x] inventaire dynamique Terraform→Ansible
      - [x] playbook.yml + ansible.cfg + requirements.yml
      - [x] Jenkinsfile
      - [x] Déploiement 3 serveurs validé ✅
      - [x] Jenkins  → http://<jenkins_ip>:8080 ✅
      - [x] ic-webapp → http://<webapp_ip> ✅
      - [x] pgAdmin  → http://<webapp_ip>:5050 ✅
      - [x] Odoo     → http://<odoo_ip>:8069 ✅
      - [X] Configurer credentials Jenkins (docker-hub + ansible-ssh-key)
      - [X] Créer job Jenkins (pointer vers repo GitHub)
      - [X] Tester pipeline end-to-end
- [ ] Partie 3 : Kubernetes (Minikube)
      - [ ] Namespace icgroup
      - [ ] Manifests ic-webapp (Deployment + Service)
      - [ ] Manifests Odoo + BDD_Odoo (Deployment + Service + PVC)
      - [ ] Manifests pgAdmin (Deployment + Service)
      - [ ] Secrets Kubernetes (données sensibles)
      - [ ] Labels env=prod sur toutes les ressources
