# 🍷 P10 — Pipeline d'orchestration des données BottleNeck

> **Projet Master 2 Data Engineering — OpenClassrooms**  
> Mise en place d'un pipeline ETL complet orchestré avec **Kestra**, conteneurisé avec **Docker**, avec alerting SMTP via **MailHog**.

---

## 📋 Contexte métier

**BottleNeck** est une entreprise de vente de vins en ligne. Les données produits sont dispersées sur trois systèmes hétérogènes :

| Source | Format | Contenu |
|--------|--------|---------|
| ERP | `.xlsx` | Référentiel produits (prix, stock) |
| Fichier liaison | `.xlsx` | Table de correspondance ERP ↔ WooCommerce |
| Export WooCommerce | `.xlsx` | Données de vente en ligne (titres, ventes) |

L'objectif est de **fusionner ces trois sources**, calculer le chiffre d'affaires par produit, classifier les vins (millésimés vs ordinaires) et valider la qualité des données — le tout de façon **automatisée, reproductible et alertée**.

---

## 🏗️ Architecture du pipeline

```
Fichier ERP (.xlsx)
Fichier Liaison (.xlsx)   ──▶  [KESTRA]  ──▶  Outputs
Fichier Web (.xlsx)
                              │
                    ┌─────────▼─────────┐
                    │  1. Ingestion &   │
                    │     Nettoyage     │
                    └─────────┬─────────┘
                              │ erp_clean.csv
                              │ liaison_clean.csv
                              │ web_clean.csv
                    ┌─────────▼─────────┐
                    │  2. Fusion        │
                    │  ERP+Liaison+Web  │
                    └─────────┬─────────┘
                              │ dataset_fusionne.csv
                    ┌─────────▼─────────┐
                    │  3. Calcul CA     │
                    │  par produit      │
                    └─────────┬─────────┘
                              │ rapport_ca_par_produit.xlsx
                    ┌─────────▼─────────┐
                    │  4. Classification│
                    │  Millésimés +     │
                    │  Z-Score          │
                    └─────────┬─────────┘
                              │ vins_millesimes.csv
                              │ vins_ordinaires.csv
                    ┌─────────▼─────────┐
                    │  5. Tests de      │
                    │  validation (8/8) │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │  6. Alerting SMTP │
                    │  (MailHog)        │
                    └───────────────────┘
```

---

## 🛠️ Stack technique

| Outil | Rôle | Version |
|-------|------|---------|
| **Kestra** | Orchestration du pipeline | `0.21.0` |
| **Docker Compose** | Conteneurisation | — |
| **PostgreSQL** | Backend Kestra | `15.6` |
| **MailHog** | Serveur SMTP local (alerting) | `latest` |
| **Python** | Scripts ETL (pandas, scipy) | `3.11-slim` |
| **pandas** | Manipulation des données | `3.0.1` |
| **scipy** | Analyse Z-Score | — |
| **openpyxl** | Lecture/écriture Excel | `3.1.5` |

---

## 📁 Structure du projet

```
P10/
├── Data/                          # Fichiers sources (non versionnés)
│   ├── Fichier_erp.xlsx
│   ├── fichier_liaison.xlsx
│   └── Fichier_web.xlsx
│
├── install/                       # Fichiers de déploiement
│   ├── docker-compose.yml         # Infrastructure Docker
│   ├── workflow.yaml  # Workflow Kestra (pipeline complet)
│   ├── install_pipeline.sh        # Script d'installation automatisé
│   ├── stop_pipeline.sh           # Script d'arrêt
│   └── README.md                  # Ce fichier
│
├── Output/                        # Livrables générés (non versionnés)
│   ├── rapport_ca_par_produit.xlsx
│   ├── vins_millesimes.csv
│   └── vins_ordinaires.csv
│
├── Presentation/                  # Support de soutenance (non versionné)
│   ├── presentation_soutenance_P10.pptx
│   ├── diagramme_flux_pipeline.drawio
│   ├── diagramme_flux_pipeline.pdf
│  │
└── .gitignore
```

---

## 🚀 Installation et démarrage

### Prérequis

- **Docker** et **Docker Compose** installés
- **Linux** (testé sur Ubuntu VM)
- Ports disponibles : `8080` (Kestra UI), `8025` (MailHog UI), `1025` (SMTP), `5432` (Postgres)

### Démarrage rapide

```bash
# 1. Cloner le dépôt
git clone git@github.com:Melkia44/P10.git
cd P10

# 2. Placer les fichiers de données dans Data/
#    (Fichier_erp.xlsx, fichier_liaison.xlsx, Fichier_web.xlsx)

# 3. Lancer le script d'installation
chmod +x install/install_pipeline.sh
./install/install_pipeline.sh
```

Le script :
- Crée le réseau Docker `bottleneck-network`
- Lance Kestra + PostgreSQL + MailHog
- Attend que les services soient prêts
- Affiche les URLs d'accès

### Accès aux interfaces

| Interface | URL |
|-----------|-----|
| **Kestra UI** | http://localhost:8080 |
| **MailHog UI** | http://localhost:8025 |

### Arrêt

```bash
./install/stop_pipeline.sh
# ou
cd install && docker compose down
```

---

