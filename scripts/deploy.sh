#!/bin/bash
set -eoux pipefail

set -o allexport
source scripts/deploy.env
set +o allexport

gcloud config set project "${GOOGLE_CLOUD_PROJECT}"

CLOUD_RUN_RUNNER_SERVICE_ACCOUNT_EMAIL=${CLOUD_RUN_RUNNER_SERVICE_ACCOUNT_NAME}@${GOOGLE_CLOUD_PROJECT}.iam.gserviceaccount.com
DOCKER_NAME="${CLOUD_RUN_NAME}:${IMG_VERSION}"

# Build a docker image for the server and publish it to google container registry
gcloud builds submit --tag "eu.gcr.io/${GOOGLE_CLOUD_PROJECT}/${DOCKER_NAME}" mlflow-docker

# Fetch environment variables from secret manager
ENV_VARS=$(gcloud secrets versions access latest --secret=mlflow-env | awk '{print $1}' | paste -s -d, -)

# Concurrency of requests is controlled by Gunicorn server and corresponds to workers * threads parameters
gcloud beta run deploy "${CLOUD_RUN_NAME}" --image "eu.gcr.io/${GOOGLE_CLOUD_PROJECT}/${DOCKER_NAME}" \
  --region="${REGION}" \
  --timeout=10m \
  --platform="${PLATFORM}" \
  --ingress="${INGRESS}" \
  --max-instances=default \
  --concurrency=default \
  --allow-unauthenticated \
  --service-account="${CLOUD_RUN_RUNNER_SERVICE_ACCOUNT_EMAIL}" \
  --vpc-connector=vpc-connector-mlflow \
  --set-env-vars="${ENV_VARS}" \
  --set-secrets=MLFLOW_CREDENTIALS=mlflow-credentials:latest,MYSQL_CREDENTIALS=mysql-credentials:latest
