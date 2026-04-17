# Image de base légère Python 3.6 (imposée par le cahier des charges)
FROM python:3.6-alpine

# Répertoire de travail dans le conteneur
WORKDIR /opt

# Installation de curl (utile pour les tests HTTP dans Jenkins)
# apk = gestionnaire de paquets Alpine
RUN apk add --no-cache curl

# Copie du code source dans le conteneur
COPY . .

# Installation de Flask
RUN pip install flask==1.1.2

# Lecture de releases.txt et injection des variables d'environnement
# awk récupère la 2ème colonne de chaque ligne (séparateur = espace)
RUN export ODOO_URL=$(awk '/ODOO_URL/{print $2}' releases.txt) && \
    export PGADMIN_URL=$(awk '/PGADMIN_URL/{print $2}' releases.txt) && \
    echo "ODOO_URL=$ODOO_URL" && \
    echo "PGADMIN_URL=$PGADMIN_URL"

# Variables d'environnement disponibles au runtime du container
ENV ODOO_URL=""
ENV PGADMIN_URL=""

# Port exposé par l'application Flask
EXPOSE 8080

# Lancement de l'application
ENTRYPOINT ["python", "app.py"]
