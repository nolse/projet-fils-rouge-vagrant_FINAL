#!/bin/bash
# =============================================================
# SETUP NETWORK - Projet Fil Rouge Kubernetes
# =============================================================
# Configure les regles iptables pour rendre les NodePorts
# Kubernetes accessibles depuis l'hote via l'IP de la VM Vagrant.
#
# Architecture reseau :
#   Hote -> 192.168.56.100 (enp0s8) -> DNAT -> 192.168.49.2 (Minikube)
#
# NOTE : L'interface bridge Minikube (br-XXXX) change a chaque
# redemarrage de Docker. Ce script la detecte automatiquement.
#
# Usage : bash setup-network.sh
# Idempotent : verifie si les regles existent avant de les ajouter.
# =============================================================
set -e
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# --- Configuration fixe ---
VM_IP="192.168.56.100"
MINIKUBE_IP="192.168.49.2"
HOST_IFACE="enp0s8"

# NodePorts exposes
WEBAPP_PORT=30080
ODOO_PORT=30069
PGADMIN_PORT=30050

# --- Detection automatique de l'interface bridge Minikube ---
# L'interface bridge change de nom a chaque redemarrage de Docker.
# On la detecte via l'IP du gateway Minikube (192.168.49.1).
echo -e "${YELLOW}>>> Detection de l'interface bridge Minikube...${NC}"
MINIKUBE_IFACE=$(ip route | grep 192.168.49 | awk '{print $3}')

if [ -z "$MINIKUBE_IFACE" ]; then
    echo -e "${RED}ERREUR : Interface bridge Minikube introuvable.${NC}"
    echo -e "${RED}Verifiez que Minikube est demarre : minikube start --driver=docker${NC}"
    exit 1
fi

echo -e "${GREEN}>>> Interface bridge detectee : $MINIKUBE_IFACE${NC}"

echo -e "${YELLOW}>>> Configuration du reseau iptables...${NC}"

# --- Activation du forwarding IP ---
echo -e "${YELLOW}>>> Activation du forwarding IP...${NC}"
sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null

# --- Fonction pour ajouter une regle DNAT si elle n'existe pas ---
add_dnat() {
  local port=$1
  if ! sudo iptables -t nat -C PREROUTING -i $HOST_IFACE -p tcp --dport $port -j DNAT --to-destination $MINIKUBE_IP:$port 2>/dev/null; then
    sudo iptables -t nat -A PREROUTING -i $HOST_IFACE -p tcp --dport $port -j DNAT --to-destination $MINIKUBE_IP:$port
    echo -e "${GREEN}>>> DNAT ajoute : $VM_IP:$port -> $MINIKUBE_IP:$port${NC}"
  else
    echo -e "${GREEN}>>> DNAT deja present : $VM_IP:$port -> $MINIKUBE_IP:$port${NC}"
  fi
}

# --- Regles DNAT ---
echo -e "${YELLOW}>>> Ajout des regles DNAT...${NC}"
add_dnat $WEBAPP_PORT
add_dnat $ODOO_PORT
add_dnat $PGADMIN_PORT

# --- MASQUERADE ---
if ! sudo iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null; then
  sudo iptables -t nat -A POSTROUTING -j MASQUERADE
  echo -e "${GREEN}>>> MASQUERADE ajoute${NC}"
fi

# --- Regles FORWARD ---
if ! sudo iptables -C FORWARD -i $HOST_IFACE -o $MINIKUBE_IFACE -j ACCEPT 2>/dev/null; then
  sudo iptables -A FORWARD -i $HOST_IFACE -o $MINIKUBE_IFACE -j ACCEPT
fi
if ! sudo iptables -C FORWARD -i $MINIKUBE_IFACE -o $HOST_IFACE -j ACCEPT 2>/dev/null; then
  sudo iptables -A FORWARD -i $MINIKUBE_IFACE -o $HOST_IFACE -j ACCEPT
fi

echo -e "${GREEN}>>> Configuration reseau terminee !${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}URLs accessibles depuis l'hote :${NC}"
echo -e "${GREEN}======================================${NC}"
echo -e "ic-webapp -> http://$VM_IP:$WEBAPP_PORT"
echo -e "Odoo      -> http://$VM_IP:$ODOO_PORT"
echo -e "pgAdmin   -> http://$VM_IP:$PGADMIN_PORT"
echo -e "${GREEN}======================================${NC}"
