# Projet Fil Rouge — Avancement

## Stack
- Terraform 1.14.5
- AWS us-east-1
- Backend S3 : terraform-backend-balde
- Repo infra : https://github.com/nolse/projet_fil_rouge_infra

## IPs (terraform output)
- jenkins : 32.193.17.236
- odoo     : 18.208.85.139
- webapp   : 52.7.104.104

## Étapes
- [x] Prérequis locaux
- [x] Bucket S3 + versioning
- [x] Git initialisé
- [x] Modules Terraform (security_group, ec2, ebs, eip)
- [x] terraform apply — 3 VMs opérationnelles
- [x] SSH OK sur les 3 serveurs
- [x] Partie 1 : Conteneurisation app vitrine (Docker)
- [x] Partie 2 : Pipeline CI/CD Jenkins + Ansible
- [x] Partie 3 : Kubernetes
