FROM python:3.9 AS builder

COPY requirements.txt .

# installing packages in a virtualenv
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install -r requirements.txt

# production stage
FROM python:3.9-slim
WORKDIR /app

# copy only the dependencies installation from the builder image
COPY --from=builder /opt/venv /opt/venv

# copy runtime source code
COPY entrypoint.sh .
COPY mlflow_app.py .

# update PATH environment variable
ENV PATH="/opt/venv/bin/:$PATH"

CMD ["/bin/bash", "entrypoint.sh"]