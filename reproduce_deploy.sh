#!/bin/bash
# ============================================================
# reproduce_deploy.sh — Partie 2 : Deploiement Ansible
# A lancer depuis Vagrant apres reproduce_infra.sh
#
# Etapes :
#   1. Verification de la cle SSH
#   2. Installation des dependances Ansible
#   3. Generation de l'inventaire depuis terraform_ips.json
#   4. Attente disponibilite SSH des instances AWS
#   5. Deploiement via ansible-playbook
#
# Prerequis :
#   - reproduce_infra.sh execute avec succes
#   - terraform_ips.json present dans inventaire/
#   - Cle SSH projet-fil-rouge-key.pem dans ~/.ssh/
#
# Utilisation :
#   bash reproduce_deploy.sh
# ============================================================

set -e  # Arret immediat si une commande echoue

# Chemins relatifs au repo — tout est dans le meme repo
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$SCRIPT_DIR"
SSH_KEY="$HOME/.ssh/projet-fil-rouge-key.pem"
IPS_FILE="$REPO_DIR/inventaire/terraform_ips.json"
SLEEP_SSH=90    # Secondes d'attente avant que SSH soit disponible sur AWS
SLEEP_PLAYS=20  # Secondes entre les plays Ansible

echo "============================================================"
echo " Reproduction Partie 2 — Deploiement Ansible"
echo "============================================================"

# --------------------------------------------------------
# Etape 1 : Verification de la cle SSH
# La cle doit etre placee dans ~/.ssh/ avant de lancer
# --------------------------------------------------------
echo ""
echo "[1/4] Verification de la cle SSH..."
if [ ! -f "$SSH_KEY" ]; then
    echo "❌ Cle SSH introuvable : $SSH_KEY"
    echo "   Copier la cle avec : cp projet-fil-rouge-key.pem ~/.ssh/ && chmod 600 ~/.ssh/projet-fil-rouge-key.pem"
    exit 1
fi
chmod 600 "$SSH_KEY"
echo "✅ Cle SSH prete : $SSH_KEY"

# --------------------------------------------------------
# Etape 2 : Installation des dependances Ansible
# --------------------------------------------------------
echo ""
echo "[2/4] Installation des dependances Ansible..."
cd "$REPO_DIR"
ansible-galaxy collection install community.docker
echo "✅ Dependances installees"

# --------------------------------------------------------
# Etape 3 : Generation de l'inventaire Ansible
# --------------------------------------------------------
echo ""
echo "[3/4] Generation de l'inventaire Ansible..."
bash inventaire/generate_inventory.sh
echo "✅ Inventaire genere"

# --------------------------------------------------------
# Etape 4 : Attente disponibilite SSH
# Les instances AWS ont besoin de temps pour demarrer
# et accepter les connexions SSH apres terraform apply
# --------------------------------------------------------
echo ""
echo "[4/4] Attente disponibilite SSH des instances AWS..."
echo "      (${SLEEP_SSH}s — demarrage EC2 + cloud-init)"

for i in $(seq "$SLEEP_SSH" -10 10); do
    echo "      ... encore ${i}s"
    sleep 10
done

# --------------------------------------------------------
# Verification SSH avant de lancer Ansible
# --------------------------------------------------------
echo ""
echo "      Verification SSH..."
ansible all -i inventaire/hosts.yml -m ping --timeout=10 || {
    echo ""
    echo "⚠️  SSH pas encore pret, on attend 30s de plus..."
    sleep 30
    ansible all -i inventaire/hosts.yml -m ping --timeout=10 || {
        echo "❌ Instances SSH inaccessibles. Verifiez votre Security Group."
        exit 1
    }
}
echo "✅ Toutes les instances sont accessibles"

# --------------------------------------------------------
# Deploiement Ansible
# Les plays sont separes par des sleeps pour laisser
# chaque service demarrer avant le suivant
# --------------------------------------------------------
echo ""
echo "      Lancement du deploiement Ansible..."
echo ""

# Play 1 : Odoo + PostgreSQL
echo "--- Play 1 : Odoo + PostgreSQL ---"
ansible-playbook \
    -i inventaire/hosts.yml \
    --private-key="$SSH_KEY" \
    --limit odoo \
    playbook.yml -v

echo ""
echo "      Attente demarrage Odoo + PostgreSQL (${SLEEP_PLAYS}s)..."
sleep "$SLEEP_PLAYS"

# Play 2 : ic-webapp + pgAdmin
echo "--- Play 2 : ic-webapp + pgAdmin ---"
ansible-playbook \
    -i inventaire/hosts.yml \
    --private-key="$SSH_KEY" \
    --limit webapp \
    playbook.yml -v

echo ""
echo "      Attente demarrage ic-webapp + pgAdmin (${SLEEP_PLAYS}s)..."
sleep "$SLEEP_PLAYS"

# Play 3 : Jenkins
echo "--- Play 3 : Jenkins ---"
ansible-playbook \
    -i inventaire/hosts.yml \
    --private-key="$SSH_KEY" \
    --limit jenkins \
    playbook.yml -v

# --------------------------------------------------------
# Recapitulatif final
# --------------------------------------------------------
echo ""
echo "============================================================"
echo " Deploiement termine !"
echo "============================================================"

JENKINS_IP=$(jq -r '.jenkins' "$IPS_FILE")
WEBAPP_IP=$(jq  -r '.webapp'  "$IPS_FILE")
ODOO_IP=$(jq    -r '.odoo'    "$IPS_FILE")

echo ""
echo " Acces aux services :"
echo "   Jenkins   -> http://${JENKINS_IP}:8080"
echo "   ic-webapp -> http://${WEBAPP_IP}"
echo "   pgAdmin   -> http://${WEBAPP_IP}:5050"
echo "   Odoo      -> http://${ODOO_IP}:8069"
echo ""
echo " Fin de session :"
echo "   bash reproduce_infra.sh destroy"
echo "============================================================"
