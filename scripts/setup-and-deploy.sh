#!/bin/bash

set -eou pipefail

# Setting project variables

read -p 'please provide the gcp project id: ' GCP_PROJECT
read -p 'please provide the deployment region [europe-west1]' REGION
read -p 'please provide a username for the server [axionable]' MLFLOW_USER
echo "You will be asked to authenticate with a google account owner of the project"
REGION=${REGION:-europe-west1}
MLFLOW_USER=${MLFLOW_USER:-axionable}
DB_INSTANCE=mlflow-db

# setting gcloud config
gcloud config set project $GCP_PROJECT
gcloud auth login

echo "\n\n====== Enabling project APIs ======\n\n"

source scripts/enable-apis.sh

# Creating the VPC network

echo "\n\n====== Creating Network Topology ======\n\n"

gcloud compute networks create mlflow-vpc --subnet-mode=custom

gcloud compute networks subnets create "mlflow-vpc-serverless-connector-subnet" \
  --network=mlflow-vpc \
  --region=$REGION \
  --range=10.0.0.0/28

# Peering the network with gcp managed services
gcloud compute addresses create "google-managed-services-mlflow-vpc" \
  --global \
  --purpose=VPC_PEERING \
  --prefix-length=16 \
  --network=mlflow-vpc

gcloud services vpc-peerings connect \
  --ranges="google-managed-services-mlflow-vpc" \
  --network=mlflow-vpc

# Create VPC serverless connector
gcloud compute networks vpc-access connectors create vpc-connector-mlflow \
  --region=$REGION \
  --subnet="mlflow-vpc-serverless-connector-subnet"

# Create database

echo "\n\n====== Creating metadata database ======\n\n"

DB_ROOT_PWD=$(cat /dev/random \
 | LC_CTYPE=C tr -dc "[:alnum:]" \
 | fold -w ${1:-20} \
 | head -n 1) || true

gcloud beta sql instances create $DB_INSTANCE \
  --database-version=MYSQL_5_7 \
  --region=$REGION \
  --root-password=$DB_ROOT_PWD \
  --cpu=4 \
  --memory=26GiB \
  --no-assign-ip \
  --network=mlflow-vpc

DB_HOST=$(gcloud sql instances describe $DB_INSTANCE --format="value(ipAddresses[0].ipAddress)")

gcloud sql databases create mlflow_tracking_database --instance=$DB_INSTANCE

# Create Service Account

echo "\n\n====== Creating MLFlow Service Account ======\n\n"

gcloud iam service-accounts create run-mlflow

# Create artifacts bucket

echo "\n\n====== Creating Artifacts Bucket ======\n\n"

BUCKET_HASH=$(cat /dev/random \
  | LC_CTYPE=C tr -dc "[:alnum:]" \
  | fold -w ${1:-20} \
  | head -n 1 \
  | tr '[:upper:]' '[:lower:]') || true

ARTIFACTS_BUCKET="gs://${GCP_PROJECT}-${BUCKET_HASH}"
gsutil mb -l europe-west1 $ARTIFACTS_BUCKET
gsutil iam ch "serviceAccount:run-mlflow@${GCP_PROJECT}.iam.gserviceaccount.com:objectAdmin" ${ARTIFACTS_BUCKET}

# Update environment variables
sed -i '' "s/<my-db-internal-ip>/$DB_HOST/g" scripts/mlflow-env.env
sed -i '' "s#<my-artifacts-bucket>#$ARTIFACTS_BUCKET#g" scripts/mlflow-env.env
sed -i '' "s/<my-gcp-project>/$GCP_PROJECT/g" scripts/deploy.env
sed -i '' "s/<my-gcp-region>/$REGION/g" scripts/deploy.env

# Create secrets

echo "\n\n====== Creating Secrets For DB and Server Credentials ======\n\n"

MLFLOW_PWD=$(cat /dev/random \
 | LC_CTYPE=C tr -dc "[:alnum:]" \
 | fold -w ${1:-20} \
 | head -n 1) || true

echo -n "root:${DB_ROOT_PWD}" \
  | gcloud secrets create mysql-credentials --data-file=-
echo -n "${MLFLOW_USER}:${MLFLOW_PWD}" \
  | gcloud secrets create mlflow-credentials --data-file=-
gcloud secrets create mlflow-env --data-file=scripts/mlflow-env.env

gcloud secrets add-iam-policy-binding mysql-credentials \
  --member="serviceAccount:run-mlflow@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role=roles/secretmanager.secretAccessor
gcloud secrets add-iam-policy-binding mlflow-credentials \
  --member="serviceAccount:run-mlflow@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role=roles/secretmanager.secretAccessor
gcloud secrets add-iam-policy-binding mlflow-env \
  --member="serviceAccount:run-mlflow@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --role=roles/secretmanager.secretAccessor

echo "\n\n====== Deploying MLFlow Server to Cloud Run ======\n\n"

source scripts/deploy.sh
