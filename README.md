Apheris Take Home Assignment for Deployment Engineer Positions
--------------------------------------------------------------

### 1\. Dockerfile Review and Best Practices

**Dockerfile**

```Dockerfile
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
```
**Fixes and Best Practices:**

*   **Base Image:** Alpine is lightweight but may lead to build-time and runtime issues due to musl libc. Consider using a Python-specific base image like `python:3.9-slim`.

*   **Non-root User:** Created a dedicated user (user) and switched to it for running the application. This improves container security by preventing the application from running with root privileges.
    
*   **Single Layer for Dependencies:** Combined the installation of dependencies into a single RUN instruction. This helps to reduce the overall size of the Docker image and improve build times.
    
*   **Secrets Management:** Never include private SSH keys directly in the image (`id_rsa`). Consider using secrets management solutions like Docker secrets, Kubernetes secrets, or HashiCorp Vault.

*   **Environment Variables:** Use `.env` files instead of hardcoding environment variables (`PORT`, `POETRY_VERSION`, etc.).

*   **RUN Commands:** Combine `RUN` commands into a single layer to reduce image size.

*   **Permissions:** Ensure permissions are restricted to prevent unprivileged access to sensitive files like `.ssh/id_rsa`.

*   **User Context:** Switch to the unprivileged user as early as possible.

*   **Entrypoint:** Avoid hardcoding `poetry`. Use a wrapper script or point to an entrypoint script.
    
### Task 2: IAM Role and ECR Access

## Missing Parts

**IAM Role Setup:**

1.  Create an IAM role in the AWS account with the ECR repository.
2.  Attach a policy to allow the role to push/pull images to/from the ECR repository.

    **Example policy:**

    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": [
            "ecr:GetAuthorizationToken",
            "ecr:BatchCheckLayerAvailability",
            "ecr:CompleteLayerUpload",
            "ecr:UploadLayerPart",
            "ecr:InitiateLayerUpload",
            "ecr:PutImage"
          ],
          "Resource": "arn:aws:ecr:<region>:<account_id>:repository/<repository_name>"
        }
      ]
    }
    ```

**Trust Relationship:**

*   Allow the IAM user in the second account to assume the role:

    ```json
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "AWS": "arn:aws:iam::<user_account_id>:user/<iam_user>"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }
    ```

**Assume Role:**

*   The IAM user assumes the role using `aws sts assume-role` to get temporary credentials.

**Push Docker Image:**

*   Use the temporary credentials to authenticate and push the Docker image:

    ```bash
    $ aws ecr get-login-password --region <region> | docker login --username AWS --password-stdin <account_id>.dkr.ecr.<region>.amazonaws.com
    $ docker tag <image>:<tag> <account_id>.dkr.ecr.<region>.amazonaws.com/<repository_name>
    $ docker push <account_id>.dkr.ecr.<region>.amazonaws.com/<repository_name>
    ```

### 3\. Service Availability and AZ Distribution

## Potential Problems

**AZ Dependency:**

*   Placing a majority of instances (3 out of 4) in a single Availability Zone (us-east-1) makes the service vulnerable to outages within that zone. If one AZ goes down (e.g., `us-west-1a`), 25% of instances are unavailable, leaving only 3 instances. Any additional instance failure causes the service to fail.

**Latency:**

*   Cross-region communication (e.g., between `us-east-1` and `us-west-1`) increases latency. Having one instance in a geographically distant Availability Zone (`us-west-1a`) can introduce latency for clients accessing the service from the east coast.

**Cost:**

*   Cross-region traffic incurs additional costs.

**Recommendations:**

*   **Distribute Instances Evenly:** Distribute the instances evenly across Availability Zones in the same region (e.g., one instance in each of `us-east-1a`, `us-east-1b`, `us-east-1c`, and `us-east-1d`).
    
*   **Consider Multiple Regions:** For higher availability, consider deploying the service in multiple regions.

### 4\. Kubernetes Pod Load Skewing

**Possible Problems:**

*   **Node Resource Imbalance:** Some nodes might have more resources (CPU, memory) than others, leading to uneven pod scheduling and load distribution.
    
*   **Service Affinity:** The Kubernetes service might not be distributing traffic evenly across the pods. This could be due to issues with the service's load balancing algorithm or session affinity.
    
*   **Pod Anti-affinity:** If pods have anti-affinity rules, they might be spread out too thinly, leading to some pods receiving more traffic than others.
    
*   **Application Issues:** The application itself might have issues that cause uneven load distribution, such as inefficient code or uneven data partitioning.

**Recommendations:**

*   Use `externalTrafficPolicy: Local` for better load balancing.
*   Use an Ingress Controller with algorithms like `round-robin` or `least-connections`.

### 5\. Pod Loss During Node Updates

**Possible Fixes:**

*   **PodDisruptionBudgets (PDBs):** Define PDBs to limit the number of pods that can be evicted simultaneously during node updates. This ensures that a minimum number of pods remain available.
    
*   **Rolling Updates:** Use rolling updates for deployments to gradually update pods, minimizing disruption.
    
*   **Graceful Termination:** Implement graceful termination in the application to allow pods to finish processing requests before shutting down.
    
*   **Resource Requests and Limits:** Set appropriate resource requests and limits for pods to prevent resource contention and improve stability.
    
*   **Liveness and Readiness Probes:** Use liveness and readiness probes to monitor the health of pods and ensure that only healthy pods receive traffic.
    

### 6\. Remote State Backend in Terraform

A remote state backend in Terraform stores the state of your infrastructure in a remote location (e.g., cloud storage, a database) instead of locally on your machine.

**Benefits:**

*   **Collaboration:** Enables multiple team members to work on the same infrastructure.
    
*   **State Locking:** Prevents concurrent modifications and state corruption.
    
*   **Secure Storage:** Provides a secure and centralized location for storing sensitive state information.
    
*   **Versioning:** Allows for state history tracking and rollback to previous states.
    

### 7\. Service Replication for Increased Availability

To achieve 99% availability with a service that has 95% uptime, you would need approximately **3 replicas**.

**Calculation:**

*   Probability of a single service being down: 1 - 0.95 = 0.05
    
*   Probability of all 3 replicas being down: 0.05 \* 0.05 \* 0.05 = 0.000125
    
*   Availability with 3 replicas: 1 - 0.000125 = 0.999875 (approximately 99.99%)
    

**Note:** This is a simplified calculation. In reality, factors like network reliability, load balancing, and dependencies between services can also affect overall availability.
