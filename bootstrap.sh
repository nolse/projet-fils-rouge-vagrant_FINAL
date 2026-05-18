#!/bin/bash
# ============================================================
# bootstrap.sh — Installation des prerequiss
# A lancer une seule fois sur la VM Vagrant
#
# Installe si absent (skip si deja present) :
#   - jq
#   - Terraform
#   - AWS CLI
#   - Python3 + pip3
#   - Ansible 2.15.x (via pip3 — requis pour community.docker >= 3.0.0)
#   - Collection community.docker 3.10.0
#
# Utilisation :
#   bash bootstrap.sh
#   source ~/.bashrc
# ============================================================

set -e

echo "============================================================"
echo " Bootstrap — Installation des prerequiss"
echo "============================================================"

# --------------------------------------------------------
# Mise a jour des paquets
# --------------------------------------------------------
echo ""
echo "[1/6] Mise a jour des paquets..."
sudo apt update -y
echo "✅ Paquets mis a jour"

# --------------------------------------------------------
# Installation de jq
# --------------------------------------------------------
echo ""
echo "[2/6] jq..."
if command -v jq &>/dev/null; then
    echo "⏭️  jq deja installe : $(jq --version)"
else
    sudo apt install -y jq
    echo "✅ jq $(jq --version) installe"
fi

# --------------------------------------------------------
# Installation de Terraform
# --------------------------------------------------------
echo ""
echo "[3/6] Terraform..."
if command -v terraform &>/dev/null; then
    echo "⏭️  Terraform deja installe : $(terraform --version | head -1)"
else
    sudo apt install -y gnupg software-properties-common curl
    curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update -y
    sudo apt install -y terraform
    echo "✅ $(terraform --version | head -1) installe"
fi

# --------------------------------------------------------
# Installation de AWS CLI
# --------------------------------------------------------
echo ""
echo "[4/6] AWS CLI..."
if command -v aws &>/dev/null; then
    echo "⏭️  AWS CLI deja installe : $(aws --version)"
else
    sudo apt install -y unzip
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp
    sudo /tmp/aws/install
    rm -rf /tmp/awscliv2.zip /tmp/aws
    echo "✅ $(aws --version) installe"
fi

# --------------------------------------------------------
# Installation de Python3 + pip3
# --------------------------------------------------------
echo ""
echo "[5/6] Python3 + pip3..."
sudo apt install -y python3 python3-pip
echo "✅ $(python3 --version) / $(pip3 --version)"

# --------------------------------------------------------
# Installation de Ansible via pip3
#
# IMPORTANT : Ansible DOIT etre installe via pip3 et NON via apt.
# La version apt (2.10.x) est incompatible avec community.docker >= 3.0.0
# qui requiert le module docker_compose_v2 absent dans les anciennes versions.
#
# Versions fixees et testees compatibles :
#   ansible-core  : 2.15.12
#   community.docker : 3.10.0
# --------------------------------------------------------
echo ""
echo "[6/6] Ansible (via pip3) + collection community.docker..."

ANSIBLE_VERSION="2.15.12"
DOCKER_COLLECTION_VERSION="3.10.0"

# Desinstaller la version apt si presente pour eviter les conflits
if dpkg -l | grep -q "^ii.*ansible "; then
    echo "⚠️  Version apt d'Ansible detectee — suppression pour eviter les conflits..."
    sudo apt remove -y ansible
fi

# Installer ansible-core via pip3 (version fixee)
if python3 -m pip show ansible-core 2>/dev/null | grep -q "Version: ${ANSIBLE_VERSION}"; then
    echo "⏭️  ansible-core ${ANSIBLE_VERSION} deja installe"
else
    echo "📦 Installation de ansible-core ${ANSIBLE_VERSION}..."
    pip3 install --user "ansible-core==${ANSIBLE_VERSION}"
    echo "✅ ansible-core ${ANSIBLE_VERSION} installe"
fi

# Ajouter ~/.local/bin au PATH si absent
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$HOME/.local/bin:$PATH"
    echo "✅ ~/.local/bin ajoute au PATH"
fi

# Installer la collection community.docker (version fixee)
INSTALLED_DOCKER=$(ansible-galaxy collection list 2>/dev/null | grep "community.docker" | awk '{print $2}' || echo "")
if [ "$INSTALLED_DOCKER" = "${DOCKER_COLLECTION_VERSION}" ]; then
    echo "⏭️  community.docker ${DOCKER_COLLECTION_VERSION} deja presente"
else
    echo "📦 Installation de community.docker ${DOCKER_COLLECTION_VERSION}..."
    ansible-galaxy collection install "community.docker:==${DOCKER_COLLECTION_VERSION}"
    echo "✅ community.docker ${DOCKER_COLLECTION_VERSION} installee"
fi

# --------------------------------------------------------
# Recapitulatif
# --------------------------------------------------------
echo ""
echo "============================================================"
echo " Bootstrap termine !"
echo "============================================================"
echo ""
echo " Versions installees :"
echo "   Terraform        : $(terraform --version | head -1)"
echo "   AWS CLI          : $(aws --version)"
echo "   jq               : $(jq --version)"
echo "   Ansible          : $(ansible --version | head -1)"
echo "   community.docker : $(ansible-galaxy collection list | grep community.docker | awk '{print $2}')"
echo ""
echo " ⚠️  IMPORTANT : Recharger le PATH avant toute commande Ansible :"
echo "   source ~/.bashrc"
echo ""
echo " Prochaine etape :"
echo "   aws configure              # Configurer les credentials AWS"
echo "   cp projet-fil-rouge-key.pem ~/.ssh/"
echo "   chmod 600 ~/.ssh/projet-fil-rouge-key.pem"
echo "   bash reproduce_infra.sh    # Partie 2 - Provisioning AWS"
echo "============================================================"
