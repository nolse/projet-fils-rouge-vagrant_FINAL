#!/bin/bash
# =============================================================
# COMMANDES UTILITAIRES - Partie 3 Kubernetes
# =============================================================
# Ce script regroupe toutes les commandes utiles du projet.
# Usage : bash kubernetes/commandes_utils.sh [action]
#
# Actions disponibles :
#   deploy    -> deploie toutes les ressources Kubernetes
#   status    -> affiche l'etat de tous les pods/services
#   urls      -> affiche les URLs d'acces aux applications
#   creds     -> affiche les identifiants de connexion
#   inject-ip -> injecte l'IP VM Vagrant dans les manifests
#   open      -> lance les port-forwards (optionnel sur Vagrant)
#   clean     -> supprime toutes les ressources du namespace
# =============================================================

set -e  # Arrete le script si une commande echoue

# --- Couleurs pour les messages ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# --- IP fixe de la VM Vagrant (definie dans le Vagrantfile) ---
VM_IP="192.168.56.100"

# --- Injection IP VM Vagrant dans webapp/deployment.yml ---
# L'IP est fixe (192.168.56.100) et ne change pas entre les sessions.
inject_ip() {
  echo -e "${YELLOW}>>> Injection de l'IP VM Vagrant...${NC}"
  echo -e "${GREEN}IP VM Vagrant : $VM_IP${NC}"

  sed -i "s|http://[0-9.]*:30069|http://$VM_IP:30069|g" kubernetes/webapp/deployment.yml
  sed -i "s|http://[0-9.]*:30050|http://$VM_IP:30050|g" kubernetes/webapp/deployment.yml

  echo -e "${GREEN}>>> IP injectee dans kubernetes/webapp/deployment.yml${NC}"
  grep "http://" kubernetes/webapp/deployment.yml
}

# --- Deploiement complet dans l'ordre des dependances ---
deploy_all() {
  echo -e "${YELLOW}>>> Injection de l'IP VM Vagrant...${NC}"
  inject_ip

  echo -e "${YELLOW}>>> Deploiement du namespace...${NC}"
  kubectl apply -f kubernetes/namespace.yml

  echo -e "${YELLOW}>>> Deploiement des secrets...${NC}"
  kubectl apply -f kubernetes/secrets.yml

  echo -e "${YELLOW}>>> Deploiement de PostgreSQL...${NC}"
  kubectl apply -f kubernetes/postgres/
  echo ">>> Attente demarrage PostgreSQL (30s)..."
  sleep 30

  echo -e "${YELLOW}>>> Deploiement d'Odoo...${NC}"
  kubectl apply -f kubernetes/odoo/
  echo ">>> Attente demarrage Odoo (60s)..."
  sleep 60

  echo -e "${YELLOW}>>> Deploiement de pgAdmin...${NC}"
  kubectl apply -f kubernetes/pgadmin/
  echo ">>> Attente demarrage pgAdmin (30s)..."
  sleep 30

  echo -e "${YELLOW}>>> Deploiement de ic-webapp...${NC}"
  kubectl apply -f kubernetes/webapp/

  echo -e "${YELLOW}>>> Deploiement de l'Ingress...${NC}"
  kubectl apply -f kubernetes/ingress.yml
  echo ">>> Attente propagation Ingress (180s)..."
  echo ">>> Les URLs par nom de domaine seront disponibles a la fin de ce delai."
  echo ">>> Merci de patienter..."
  sleep 180

  echo -e "${GREEN}>>> Deploiement termine !${NC}"
  status
  urls
  creds
}

# --- Statut de tous les pods et services ---
status() {
  echo -e "${YELLOW}>>> Pods :${NC}"
  kubectl get pods -n icgroup

  echo -e "${YELLOW}>>> Services :${NC}"
  kubectl get services -n icgroup

  echo -e "${YELLOW}>>> PVC :${NC}"
  kubectl get pvc -n icgroup

  echo -e "${YELLOW}>>> Ingress :${NC}"
  kubectl get ingress -n icgroup
}

