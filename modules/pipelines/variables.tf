variable "aws_account_id" { type = string }
variable "name_prefix" { type = string }
variable "branch" { type = string, default = "main" }
variable "tags" { type = map(string), default = {} }

variable "pipeline_defs" {
  description = "Map of pipeline_name => { working_dir = string, tf_targets = list(string) }"
  type = map(object({
    working_dir = string
    tf_targets  = list(string)
  }))
}
