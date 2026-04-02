# Google Managed Prometheus Terraform Project

This project uses Terraform to deploy Google Managed Prometheus infrastructure on Google Cloud Platform (GCP).

## Project Structure

- `main.tf`: Main Terraform configuration file.
- `variables.tf`: Input variables for the Terraform configuration.
- `outputs.tf`: Output values from the Terraform configuration.
- `modules/`: Contains reusable Terraform modules.
  - `modules/vpc`: VPC network configuration.
  - `modules/gke`: GKE cluster configuration.

## Getting Started

### Prerequisites

- Google Cloud SDK
- Terraform
- Authenticated GCP account

### Deployment

1. Initialize Terraform:
   ```bash
   terraform init
   ```

2. Plan the deployment:
   ```bash
   terraform plan
   ```

3. Apply the deployment:
   ```bash
   terraform apply
   ```

## Configuration

The project can be configured using the variables defined in `variables.tf`. Key variables include:

- `project_id`: Your GCP project ID.
- `region`: GCP region for resource deployment.
- `name`: A unique name for your deployment.

## Resources Deployed

- GCP Project
- VPC Network
- GKE Cluster
- Google Managed Prometheus setup (implied by the project name and GKE deployment)

## Cleanup

To destroy the deployed resources:

```bash
terraform destroy
```
