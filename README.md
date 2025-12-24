# Terraform Foundation (ap-south-1) — Audit + Networking + Optional CI/CD Pipelines

This repo contains:
- `modules/audit_baseline`: CloudTrail + AWS Config + SNS (plus optional basic CloudWatch alarms)
- `modules/network_baseline`: VPC + subnets (public/private) + IGW + NAT + route tables + tagging
- `modules/pipelines`: Optional CodePipeline/CodeBuild pipelines to run Terraform for Audit and Network roots

## Quick start (local apply)
1) Configure AWS credentials for the target account.
2) Copy `terraform.tfvars.example` to `terraform.tfvars` and edit values.
3) Run:
```bash
terraform init
terraform apply
```

## Notes
- Buckets are named using your account id to be globally unique.
- CodePipeline needs a repository (this module creates CodeCommit repos by default).