# --- Affichage des URLs d'acces ---
# Sur Vagrant, les NodePorts sont directement accessibles
# depuis Windows via l'IP fixe de la VM (192.168.56.100).
# L'Ingress permet egalement l'acces par nom de domaine
# (necessite la configuration du fichier hosts Windows).
urls() {
  echo -e "${GREEN}======================================${NC}"
  echo -e "${GREEN}URLs accessibles depuis Windows :${NC}"
  echo -e "${GREEN}======================================${NC}"
  echo -e "${YELLOW}--- Acces par NodePort :${NC}"
  echo -e "ic-webapp -> http://$VM_IP:30080"
  echo -e "Odoo      -> http://$VM_IP:30069"
  echo -e "pgAdmin   -> http://$VM_IP:30050"
  echo -e ""
  echo -e "${YELLOW}--- Acces par nom de domaine (Ingress) :${NC}"
  echo -e "ic-webapp -> http://ic-webapp.icgroup.fr"
  echo -e "Odoo      -> http://odoo.icgroup.fr"
  echo -e "pgAdmin   -> http://pgadmin.icgroup.fr"
  echo -e ""
  echo -e "${YELLOW}Note : Les noms de domaine necessitent la ligne suivante${NC}"
  echo -e "${YELLOW}dans C:\\Windows\\System32\\drivers\\etc\\hosts (Windows) :${NC}"
  echo -e "192.168.56.100  ic-webapp.icgroup.fr odoo.icgroup.fr pgadmin.icgroup.fr"
  echo -e "${GREEN}======================================${NC}"
}

# --- Affichage des identifiants de connexion ---
# Les identifiants sont definis dans kubernetes/secrets.yml
# (encodes en base64 - ne pas committer avec de vrais mots de passe).
creds() {
  echo -e "${GREEN}======================================${NC}"
  echo -e "${GREEN}Identifiants de connexion :${NC}"
  echo -e "${GREEN}======================================${NC}"
  echo -e "${YELLOW}ic-webapp :${NC}"
  echo -e "  URL      -> http://ic-webapp.icgroup.fr"
  echo -e ""
  echo -e "${YELLOW}pgAdmin :${NC}"
  echo -e "  URL      -> http://pgadmin.icgroup.fr"
  echo -e "  Email    -> admin@icgroup.fr"
  echo -e "  Password -> pgadmin_password"
  echo -e ""
  echo -e "${YELLOW}Odoo :${NC}"
  echo -e "  URL      -> http://odoo.icgroup.fr"
  echo -e "  Login    -> admin"
  echo -e "  Password -> admin"
  echo -e ""
  echo -e "${YELLOW}PostgreSQL (via pgAdmin) :${NC}"
  echo -e "  Host     -> postgres-service"
  echo -e "  Port     -> 5432"
  echo -e "  Base     -> odoo"
  echo -e "  User     -> odoo"
  echo -e "  Password -> odoo_password"
  echo -e "${GREEN}======================================${NC}"
}

# Cette action reste disponible si besoin de rediriger des ports.
open() {
  echo -e "${YELLOW}>>> Liberation des ports si deja occupes...${NC}"
  fuser -k 8080/tcp 2>/dev/null || true
  fuser -k 8069/tcp 2>/dev/null || true
  fuser -k 8050/tcp 2>/dev/null || true

  echo -e "${YELLOW}>>> Ouverture des port-forwards...${NC}"
  echo -e "${YELLOW}IMPORTANT : ne pas fermer ce terminal !${NC}"
  echo ""

  kubectl port-forward -n icgroup svc/ic-webapp-service 8080:8080 --address 0.0.0.0 &
  kubectl port-forward -n icgroup svc/odoo-service 8069:8069 --address 0.0.0.0 &
  kubectl port-forward -n icgroup svc/pgadmin-service 8050:80 --address 0.0.0.0 &

  urls
  wait
}

# --- Nettoyage complet ---
clean() {
  echo -e "${RED}>>> Suppression de toutes les ressources icgroup...${NC}"
  kubectl delete namespace icgroup
  echo -e "${GREEN}>>> Namespace icgroup supprime.${NC}"
}

# --- Point d'entree ---
case "$1" in
  deploy)      deploy_all ;;
  status)      status ;;
  urls)        urls ;;
  creds)       creds ;;
  inject-ip)   inject_ip ;;
  open)        open ;;
  clean)       clean ;;
  *)
    echo "Usage : bash kubernetes/commandes_utils.sh [action]"
    echo ""
    echo "Actions disponibles :"
    echo "  deploy     -> deploie toutes les ressources"
    echo "  status     -> etat des pods/services/pvc"
    echo "  urls       -> affiche les URLs accessibles depuis Windows"
    echo "  creds      -> affiche les identifiants de connexion"
    echo "  inject-ip  -> injecte l'IP VM Vagrant dans webapp"
    echo "  open       -> lance les port-forwards (optionnel sur Vagrant)"
    echo "  clean      -> supprime le namespace icgroup"
    ;;
esac
