#!/bin/bash
# ============================================================
# Arrête Kestra et MailHog proprement
# ============================================================

echo "Arrêt de Kestra..."
cd "$HOME/bottleneck-pipeline" 2>/dev/null && docker compose down 2>/dev/null
echo "Arrêt de MailHog..."
docker rm -f mailhog 2>/dev/null

echo ""
echo "✅ Tout est arrêté."
echo ""
echo "Pour relancer :"
echo "  cd ~/P10/install && bash install_pipeline.sh"
