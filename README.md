# Seguros Horizonte - AWS Infrastructure

Single-account, single-environment (prod) AWS infrastructure for Seguros Horizonte, a fictional insurance brokerage, in `sa-east-1`. Built with Terraform modules and designed with LGPD-oriented controls: encryption at rest and in transit, private data tier and least-privilege IAM. Multi-account and PCI-DSS are out of scope.

## Status

Work in progress, phase by phase. Validated with `terraform validate` and `terraform plan` only (never applied).

## Project Structure

    terraform/
    ├── main.tf        # wires the modules together
    ├── variables.tf
    ├── versions.tf
    └── modules/
        └── networking/  # VPC in 2 AZs, NAT, chained security groups
