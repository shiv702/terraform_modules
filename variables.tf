variable "aws_account_id" {
  description = "AWS account id where the resources will be deployed."
  type        = string
  default     = "970547338216"
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "ap-south-1"
}

variable "name_prefix" {
  description = "Prefix used for resource names."
  type        = string
  default     = "foundation"
}

variable "tags" {
  description = "Common tags applied to all resources via provider default_tags."
  type        = map(string)
  default = {
    ManagedBy = "Terraform"
    Project   = "Foundation"
  }
}

# ---------- Networking inputs ----------
variable "vpc_cidr" {
  description = "VPC CIDR."
  type        = string
  default     = "10.10.0.0/16"
}

variable "subnets" {
  description = <<EOT
Map of subnets to create. Keys are subnet names. Example:
{
  public-a  = { cidr="10.10.1.0/24", az="ap-south-1a", type="public"  }
  private-a = { cidr="10.10.101.0/24", az="ap-south-1a", type="private" }
}
EOT
  type = map(object({
    cidr = string
    az   = string
    type = string # "public" or "private"
    tags = optional(map(string), {})
  }))

  default = {
    public-a  = { cidr = "10.10.1.0/24",   az = "ap-south-1a", type = "public" }
    public-b  = { cidr = "10.10.2.0/24",   az = "ap-south-1b", type = "public" }
    private-a = { cidr = "10.10.101.0/24", az = "ap-south-1a", type = "private" }
    private-b = { cidr = "10.10.102.0/24", az = "ap-south-1b", type = "private" }
  }
}

variable "nat_gateway_strategy" {
  description = "NAT strategy: none | single | per_az"
  type        = string
  default     = "single"

  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_gateway_strategy)
    error_message = "nat_gateway_strategy must be one of: none, single, per_az"
  }
}

# ---------- Audit inputs ----------
variable "enable_cloudtrail" {
  description = "Enable CloudTrail."
  type        = bool
  default     = true
}

variable "enable_config" {
  description = "Enable AWS Config."
  type        = bool
  default     = true
}

variable "cloudtrail_multi_region" {
  description = "Create a multi-region CloudTrail."
  type        = bool
  default     = true
}

variable "cloudtrail_enable_cloudwatch_logs" {
  description = "Send CloudTrail to CloudWatch Logs."
  type        = bool
  default     = true
}

variable "sns_email_subscriptions" {
  description = "Map of subscription name => email address."
  type        = map(string)
  default     = {}
}

variable "config_managed_rules" {
  description = <<EOT
Managed AWS Config rules to create. Keys are rule names. Example:
{
  s3_public_read = { identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED" }
}
EOT
  type = map(object({
    identifier       = string
    input_parameters = optional(map(string), {})
    scope = optional(object({
      compliance_resource_types = optional(list(string))
      compliance_resource_id    = optional(string)
      tag_key                   = optional(string)
      tag_value                 = optional(string)
    }))
  }))
  default = {}
}

# ---------- Optional pipelines ----------
variable "enable_pipelines" {
  description = "Create CodePipelines (Audit and Networking) that run Terraform via CodeBuild."
  type        = bool
  default     = false
}

variable "pipeline_branch" {
  description = "Branch to watch (CodeCommit)."
  type        = string
  default     = "main"
}

