aws_account_id = "970547338216"
aws_region     = "ap-south-1"

name_prefix = "foundation"

tags = {
  ManagedBy = "Terraform"
  Project   = "Foundation"
  Owner     = "platform-team"
  Env       = "prod"
}

# --- Networking ---
vpc_cidr = "10.10.0.0/16"

subnets = {
  public-a  = { cidr = "10.10.1.0/24",   az = "ap-south-1a", type = "public"  }
  public-b  = { cidr = "10.10.2.0/24",   az = "ap-south-1b", type = "public"  }
  private-a = { cidr = "10.10.101.0/24", az = "ap-south-1a", type = "private" }
  private-b = { cidr = "10.10.102.0/24", az = "ap-south-1b", type = "private" }
}

nat_gateway_strategy = "single" # none | single | per_az

# --- Audit ---
enable_cloudtrail              = true
enable_config                  = true
cloudtrail_multi_region        = true
cloudtrail_enable_cloudwatch_logs = true

sns_email_subscriptions = {
  security = "security-team@example.com"
}

config_managed_rules = {
  s3_public_read = { identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED" }
  s3_public_write = { identifier = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED" }
}

# --- Pipelines ---
enable_pipelines = false
pipeline_branch  = "main"
