#!/bin/bash
# Arrête Kestra, Postgres et MailHog
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
docker compose down
echo ""
echo "✅ Tout est arrêté."
echo "Pour relancer : cd ~/P10/install && bash install_pipeline.sh"
