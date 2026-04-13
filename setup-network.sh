#!/bin/bash
set -e
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

VM_IP="192.168.56.100"
HOST_IFACE="enp0s8"
WEBAPP_PORT=30080
ODOO_PORT=30069
PGADMIN_PORT=30050

echo -e "${YELLOW}>>> Detection de l'IP Minikube via Docker...${NC}"
MINIKUBE_IP=$(docker inspect minikube | grep '"IPAddress"' | tail -1 | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}')
if [ -z "$MINIKUBE_IP" ]; then
  echo -e "${RED}ERREUR : IP Minikube introuvable.${NC}"
  exit 1
fi
echo -e "${GREEN}>>> IP Minikube : $MINIKUBE_IP${NC}"

MINIKUBE_SUBNET=$(echo $MINIKUBE_IP | cut -d. -f1-3)
MINIKUBE_IFACE=$(ip route | grep $MINIKUBE_SUBNET | awk '{print $3}')
echo -e "${GREEN}>>> Interface bridge : $MINIKUBE_IFACE${NC}"

sudo sysctl -w net.ipv4.ip_forward=1 > /dev/null

# Nettoyage des anciennes règles DNAT
sudo iptables -t nat -F PREROUTING

# Nouvelles règles DNAT
sudo iptables -t nat -A PREROUTING -i $HOST_IFACE -p tcp --dport $WEBAPP_PORT -j DNAT --to-destination $MINIKUBE_IP:$WEBAPP_PORT
sudo iptables -t nat -A PREROUTING -i $HOST_IFACE -p tcp --dport $ODOO_PORT -j DNAT --to-destination $MINIKUBE_IP:$ODOO_PORT
sudo iptables -t nat -A PREROUTING -i $HOST_IFACE -p tcp --dport $PGADMIN_PORT -j DNAT --to-destination $MINIKUBE_IP:$PGADMIN_PORT
sudo iptables -t nat -A POSTROUTING -d $MINIKUBE_IP/24 -j MASQUERADE

# Règles FORWARD
sudo iptables -I FORWARD 1 -i $HOST_IFACE -o $MINIKUBE_IFACE -j ACCEPT
sudo iptables -I FORWARD 1 -i $MINIKUBE_IFACE -o $HOST_IFACE -j ACCEPT

echo -e "${GREEN}>>> Configuration réseau terminée !${NC}"
echo -e "ic-webapp -> http://$VM_IP:$WEBAPP_PORT"
echo -e "Odoo      -> http://$VM_IP:$ODOO_PORT"
echo -e "pgAdmin   -> http://$VM_IP:$PGADMIN_PORT"
