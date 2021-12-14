#!/bin/bash

export WSGI_AUTH_CREDENTIALS="${MLFLOW_CREDENTIALS}"
export _MLFLOW_SERVER_ARTIFACT_ROOT="${ARTIFACT_STORE}"
export _MLFLOW_SERVER_FILE_STORE="mysql+pymysql://${MYSQL_CREDENTIALS}@${MYSQL_HOST}/${MYSQL_DB}"

exec gunicorn --bind $SERVER_HOST:$SERVER_PORT --workers 1 --threads 8 --timeout 0 mlflow_app:app