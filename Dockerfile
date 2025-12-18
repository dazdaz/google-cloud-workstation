# Google Cloud Workstations Custom Image
# Built with Docker builder (not Kaniko) to preserve image metadata
FROM us-central1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest

# Disable gcloud usage reporting prompt
RUN gcloud config set disable_usage_reporting false

# Install Terraform without USER switching (use sudo instead)
ARG TERRAFORM_VERSION=1.7.0
RUN sudo curl -LO https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
    sudo unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/local/bin/ && \
    sudo rm terraform_${TERRAFORM_VERSION}_linux_amd64.zip

# Copy and install startup scripts (for VS Code extension installation)
COPY scripts/120-install-extensions.sh /etc/workstation-startup.d/120-install-extensions.sh
RUN sudo chmod +x /etc/workstation-startup.d/120-install-extensions.sh
