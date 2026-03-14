#!/bin/bash
# ============================================================
# SCRIPT D'INSTALLATION — Pipeline BottleNeck P10
# Structure attendue :
#   ~/P10/Data/          → 3 fichiers Excel (inputs)
#   ~/P10/install/       → ce script + workflow_bottleneck_smtp.yaml
#   ~/P10/Output/        → livrables générés par le pipeline
#   ~/P10/Presentation/  → docs de soutenance
# ============================================================

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Détecter les dossiers du projet
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
P10_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$P10_DIR/Data"
OUTPUT_DIR="$P10_DIR/Output"
INSTALL_DIR="$SCRIPT_DIR"
KESTRA_DIR="$HOME/bottleneck-pipeline"

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  INSTALLATION PIPELINE BOTTLENECK — P10 Data Engineer${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "  Projet:  $P10_DIR"
echo -e "  Data:    $DATA_DIR"
echo -e "  Output:  $OUTPUT_DIR"
echo -e "  Install: $INSTALL_DIR"
echo ""

# -----------------------------------------------
# 0. Vérifier que les fichiers Excel sont présents
# -----------------------------------------------
echo -e "${YELLOW}[0/6] Vérification des fichiers sources...${NC}"
MISSING=false
for f in "Fichier_erp.xlsx" "fichier_liaison.xlsx" "Fichier_web.xlsx"; do
    if [ -f "$DATA_DIR/$f" ]; then
        echo -e "${GREEN}  ✅ $f${NC}"
    else
        echo -e "${RED}  ❌ $f manquant dans $DATA_DIR/${NC}"
        MISSING=true
    fi
done
if $MISSING; then
    echo -e "${RED}Place les 3 fichiers Excel dans $DATA_DIR/ et relance le script.${NC}"
    exit 1
fi

# Créer le dossier Output s'il n'existe pas
mkdir -p "$OUTPUT_DIR"

# -----------------------------------------------
# 1. Vérifier Docker
# -----------------------------------------------
echo ""
echo -e "${YELLOW}[1/6] Vérification de Docker...${NC}"
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker n'est pas installé.${NC}"
    echo "  sudo apt update && sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin"
    echo "  sudo usermod -aG docker \$USER && newgrp docker"
    exit 1
fi
if ! docker info &> /dev/null; then
    echo -e "${RED}Docker n'est pas accessible.${NC}"
    echo "  sudo usermod -aG docker \$USER && newgrp docker"
    exit 1
fi
echo -e "${GREEN}  ✅ Docker OK ($(docker --version))${NC}"
echo -e "${GREEN}  ✅ Docker Compose OK${NC}"

# -----------------------------------------------
# 2. Lancer Kestra
# -----------------------------------------------
echo ""
echo -e "${YELLOW}[2/6] Lancement de Kestra...${NC}"
mkdir -p "$KESTRA_DIR"

if [ ! -f "$KESTRA_DIR/docker-compose.yml" ]; then
    curl -sSL -o "$KESTRA_DIR/docker-compose.yml" \
        https://raw.githubusercontent.com/kestra-io/kestra/develop/docker-compose.yml
    echo -e "${GREEN}  ✅ docker-compose.yml téléchargé${NC}"
fi

cd "$KESTRA_DIR"
docker compose up -d 2>&1 | tail -5

echo -e "${YELLOW}  Attente du démarrage de Kestra (40s)...${NC}"
sleep 40

KESTRA_OK=false
for i in {1..12}; do
    if curl -s http://localhost:8080 > /dev/null 2>&1; then
        KESTRA_OK=true
        break
    fi
    sleep 5
done

if $KESTRA_OK; then
    echo -e "${GREEN}  ✅ Kestra démarré: http://localhost:8080${NC}"
else
    echo -e "${YELLOW}  ⚠️  Kestra met du temps. Vérifie http://localhost:8080 dans 1-2 min.${NC}"
fi

# -----------------------------------------------
# 3. Trouver le réseau Docker de Kestra
# -----------------------------------------------
echo ""
echo -e "${YELLOW}[3/6] Détection du réseau Kestra...${NC}"

KESTRA_CONTAINER=$(docker ps --format '{{.Names}}' | grep -i kestra | grep -v postgres | head -1)
if [ -z "$KESTRA_CONTAINER" ]; then
    echo -e "${RED}  ❌ Container Kestra non trouvé${NC}"
    exit 1
fi

KESTRA_NETWORK=$(docker inspect -f '{{range $key, $value := .NetworkSettings.Networks}}{{$key}} {{end}}' "$KESTRA_CONTAINER" | tr ' ' '\n' | head -1)
echo -e "${GREEN}  ✅ Réseau Kestra: $KESTRA_NETWORK${NC}"

# -----------------------------------------------
# 4. Lancer MailHog sur le même réseau
# -----------------------------------------------
echo ""
echo -e "${YELLOW}[4/6] Lancement de MailHog (serveur SMTP)...${NC}"

docker rm -f mailhog > /dev/null 2>&1 || true

docker run -d \
    --name mailhog \
    --network "$KESTRA_NETWORK" \
    -p 1025:1025 \
    -p 8025:8025 \
    mailhog/mailhog > /dev/null 2>&1

sleep 3

if docker ps --format '{{.Names}}' | grep -q '^mailhog$'; then
    MAILHOG_IP=$(docker inspect -f "{{with index .NetworkSettings.Networks \"$KESTRA_NETWORK\"}}{{.IPAddress}}{{end}}" mailhog)
    echo -e "${GREEN}  ✅ MailHog démarré sur $KESTRA_NETWORK${NC}"
    echo -e "${GREEN}     IP: $MAILHOG_IP | SMTP: :1025 | Web: http://localhost:8025${NC}"
else
    echo -e "${RED}  ❌ Erreur au lancement de MailHog${NC}"
    exit 1
fi

# -----------------------------------------------
# 5. Générer le workflow prêt à l'emploi
# -----------------------------------------------
echo ""
echo -e "${YELLOW}[5/6] Génération du workflow...${NC}"

WORKFLOW_SRC="$INSTALL_DIR/workflow_bottleneck_smtp.yaml"
WORKFLOW_OUT="$INSTALL_DIR/workflow_ready.yaml"

if [ -f "$WORKFLOW_SRC" ]; then
    # Remplacer l'IP SMTP
    sed "s|host.docker.internal|$MAILHOG_IP|g" "$WORKFLOW_SRC" > /tmp/wf_step1.yaml

    # Ajouter transportStrategy: SMTP après chaque ligne port: smtp_port
    awk '
    /port:.*smtp_port/ {
        print
        match($0, /^[[:space:]]*/)
        indent = substr($0, RSTART, RLENGTH)
        print indent "transportStrategy: SMTP"
        next
    }
    { print }
    ' /tmp/wf_step1.yaml > "$WORKFLOW_OUT"

    rm /tmp/wf_step1.yaml
    echo -e "${GREEN}  ✅ Workflow généré: $WORKFLOW_OUT${NC}"
    echo -e "${GREEN}     smtp_host = $MAILHOG_IP${NC}"
    echo -e "${GREEN}     transportStrategy = SMTP${NC}"
else
    echo -e "${RED}  ❌ $WORKFLOW_SRC non trouvé${NC}"
    echo -e "${RED}     Place workflow_bottleneck_smtp.yaml dans $INSTALL_DIR/${NC}"
    exit 1
fi

# -----------------------------------------------
# 6. Préparer les commandes utiles
# -----------------------------------------------
echo ""
echo -e "${YELLOW}[6/6] Préparation terminée.${NC}"

echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  INSTALLATION TERMINÉE ✅${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo -e "  ${GREEN}Kestra:${NC}         http://localhost:8080"
echo -e "  ${GREEN}MailHog:${NC}        http://localhost:8025"
echo -e "  ${GREEN}SMTP:${NC}           $MAILHOG_IP:1025 (SMTP, pas SSL)"
echo -e "  ${GREEN}Réseau:${NC}         $KESTRA_NETWORK"
echo ""
echo -e "  ${GREEN}Données:${NC}        $DATA_DIR/"
echo -e "  ${GREEN}Workflow:${NC}       $WORKFLOW_OUT"
echo -e "  ${GREEN}Outputs:${NC}        $OUTPUT_DIR/"
echo ""
echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}  PROCHAINES ÉTAPES${NC}"
echo -e "${BLUE}============================================================${NC}"
echo ""
echo "  1. Ouvre Kestra → http://localhost:8080"
echo "  2. Flows → + Create"
echo "  3. Colle le workflow :"
echo "     cat $WORKFLOW_OUT"
echo "  4. Save"
echo "  5. Execute → uploade les 3 fichiers depuis :"
echo "     $DATA_DIR/"
echo "  6. Vérifie l'email → http://localhost:8025"
echo ""
echo "  Quand le pipeline a tourné, télécharge les outputs"
echo "  depuis Kestra et place-les dans :"
echo "     $OUTPUT_DIR/"
echo ""
