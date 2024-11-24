FROM alpine

ENV POETRY_VERSION=1.1.13 \
    HOME=/home/user \
    PATH="${HOME}/.local/bin:${PATH}" \
    PORT=8080

# Use a non-root user for improved security
RUN addgroup -S user && \
    adduser -S -G user -h $HOME user && \
    apk add --no-cache \
        curl \
        python3-dev \
        gcc \
        libressl-dev \
        musl-dev \
        libffi-dev && \
    curl -sSL https://install.python-poetry.org | \
    python3 - --version $POETRY_VERSION && \
    mkdir /home/user/.ssh

# Copy application code and SSH key (consider alternatives for secrets management)
COPY app/ /app/
COPY ssh-keys/id_rsa /home/user/.ssh/id_rsa

# Install dependencies in a single layer to reduce image size
RUN cd /app && poetry install --no-dev --no-root --no-interaction --no-ansi

# Switch to the non-root user
USER user

# Define the entrypoint and command
ENTRYPOINT ["poetry", "run"]
CMD ["uvicorn", "--host=0.0.0.0", "--port=$PORT", "--workers=$UVICORN_WORKERS"]
