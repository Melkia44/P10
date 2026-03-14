# P10 BottleNeck — Pipeline Kestra + Alerting SMTP

## Structure du projet

```
P10/
├── Data/                       ← Fichiers sources (inputs)
│   ├── Fichier_erp.xlsx            ERP : 825 produits, prix, stock
│   ├── fichier_liaison.xlsx        Liaison : correspondance ERP ↔ Web
│   └── Fichier_web.xlsx            Web : catalogue WooCommerce, ventes
│
├── install/                    ← Scripts d'installation + workflow
│   ├── install_pipeline.sh         Lance Docker, Kestra, MailHog
│   ├── stop_pipeline.sh            Arrête tout proprement
│   ├── workflow_bottleneck_smtp.yaml   Workflow Kestra (template)
│   ├── workflow_ready.yaml         Généré par le script (prêt à coller)
│   └── README.md                   Ce fichier
│
├── Output/                     ← Livrables données (générés par le pipeline)
│   ├── rapport_ca_par_produit.xlsx     CA par produit (714 lignes)
│   ├── vins_millesimes.csv             651 vins millésimés
│   └── vins_ordinaires.csv            63 vins ordinaires
│
└── Presentation/               ← Documents de soutenance
    ├── diagramme_flux_pipeline.drawio  Diagramme du pipeline
    └── presentation_soutenance_P10.pptx  11 slides pour la soutenance
```

---

## Installation rapide

### Prérequis
- Linux (Ubuntu/Debian)
- Docker + Docker Compose installés
- Droits Docker : `sudo usermod -aG docker $USER && newgrp docker`

### Lancer l'environnement
```bash
cd ~/P10/install
chmod +x install_pipeline.sh stop_pipeline.sh
bash install_pipeline.sh
```

Le script fait tout automatiquement :
1. Vérifie que les 3 Excel sont dans `P10/Data/`
2. Lance Kestra (http://localhost:8080)
3. Lance MailHog sur le même réseau Docker que Kestra
4. Génère `workflow_ready.yaml` avec la bonne IP SMTP et le `transportStrategy: SMTP`

### Importer et exécuter le workflow
1. Ouvrir **http://localhost:8080** (Kestra)
2. Flows → **+ Create**
3. Supprimer le contenu par défaut
4. Copier-coller le workflow généré :
   ```bash
   cat ~/P10/install/workflow_ready.yaml
   ```
5. Cliquer **Save**
6. Cliquer **Execute** → uploader les 3 fichiers depuis `P10/Data/` :
   - erp_file → `Fichier_erp.xlsx`
   - liaison_file → `fichier_liaison.xlsx`
   - web_file → `Fichier_web.xlsx`
7. Vérifier l'email dans **http://localhost:8025** (MailHog)

### Arrêter tout
```bash
cd ~/P10/install
bash stop_pipeline.sh
```

---

## Chiffres clés (soutenance)

| Métrique | Valeur |
|----------|--------|
| Produits finaux | **714** |
| CA Global | **70 568,60 EUR** |
| Millésimés | **651** (91.2%) |
| Ordinaires | **63** (8.8%) |
| Tests | **8/8 PASS** |
| Z-score seuil | **3** (configurable) |
| Outliers millésimés | 15 (2.3%) |
| Outliers ordinaires | 1 (1.6%) |

---

## Résumé technique pour le jury

**Pipeline :** 6 tâches Kestra séquentielles (ingestion, fusion, CA, classification, tests, notification)

**Alerting SMTP :** Bloc errors natif Kestra + MailSend. MailHog en démo, SMTP entreprise en production. Emails succès et erreur.

**Z-Score :** Configurable via variables Kestra (seuil=3, max_outlier=5%). Injecté en env dans les containers Python.

**Kestra vs Airflow :** Kestra choisi pour sa simplicité (YAML, Docker natif, UI intégrée). Airflow pertinent pour des centaines de DAGs avec scheduling avancé.
