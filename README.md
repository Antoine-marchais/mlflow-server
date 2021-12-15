# Serveur MLFlow

Ce dépôt de code permet de configurer et déployer un serveur mlflow sur GCP pour votre projet

## Mise en place

### Avec Terraform (Recommandé)

**A compléter**

### Avec un script

**A compléter**

### Manuelle

**1. Activation des APIs**

Exécuter le script pour activer toutes les APIs utilisées par le projet (nécessite de s'authentifier auprès du sdk gcloud)

```
gcloud auth login
gcloud config set project <my-project>
bash scripts/enable-apis.sh
```

**1bis. (Optionel) Création du réseau VPC pour les services utilisés par le serveur**

Dans la console GCP > Réseau VPC, créer un réseau VPC

**2. Création de la base de données**

Se rendre sur la console GCP > SQL et créer une base de données MySQL avec le nom mlflow_tracking_database:  
- Spécifier et noter le mot de passe pour l'utilisateur root.
- Aller dans la section connection:
  - déselectionner l'adresse publique
  - sélectionner l'adresse privée et sélectionné le réseau VPC créé (si réseau custom)
  - Créer le connecteur de service pour la connection
  - Attendre que l'instance soit créée
  - Ajouter une base de données `mlflow_tracking_database`

**3. Création du connecteur serverless**

Se rendre dans la console GCP > Réseau VPC > Accès VPC serverless et créer un connecteur VPC:
- L'appeler `vpc-connector-mlflow`
- Choisir le réseau créé (si réseau custom)
- Choisir un bloc d'IP /28 non dans les adresses internes autorisées (par exemple `10.0.0.0/28`): https://cloud.google.com/vpc/docs/vpc#manually_created_subnet_ip_ranges

**4. Création du compte de service**

Se rendre dans la console GCP > IAM > Comptes de services et créer un compte de service:
- L'appeler `run-mlflow`

**5. Création du bucket d'artefacts**

Se rendre dans la console GCP > Cloud Storage et créer un bucket pour les artefacts mlflow:
- noter le nom du bucket choisi
- Autoriser le compte de service `run-mlflow` à lire et écrire dans ce bucket avec le role `Storage Object Admin`

**6. Mise à jour des variables d'environnement**

Mettre à jour les fichiers `scripts/mlflow-env.env` et `scripts/deploy.env` avec les paramètres utilisés pour créer vos ressources.

**7. Création des secrets**

Se rendre dans la console GCP > Securité > Secret Manager et ajouter 3 secrets:
- Le secret `mlflow-env`, qui contient le contenu du fichier `scripts/mlflow-env.env`
- Le secret `mysql-credentials`, qui contient le login/mdp de la base de données sous la forme `root:<mdp-de-la-bdd>`
- Le secret `mlflow-credentials`, qui contient le login/mdp du service mlflow (**A créer) sous la forme `<login>:<mdp>`

Ajouter le compte de service `run-mlflow` en temps qu'accesseur de ces secrets.

**8. Déployer le service**

Déployer le service avec le script de déploiement. Ce script demande d'être authentifié avec la sdk Google Cloud.

```
gcloud auth login
bash scripts/deploy.sh
```

## Utilisation

### Interface MLFlow

L'interface graphique du serveur mlflow sera accessible à l'addresse du service `mlflow` créé. Pour obtenir l'url de connexion, se rendre sur la console GCP > Cloud Run > mlflow.

L'interface est sécurisée par un login/mdp qui peut être récupéré dans le secret manager `mlflow-credentials`

### Publication de métriques et modèles

Les métriques et modèles peuvent être publiés avec la librairie mlflow. Il faudra cependant préciser l'url du serveur dans le code ainsi que les login/mdp du serveur dans les variables d'environnement (enregistrés dans le secret manager `mlflow-credentials`).

Par exemple:
```python
import mlflow
import os

os.environ["MLFLOW_TRACKING_USERNAME"] = "<my_username>"
os.environ["MLFLOW_TRACKING_PASSWORD"] = "<my_password>"

mlflow.set_tracking_uri("<my_server_url>")

if not mlflow.get_experiment_by_name("test_experiment"):
    mlflow.create_experiment(name="test_experiment")
experiment = mlflow.get_experiment_by_name("test_experiment")

with mlflow.start_run(experiment_id=experiment.experiment_id):
    mlflow.log_param("param1", 23)
    mlflow.log_param("param2", "smth")
    mlflow.log_metric("accuracy", 0.95)
```
