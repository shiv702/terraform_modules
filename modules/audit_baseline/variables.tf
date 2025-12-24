variable "aws_account_id" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "enable_cloudtrail" {
  type    = bool
  default = true
}

variable "enable_config" {
  type    = bool
  default = true
}

variable "cloudtrail_multi_region" {
  type    = bool
  default = true
}

variable "cloudtrail_enable_cw_logs" {
  type    = bool
  default = true
}

variable "sns_email_subscriptions" {
  type    = map(string)
  default = {}
}

variable "config_managed_rules" {
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

variable "tags" {
  type    = map(string)
  default = {}
}