## ⚙️ Configuration

Toutes les variables sont centralisées en tête du workflow YAML :

```yaml
variables:
  zscore_threshold: 3          # Seuil de détection des outliers
  zscore_max_outlier_pct: 0.05 # Max 5% d'outliers acceptés par catégorie
  smtp_host: "mailhog"         # Nom de service Docker (stable)
  smtp_port: "1025"
  smtp_from: "kestra-pipeline@bottleneck.fr"
  smtp_to: "laurent.manager@bottleneck.fr"
```

> ⚠️ Ne pas utiliser d'IP fixe pour `smtp_host` — les IPs Docker changent à chaque `docker compose down -v`. Utiliser toujours le nom de service.

---

## 📊 Description des étapes du pipeline

### Étape 1 — Ingestion & Nettoyage
- Lecture des 3 fichiers Excel
- Dédoublonnage sur `product_id` (ERP) et `sku` (Web)
- Suppression des valeurs manquantes sur les clés de jointure
- Vérification critique : pipeline bloqué si fichier vide après nettoyage

### Étape 2 — Fusion
- JOIN 1 : ERP + Liaison sur `product_id`
- JOIN 2 : Résultat + Web sur `id_web = sku`
- Jointures `INNER` : seuls les produits présents dans les 3 sources sont conservés

### Étape 3 — Calcul du CA
- `ca_produit = price × total_sales` pour chaque produit
- Export du rapport trié par CA décroissant en `.xlsx`

### Étape 4 — Classification + Z-Score
- **Millésimés** : détection par regex `\b(19|20)\d{2}\b` dans le titre produit
- **Ordinaires** : tous les vins sans année dans le titre
- **Z-Score** : analyse statistique des prix par catégorie pour détecter les valeurs aberrantes (erreurs de saisie)

### Étape 5 — Tests de validation (8/8)
| Test | Critère |
|------|---------|
| Absence de doublons | `product_id` unique dans le dataset final |
| Absence de valeurs manquantes | Clés `product_id`, `price`, `post_title`, `id_web` non nulles |
| Cohérence volumétrie | Nb lignes fusionnées ≤ nb lignes ERP |
| CA positif | `ca_produit >= 0` pour tous les produits |
| CA cohérent | Vérification arithmétique `price × total_sales` |
| Classification complète | `millésimés + ordinaires = total produits` |
| Z-Score millésimés | < 5% d'outliers prix |
| Z-Score ordinaires | < 5% d'outliers prix |

### Étape 6 — Alerting SMTP
- **Succès** : email HTML envoyé à `laurent.manager@bottleneck.fr` avec récapitulatif des livrables
- **Échec** : email d'alerte envoyé automatiquement via le bloc `errors:` de Kestra
- Les emails sont interceptés localement par **MailHog** (visible sur http://localhost:8025)

---

## 📦 Livrables générés

| Fichier | Description |
|---------|-------------|
| `rapport_ca_par_produit.xlsx` | CA par produit trié décroissant |
| `vins_millesimes.csv` | Vins avec année détectée + millésime |
| `vins_ordinaires.csv` | Vins sans année dans le titre |
| `test_results.json` | Résultats détaillés des 8 tests |
| `classification_report.json` | Rapport Z-Score par catégorie |
| `fusion_report.json` | Métriques de jointure |
| `ingestion_report.json` | Métriques de nettoyage par source |

---

## 🔧 Points techniques notables

### Réseau Docker explicite
Tous les services partagent un réseau nommé `bottleneck-network`. Cela permet :
- La résolution DNS par nom de service (`mailhog`, `postgres`)
- L'isolation réseau du projet
- La stabilité des connexions inter-services

```yaml
networks:
  bottleneck-network:
    driver: bridge
    name: bottleneck-network
```

### SMTP sans TLS
MailHog ne supporte pas TLS. Le paramètre `transportStrategy: SMTP` est obligatoire sur les tâches `MailSend` pour forcer le protocole plain SMTP (sans chiffrement).

### Z-Score configurable
Le seuil Z-Score est une variable Kestra, modifiable sans toucher au code Python :
```yaml
variables:
  zscore_threshold: 3        # Modifier ici pour ajuster la sensibilité
  zscore_max_outlier_pct: 0.05
```

---

## 🐛 Résolution de problèmes fréquents

### Page de login Kestra au démarrage
Cause : volume PostgreSQL corrompu avec une ancienne session Enterprise.
```bash
docker compose down -v && docker compose up -d
```

### Connection refused sur le SMTP
Cause : IP hardcodée dans le workflow qui a changé après un `docker compose down -v`.
Solution : utiliser `mailhog` (nom de service) au lieu d'une IP fixe dans les variables du workflow.

### Warnings openpyxl dans les logs Kestra
```
UserWarning: Unknown extension is not supported and will be removed
```
Ce sont des warnings non bloquants liés au formatage Excel avancé. Le pipeline s'exécute correctement (statut SUCCESS).

---

## 👤 Auteur

**Mathieu** — Étudiant Master 2 Data Engineering, OpenClassrooms  
Dépôt : [github.com/Melkia44/P10](https://github.com/Melkia44/P10)

---

## 📄 Licence

Projet académique — OpenClassrooms P10
