#!/bin/bash
# ============================================================
# generate_inventory.sh
# Génère automatiquement l'inventaire Ansible (hosts.yml)
#
# Deux modes de fonctionnement :
#   1. Fichier terraform_ips.json présent → lecture directe (WSL)
#   2. Sinon → appel terraform output (Git Bash / Linux natif)
#
# Prérequis WSL : générer terraform_ips.json depuis Git Bash :
#   terraform output -json public_ips > inventaire/terraform_ips.json
#
# Compatible : WSL, Linux natif, Git Bash
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/hosts.yml"
IPS_FILE="$SCRIPT_DIR/terraform_ips.json"
SSH_USER="ubuntu"

# --------------------------------------------------------
# Détection automatique de l'environnement
# --------------------------------------------------------
if grep -qi microsoft /proc/version 2>/dev/null; then
    WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')
    SSH_KEY="/mnt/c/Users/${WIN_USER}/.ssh/projet-fil-rouge-key.pem"
else
    SSH_KEY="$HOME/.ssh/projet-fil-rouge-key.pem"
fi

echo "🔍 Environnement détecté : $(uname -s)"

# --------------------------------------------------------
# Récupération des IPs
# Mode 1 : fichier JSON pré-généré (WSL)
# Mode 2 : appel direct terraform (Git Bash / Linux)
# --------------------------------------------------------
if [ -f "$IPS_FILE" ]; then
    echo "📄 Lecture depuis terraform_ips.json..."
    TF_OUTPUT=$(cat "$IPS_FILE")
else
    echo "⚙️  Appel terraform output..."
    if grep -qi microsoft /proc/version 2>/dev/null; then
        WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r')
        TERRAFORM_DIR="/mnt/c/Users/${WIN_USER}/cursus-devops/projet_fil_rouge_infra/app"
    else
        TERRAFORM_DIR="$HOME/cursus-devops/projet_fil_rouge_infra/app"
    fi
    cd "$TERRAFORM_DIR" || { echo "❌ Dossier Terraform introuvable"; exit 1; }
    TF_OUTPUT=$(terraform output -json public_ips 2>/dev/null)
fi

if [ -z "$TF_OUTPUT" ] || [ "$TF_OUTPUT" = "null" ]; then
    echo "❌ Aucune IP trouvée."
    echo "   → Depuis Git Bash : terraform output -json public_ips > inventaire/terraform_ips.json"
    exit 1
fi

JENKINS_IP=$(echo "$TF_OUTPUT" | jq -r '.jenkins')
WEBAPP_IP=$(echo "$TF_OUTPUT"  | jq -r '.webapp')
ODOO_IP=$(echo "$TF_OUTPUT"    | jq -r '.odoo')

echo "✅ IPs récupérées :"
echo "   jenkins : $JENKINS_IP"
echo "   webapp  : $WEBAPP_IP"
echo "   odoo    : $ODOO_IP"

cat > "$OUTPUT_FILE" << YAML
---
# ============================================================
# Inventaire Ansible — généré automatiquement
# Source : terraform output public_ips
# Ne pas modifier manuellement, relancer generate_inventory.sh
# ============================================================

all:
  vars:
    ansible_user: $SSH_USER
    ansible_ssh_private_key_file: $SSH_KEY
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'

  children:
    jenkins:
      hosts:
        jenkins_server:
          ansible_host: $JENKINS_IP

    webapp:
      hosts:
        webapp_server:
          ansible_host: $WEBAPP_IP

    odoo:
      hosts:
        odoo_server:
          ansible_host: $ODOO_IP
YAML

echo "✅ Inventaire généré : $OUTPUT_FILE"
